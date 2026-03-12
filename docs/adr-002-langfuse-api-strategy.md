# ADR-002: Langfuse API 연동 전략

> **상태**: Accepted
> **일자**: 2026-03-12
> **결정자**: Platform TG

## 컨텍스트

Console은 Langfuse의 Organization/Project/API Key를 프로그래밍 방식으로 관리해야 한다 (FR-1, FR-5). Langfuse는 두 가지 API 체계를 제공한다:

1. **Public API** (`sk-lf-...` / `pk-lf-...`): 트레이싱 데이터 수집용. Project 내부 데이터 접근 전용이며 관리 기능 없음.
2. **Admin API** (`ADMIN_API_KEY` + Org API Key): Org/Project/사용자 관리용 REST API. **Enterprise Edition(EE) 전용**.

Console은 Langfuse **OSS(Self-hosted)** 를 사용하므로 Admin API를 쓸 수 없다.

## 선택지

### 1. tRPC (NextAuth 세션 쿠키) — 채택

Langfuse 웹 UI가 내부적으로 사용하는 tRPC API (`/api/trpc/*`)를 호출한다.

**인증 흐름**:
1. `POST /api/auth/callback/credentials` (Console 서비스 계정 email/password)
2. `Set-Cookie: next-auth.session-token=...` 획득
3. 쿠키로 tRPC procedure 호출

**장점**:
- OSS에서 유일하게 런타임에 Org/Project CRUD 가능
- Langfuse UI와 동일한 기능 범위

**단점**:
- 비공식 API — procedure 시그니처가 Langfuse 업그레이드 시 변경될 수 있음
- 세션 쿠키 관리 로직 직접 구현 (만료 감지, 재로그인)
- 서비스 계정 credential을 환경변수로 관리해야 함

### 2. Admin API (`ADMIN_API_KEY`) — 미채택

**이유**: Enterprise Edition 전용. OSS에서 사용 불가.

**EE 전환 시 마이그레이션 경로**:
- `LangfuseClient` 내부 구현만 교체 (tRPC → REST)
- 인터페이스(메서드 시그니처)는 유지
- `LANGFUSE_ADMIN_API_KEY` 환경변수 추가
- `organizations` 테이블에 `langfuse_org_api_key` 컬럼 추가 가능

### 3. Headless Initialization (환경변수) — 미채택

`LANGFUSE_INIT_*` 환경변수로 기동 시 자동 생성.

**이유**: 기동 시 1회성 초기화만 가능. Console에서 동적으로 Org/Project를 생성하는 런타임 요구사항을 충족하지 못함.

### 4. DB 직접 조작 — 미채택

Langfuse PostgreSQL에 직접 INSERT.

**이유**: 내부 스키마 변경에 극도로 취약. 이벤트/캐시 등 애플리케이션 레이어 로직 우회. 유지보수 불가.

## 결정

**tRPC (세션 쿠키) 방식 채택**.

## 리스크 완화

| 리스크 | 완화 전략 |
|--------|---------|
| tRPC procedure 변경 | Langfuse tRPC 호출을 검증하는 통합 테스트 자동화. CI에서 Langfuse 컨테이너로 실행 |
| 세션 쿠키 만료 | `LangfuseClient`에서 401 응답 감지 시 자동 재로그인. 세션 TTL보다 짧은 주기로 갱신 불필요 (요청 시 lazy 갱신) |
| Langfuse 업그레이드 호환성 | Langfuse 버전 업그레이드 시 Console 통합 테스트를 먼저 실행. 실패 시 업그레이드 보류 |
| Credential 노출 | `LANGFUSE_SERVICE_EMAIL`, `LANGFUSE_SERVICE_PASSWORD`를 Kubernetes Secret으로 관리 |
| EE 전환 시 마이그레이션 | `LangfuseClient`의 public 메서드 인터페이스를 Admin API와 호환되게 설계. 내부 구현만 교체 가능하도록 |

## 필요 사항

| 항목 | 설명 |
|------|------|
| Langfuse 서비스 계정 | Console 전용 사용자 생성 (email/password). Org 생성 권한이 있어야 하므로 Langfuse 초기 설정 시 Admin 사용자로 등록 필요 |
| 환경변수 | `LANGFUSE_URL`, `LANGFUSE_SERVICE_EMAIL`, `LANGFUSE_SERVICE_PASSWORD` |
| 통합 테스트 | `docker-compose`로 Langfuse 컨테이너 기동 → tRPC 호출 검증 |

## 사용 tRPC Procedures

| Procedure | 용도 | 관련 FR |
|-----------|------|---------|
| `organizations.create` | Org 생성 | FR-1 |
| `organizations.update` | Org 수정 | FR-1 |
| `organizations.delete` | Org 삭제 | FR-1 |
| `projects.create` | Project 생성 | FR-5 |
| `projects.delete` | Project 삭제 | FR-5 |
| `projectApiKeys.create` | SDK Key 생성 | FR-5 |
| `projectApiKeys.byProjectId` | SDK Key 조회 | FR-5 |
| `projectApiKeys.delete` | SDK Key 삭제 | FR-5 |
