# ADR-001: 프로비저닝 오케스트레이션 방식 선정

> **상태**: Accepted
> **일자**: 2026-03-11
> **결정자**: Platform TG
> **결정**: 직접 구현 (Rails 내 Saga 패턴)

---

## 배경

FR-7/8 구현을 위해 다단계 프로비저닝 파이프라인이 필요하다. Project 생성/수정/삭제 시 3개 외부 서비스(Keycloak, Langfuse, Config Server)에 순차/병렬로 리소스를 생성하고, 실패 시 보상 트랜잭션으로 롤백해야 한다.

**필요 기능**: 병렬 단계 실행, 재시도(exponential backoff), 보상 트랜잭션(롤백), 상태 저장, 실시간 진행률, 크래시 복구

---

## 후보 비교

### 1. Terraform + Custom Provider

| 항목 | 평가 |
|------|------|
| **접근** | 선언적 IaC. `.tf` 파일 동적 생성 → `terraform apply` 실행 |
| **Provider 현황** | Keycloak: 있음 ([mrparkers/keycloak](https://registry.terraform.io/providers/mrparkers/keycloak/latest)). **Langfuse: 없음. Config Server: 없음** |
| **병렬 실행** | 자동 (의존성 그래프 기반) |
| **롤백** | `terraform destroy`로 리소스 정리 |
| **상태 저장** | `.tfstate` 파일 (Project당 1개) |
| **실시간 진행률** | stdout 파싱 필요 → ActionCable 연동 어색 |

**불채택 사유**:
- Provider 2개를 **Go로 직접 작성** 필요 (~2,000줄 Go + 빌드 파이프라인). Ruby 프로젝트에 Go 코드베이스 추가
- Rails 앱에서 CLI subprocess(`system("terraform apply")`) 실행 → 에러 핸들링, 타임아웃, 프로세스 관리 복잡
- `.tfstate`에 Secret 평문 저장 (보안 위험)
- `terraform init` 오버헤드. API 3개 직접 호출하면 2~3초면 끝나는 작업에 불필요
- **문제 도메인 불일치**: Terraform은 "인프라를 코드로 관리"하는 도구. 우리는 "애플리케이션 레벨 리소스를 API로 오케스트레이션"하는 문제

### 2. Dynflow (Red Hat)

| 항목 | 평가 |
|------|------|
| **접근** | Ruby 워크플로우 엔진. Plan → Run → Finalize 3단계 라이프사이클 |
| **GitHub** | [Dynflow/dynflow](https://github.com/Dynflow/dynflow) — 130 stars, v2.0.0 (2025-12), MIT |
| **프로덕션 사례** | Foreman/Katello (Red Hat Satellite) — 대규모 서비스 오케스트레이션 |
| **병렬 실행** | 자동 감지 (의존성 없는 Action을 병렬 실행) |
| **재시도** | resume/skip 내장 |
| **롤백** | **"planned" 상태** — 보상 트랜잭션은 직접 구현 필요 |
| **상태 저장** | DB 자동 직렬화 |
| **크래시 복구** | 자동 (상태 직렬화 + 재개) |

**불채택 사유**:
- 가장 빡센 부분인 **보상 트랜잭션이 공짜가 아님** — 어차피 직접 구현 필요
- 문서 부족. 사실상 Foreman 소스코드가 문서 역할 → 학습 비용이 직접 구현 비용과 비슷
- 별도 executor 설정 필요. SQLite + SolidQueue 스택과의 궁합 미검증
- 우리 단계가 4~5개로 단순 (Foreman은 수십 개 단계를 관리하는 유스케이스)

**비고**: 프로비저닝 단계가 20개 이상으로 복잡해지면 재검토 가치 있음

### 3. Temporal.io Ruby SDK

| 항목 | 평가 |
|------|------|
| **접근** | 분산 워크플로우 엔진. Durable execution |
| **GitHub** | [temporalio/sdk-ruby](https://github.com/temporalio/sdk-ruby) — 136 stars, Ruby 3.3+ |
| **기능** | 모든 요구사항 네이티브 충족 (Saga, 병렬, 재시도, 상태, 크래시 복구) |

**불채택 사유**:
- **Temporal Server 별도 운영 필요** (Java/Go 기반 분산 시스템). 인프라 복잡도 대폭 증가
- 4~5단계 오케스트레이션에 Temporal은 과도한 인프라 투자

### 4. 기타 Ruby Gems

| Gem | Stars | 평가 | 사유 |
|-----|-------|------|------|
| [Novel](https://github.com/davydovanton/novel) | 60 | 2021년 이후 관리 안 됨 | 프로덕션 사용 불가 |
| [Sagas](https://github.com/arjunlol/Sagas) | 15 | 상태 저장/병렬/재시도 없음 | PoC 수준 |
| [Gush](https://github.com/chaps-io/gush) | 1,100 | DAG 병렬 처리 우수. 보상 트랜잭션 없음 | Redis 필요 + 롤백 DIY |

---

## 결정: 직접 구현

### 근거

1. **단계 수가 적다** — 4~5개 단계. 외부 라이브러리의 추상화 이점보다 학습/통합 비용이 더 큼
2. **보상 트랜잭션이 핵심** — 어떤 라이브러리를 써도 이 부분은 직접 구현. 그렇다면 전체를 직접 구현해도 추가 비용이 크지 않음
3. **Rails 스택과 자연스러운 통합** — SolidQueue, ActionCable, Turbo Streams와 직접 연동
4. **완전한 제어** — 디버깅, 장애 대응, 기능 확장에 유리
5. **의존성 최소화** — 외부 gem 없이 순수 Rails 코드

### 구현 규모 추정

| 영역 | LOC |
|------|-----|
| Core (Orchestrator + StepRunner + RollbackRunner) | ~300 |
| Step 구현체 5~6개 | ~250 |
| 엣지 케이스 (크래시 복구, 병렬 부분 실패, 동시성) | ~300 |
| Model 상태 관리 | ~100 |
| Job + Channel | ~50 |
| **프로덕션 코드 합계** | **~1,000** |
| 테스트 (실패 시나리오 포함) | ~1,500 |

### 주요 엣지 케이스 대응

| 엣지 케이스 | 대응 |
|------------|------|
| **크래시 복구** | SolidQueue 재시도 + Step별 `already_completed?` 멱등성 체크 |
| **병렬 부분 실패** | 성공한 병렬 Step만 선별 롤백 후 이전 단계 역순 롤백 |
| **재시도 중 worker 블록** | Step 내 in-process retry (Thread.sleep). 전체 Job은 SolidQueue timeout으로 보호 |
| **롤백 실패** | `rollback_failed` 상태 + 진단 정보 기록. 관리자 수동 개입 안내 |
| **동시성 제어** | 앱 레벨 체크 (동일 project에 active job 있으면 거부) + DB unique constraint |

---

## 참고 자료

- [Dynflow GitHub](https://github.com/Dynflow/dynflow)
- [Temporal Ruby SDK](https://github.com/temporalio/sdk-ruby)
- [Terraform Keycloak Provider](https://registry.terraform.io/providers/mrparkers/keycloak/latest)
- [Saga Pattern (microservices.io)](https://microservices.io/patterns/data/saga.html)
