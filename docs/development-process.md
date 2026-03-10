# AAP Console — TDD 개발 프로세스 가이드

> 이 문서는 AAP Console 개발 시 TDD(Test-Driven Development) 기반으로 작업하는 구체적인 프로세스를 정의한다.

---

## 1. 개발 사이클 (Red → Green → Refactor)

모든 기능 구현은 아래 사이클을 따른다:

```
1. RED    — 실패하는 테스트를 먼저 작성한다
2. GREEN  — 테스트를 통과하는 최소한의 코드를 작성한다
3. REFACTOR — 테스트가 통과하는 상태를 유지하면서 코드를 정리한다
```

### 1.1 단계별 상세

**RED (테스트 작성)**:
- 구현하려는 동작을 테스트로 먼저 표현한다
- 테스트를 실행하여 **실패하는 것을 확인**한다 (이 단계를 건너뛰지 않는다)
- 실패 메시지가 의도한 대로인지 확인한다 (예: "undefined method" vs "expected X got Y")

**GREEN (최소 구현)**:
- 테스트를 통과시키는 **가장 단순한 코드**를 작성한다
- 미래 요구사항을 예측하여 추가 구현하지 않는다
- 하드코딩이라도 괜찮다 — 다음 테스트가 일반화를 강제한다

**REFACTOR (정리)**:
- 중복 제거, 네이밍 개선, 메서드 추출 등
- **테스트를 계속 실행하면서** 리팩토링한다
- 새로운 기능을 추가하지 않는다

---

## 2. 테스트 계층 및 작성 전략

### 2.1 테스트 유형

| 유형 | 도구 | 대상 | 비율 목표 |
|------|------|------|-----------|
| **Unit Test** | RSpec | Model, Service Object, PORO | 70% |
| **Integration Test** | RSpec + WebMock/VCR | 외부 API 연동 (Keycloak, Langfuse), Job 실행 | 20% |
| **System Test** | RSpec + Capybara | E2E 워크플로우 (Project 생성 전체 흐름) | 10% |

### 2.2 테스트 작성 순서 (Outside-In)

기능 개발 시 **바깥에서 안쪽으로** 테스트를 작성한다:

```
1. System/Request Spec  — "사용자가 이 API를 호출하면 어떤 응답이 와야 하는가"
2. Service Object Spec  — "이 서비스 객체가 어떤 동작을 해야 하는가"
3. Model Spec           — "이 모델이 어떤 유효성 검증과 관계를 가져야 하는가"
4. Job Spec             — "이 Background Job이 어떤 순서로 실행되어야 하는가"
```

### 2.3 외부 API Mock 전략

외부 서비스(Keycloak Admin API, Langfuse API)는 **항상 Mock**한다:

```ruby
# spec/support/keycloak_mock.rb
# WebMock을 사용하여 Keycloak Admin API 응답을 stub
#
# 예시:
# stub_keycloak_create_client(realm: "aap", client_id: "test-oidc")
# stub_keycloak_delete_client(realm: "aap", id: "uuid-123")
```

- **WebMock**: HTTP 레벨에서 외부 API 호출을 차단하고 미리 정의된 응답을 반환
- **FactoryBot**: 테스트 데이터 생성에 사용
- 실제 외부 서비스에 의존하는 테스트는 작성하지 않는다 (CI 환경에서 실행 불가)

---

## 3. 기능별 개발 워크플로우

### 3.1 새로운 기능 구현 시

```
1. PRD에서 해당 FR(기능 요구사항) 확인
2. 기능을 작은 단위로 분해 (각 단위가 하나의 TDD 사이클)
3. 각 단위에 대해:
   a. 실패하는 테스트 작성
   b. 테스트 통과하는 최소 코드 작성
   c. 리팩토링
   d. 커밋 (테스트 + 구현 함께)
4. 전체 테스트 스위트 실행하여 regression 없는지 확인
5. 기능 완료 커밋
```

### 3.2 예시: Keycloak OIDC Client 생성 기능

```
Step 1. Request Spec 작성
  - POST /api/v1/organizations/:org_id/projects 요청 시
    인증 방식 OIDC 선택하면 202 응답 + Job 큐잉 확인

Step 2. Service Object Spec 작성
  - Keycloak::ClientCreator 서비스가
    올바른 Admin API 엔드포인트를 호출하는지 확인 (WebMock)

Step 3. Model Spec 작성
  - Project 모델 유효성 검증, 상태 전이 테스트

Step 4. Job Spec 작성
  - ProvisionProjectJob이 올바른 순서로
    Keycloak → Langfuse → Config Git 반영하는지 확인

Step 5. 각 단계마다 RED → GREEN → REFACTOR 반복
```

### 3.3 버그 수정 시

```
1. 버그를 재현하는 테스트를 먼저 작성한다 (RED)
2. 테스트가 실패하는 것을 확인한다
3. 버그를 수정한다 (GREEN)
4. 리팩토링 (필요 시)
5. 커밋: "fix: 버그 설명" + 재현 테스트 포함
```

---

## 4. 커밋 전략

### 4.1 커밋 단위

- **하나의 TDD 사이클 = 하나의 커밋** (테스트 + 구현 코드 함께)
- 테스트만 있는 커밋, 구현만 있는 커밋을 분리하지 않는다
- 리팩토링은 별도 커밋으로 분리할 수 있다

### 4.2 커밋 메시지 형식

```
<type>(<scope>): <description>

# type: feat, fix, refactor, test, docs, chore
# scope: 영향 범위 (model, api, service, job 등)

# 예시:
feat(keycloak): OIDC Client 생성 API 연동
fix(project): 삭제 시 Langfuse 프로젝트 정리 누락 수정
refactor(service): Provisioner 중복 로직 추출
test(integration): Keycloak Client 생성 실패 시나리오 추가
```

---

## 5. 실행 명령어

```bash
# 전체 테스트 실행
bundle exec rspec

# 특정 파일 실행
bundle exec rspec spec/services/keycloak/client_creator_spec.rb

# 특정 라인의 테스트만 실행
bundle exec rspec spec/services/keycloak/client_creator_spec.rb:15

# 실패한 테스트만 재실행
bundle exec rspec --only-failures

# 커버리지 리포트 생성
COVERAGE=true bundle exec rspec
```

---

## 6. CI에서의 테스트

- 모든 PR은 전체 테스트 스위트가 통과해야 머지 가능
- 커버리지 90% 이상 유지 (SimpleCov 기준)
- 새로운 코드에 대한 테스트가 없으면 리뷰에서 반려

---

## 7. 디렉토리 구조 (예상)

```
spec/
├── factories/           # FactoryBot 팩토리 정의
├── support/
│   ├── keycloak_mock.rb # Keycloak Admin API mock helpers
│   ├── langfuse_mock.rb # Langfuse API mock helpers
│   └── shared_contexts/ # 공통 테스트 컨텍스트
├── models/              # Model 단위 테스트
├── services/            # Service Object 단위 테스트
│   ├── keycloak/
│   └── langfuse/
├── jobs/                # Background Job 테스트
├── requests/            # API endpoint 테스트
└── system/              # E2E 시스템 테스트
```
