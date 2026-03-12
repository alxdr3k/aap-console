# ADR-003: 외부 API 연동 방식 — Terraform Provider vs 직접 호출

> **상태**: Accepted
> **일자**: 2026-03-12
> **결정자**: Console 팀

## 컨텍스트

Console은 Keycloak과 Langfuse를 프로그래밍 방식으로 관리해야 한다:

- **Keycloak**: Realm Client 생성/삭제, Protocol Mapper 설정, Service Account Role 부여 (FR-4)
- **Langfuse**: Organization/Project 생성/삭제, SDK Key 발급 (FR-5)

초기 설계에서는 Terraform Provider를 통한 선언적 관리를 검토했으나, 최종적으로 각 서비스의 API를 직접 호출하는 방식을 채택했다.

## 선택지

### 1. Terraform Provider — 미채택

Keycloak Terraform Provider (`mrparkers/keycloak`)와 Langfuse 리소스를 Terraform으로 관리.

**장점**:
- 선언적 리소스 관리 — state 파일 기반 drift detection
- Plan/Apply 단계 분리로 변경 사항 사전 검토 가능
- Terraform 생태계의 성숙한 state 관리 활용

**단점**:
- **Langfuse Terraform Provider 부재**: 공식/커뮤니티 Provider가 존재하지 않음. Custom Provider 개발 필요
- **Terraform 실행 오버헤드**: Client 1개 생성에도 `terraform init → plan → apply` 전체 사이클 필요. 프로비저닝 레이턴시 증가
- **State 파일 관리 복잡도**: 테넌트별 state 분리 시 수백 개의 state 파일 관리 필요
- **부분 실패 복구 어려움**: Terraform의 all-or-nothing 특성상, 멀티 서비스(Keycloak + Langfuse + Config Server) 걸친 트랜잭션 제어 불가
- **디버깅 난이도**: Terraform Provider 내부 오류 시 원인 추적 어려움

### 2. 직접 API 호출 — 채택

각 서비스의 API를 Ruby Client 클래스에서 직접 호출.

- Keycloak: Admin REST API (`KeycloakClient`)
- Langfuse: 내부 tRPC API (`LangfuseClient`, ADR-002 참조)
- Config Server: Admin API (`ConfigServerClient`)

**장점**:
- **즉시 실행**: HTTP 호출 즉시 반영. Terraform init/plan 오버헤드 없음
- **세밀한 에러 핸들링**: 서비스별 실패를 독립적으로 처리. Saga 패턴으로 보상 트랜잭션 구현 가능 (ADR-001)
- **단순한 의존성**: Terraform 바이너리, Provider 플러그인, state backend 불필요
- **Langfuse 호환**: tRPC API를 직접 호출하므로 별도 Provider 개발 불필요

**단점**:
- Drift detection 없음 — Console DB와 외부 서비스 간 불일치 가능 (Health Check FR-9로 완화)
- Client 코드 직접 유지보수 필요 (API 변경 시 수동 대응)

## 결정

**직접 API 호출 방식 채택**.

핵심 이유:
1. Langfuse Terraform Provider가 존재하지 않아 Custom Provider 개발이 불가피
2. Terraform 실행 사이클의 레이턴시가 프로비저닝 UX에 부정적
3. Saga 패턴 기반 보상 트랜잭션과 Terraform의 선언적 모델이 상충
4. Console은 인프라 프로비저닝이 아닌 **서비스 설정 자동화** — Terraform의 강점(인프라 lifecycle)과 맞지 않음

## 영향

| 영역 | 영향 |
|------|------|
| 코드 구조 | `app/clients/` 디렉토리에 서비스별 Client 클래스 구현 |
| 에러 처리 | Saga 패턴 + 보상 트랜잭션으로 멀티 서비스 정합성 유지 (ADR-001) |
| 정합성 검증 | Health Check (FR-9)로 Console DB ↔ 외부 서비스 간 drift 감지 |
| 테스트 | 서비스별 통합 테스트 필요 (docker-compose로 Keycloak/Langfuse 컨테이너 기동) |

## 관련 문서

- [ADR-001: 프로비저닝 오케스트레이션](./adr-001-provisioning-orchestration.md) — 직접 구현 + Saga 패턴
- [ADR-002: Langfuse API 연동 전략](./adr-002-langfuse-api-strategy.md) — tRPC 선택 상세
- PRD Section 3: 시스템 아키텍처 개요
- HLD Section 7: 외부 API Client
