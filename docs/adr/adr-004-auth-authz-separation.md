# ADR-004: 인증/인가 분리 — Keycloak 순수 인증 + Console DB RBAC

> **상태**: Accepted
> **일자**: 2026-04-22
> **결정자**: Platform TG

## 컨텍스트

Console은 Organization/Project 단위의 접근 제어가 필요하다. 사내 Keycloak이 이미 SSO 인프라로 운영 중이며, 인증과 인가의 책임 분리 방식을 결정해야 한다.

초기 설계에서는 Keycloak의 그룹/역할 기능을 활용하여 RBAC 전체를 Keycloak에 위임하는 방안을 검토했으나, 최종적으로 인증만 Keycloak에 위임하고 인가는 Console DB에서 자체 관리하는 방식으로 결정했다.

## 선택지

### 1. Keycloak SSOT (인증 + 인가 모두 Keycloak) — 미채택

Keycloak 그룹으로 Org 소속을 관리하고, Client Role/Realm Role로 권한을 표현.

**장점**:
- 권한 데이터의 단일 원천 (Keycloak)
- ID 토큰/Access 토큰에 그룹/역할 클레임 포함 → Console DB 조회 불필요

**단점**:
- **Project ACL 불가**: Keycloak 그룹은 계층적 소속만 표현. "사용자 A는 Project X에 write, Project Y에 read" 같은 세밀한 리소스별 ACL을 표현할 수 없음
- **그룹 폭발**: Organization × Project × 역할 조합으로 그룹 수가 급격히 증가
- **Keycloak 팀 부담**: Console 전용 그룹 구조를 Keycloak Realm에 생성해야 하며, 타 서비스와의 그룹 충돌 우려
- **역할 추가 어려움**: 새로운 권한 수준이나 기능별 권한 추가 시 Keycloak 설정 변경 필요

### 2. Hybrid (인증 + Org 소속은 Keycloak, 인가는 Console DB) — 미채택

Keycloak 그룹으로 Org 소속을 관리하고, Project 권한은 Console DB에서 관리.

**장점**:
- Org 소속을 토큰 클레임으로 전달 가능
- Keycloak의 그룹 기능 일부 활용

**단점**:
- **두 원천 관리**: Org 소속(Keycloak) + Project 권한(Console DB)이 분리되어 동기화 로직 필요
- **정합성 리스크**: Keycloak 그룹 변경과 Console DB 변경 간 불일치 가능
- **Keycloak 의존성**: 그룹 변경 시 Keycloak Admin API 호출 필요 → 외부 서비스 장애가 권한 관리에 영향

### 3. Console DB 전량 (인증만 Keycloak) — 채택

Keycloak은 **OIDC 로그인/토큰 발급만** 담당. Org 소속, 역할, Project ACL 전부 Console DB에서 관리.

**장점**:
- **단일 원천**: 모든 권한 데이터가 Console DB에 존재. 동기화 불필요
- **Project ACL 지원**: `project_permissions` 테이블로 사용자별 Project 단위 세밀한 접근 제어
- **Keycloak 팀 부담 최소**: OIDC Client 등록 + Service Account 권한 부여만 요청. 그룹/역할 구조 불필요
- **확장 자유**: 기능별 권한, 리소스별 ACL 등 자유롭게 추가 가능
- **장애 격리**: Keycloak 장애 시 신규 로그인만 불가. 기존 세션 사용자의 권한 관리는 정상 동작

**단점**:
- 매 요청 시 Console DB에서 멤버십/권한 조회 필요 (세션 캐싱으로 완화)
- 사용자 정보(이름/이메일) 표시 시 Keycloak Admin API 실시간 조회 필요

## 결정

**Console DB 전량 관리 (인증만 Keycloak) 채택**.

## 핵심 설계

| 영역 | 설명 |
|------|------|
| **인증** | Keycloak OIDC Authorization Code Flow. `aap-console` Confidential Client |
| **Org 역할** | `org_memberships` 테이블: `user_sub` + `organization_id` + `role(admin/write/read)` |
| **Project ACL** | `project_permissions` 테이블: `org_membership_id` + `project_id` + `role(write/read)` |
| **super_admin** | 유일한 예외. Keycloak Realm Role `super_admin`으로 판별. 플랫폼 전체 관리 권한 |
| **PII 미저장** | Console DB에 `user_sub`만 저장. 이메일/이름은 Keycloak Admin API로 실시간 조회 |

## 관련 문서

- PRD Section FR-2: 접근제어 (RBAC)
- HLD Section 8: 인증/인가
