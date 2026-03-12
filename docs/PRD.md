# AAP Console — Product Requirements Document (PRD)

> **Version**: 1.13
> **Date**: 2026-03-12
> **Status**: Approved
> **References**: [HLD](./HLD.md) · [UI Spec](./ui-spec.md)

---

## 목차

1. [개요](#1-개요)
2. [용어 정의](#2-용어-정의)
3. [시스템 아키텍처 개요](#3-시스템-아키텍처-개요)
4. [리소스 계층 구조](#4-리소스-계층-구조)
5. [핵심 기능 요구사항](#5-핵심-기능-요구사항)
6. [비기능 요구사항](#6-비기능-요구사항)
7. [신규 Project 생성 워크플로우](#7-신규-project-생성-워크플로우)
8. [기술 스택](#8-기술-스택)
9. [마일스톤 및 우선순위](#9-마일스톤-및-우선순위)
10. [리스크 및 의존성](#10-리스크-및-의존성)
11. [부록](#11-부록)

---

## 1. 개요

### 1.1 배경

조직 내 다양한 팀이 AI/LLM 기반 서비스를 구축하기 위해 공통 인프라(인증, 모델 게이트웨이, 관측성 등)를 필요로 한다. 현재는 각 팀의 온보딩 시 수동으로 인프라를 구성하고 있어 시간 소요가 크고, 설정 오류 및 보안 누수 위험이 존재한다.

### 1.2 목적

타 부서 사용자가 **셀프서비스 방식**으로 Organization과 Project를 등록하면, AAP의 공유 서비스들(Keycloak, LiteLLM, Langfuse 등)에 해당 Project를 지원하기 위한 **설정이 자동으로 추가**되는 관리 콘솔을 구축한다.

### 1.3 핵심 원칙

| 원칙 | 설명 |
|------|------|
| **Console Creates, Server Manages** | Console은 "무엇을 설정할지"만 결정하고, Config Server는 "어떻게 저장하고 전파할지"를 담당 |
| **All-or-Nothing Provisioning** | 프로비저닝은 모든 단계가 성공하거나 전체 롤백. 부분 성공 상태 없음 |
| **Secret Zero-Store** | Console은 시크릿 평문을 저장하지 않음. 생성 시 일회성 표시 후 폐기 또는 Config Server로 즉시 전달 |
| **Auth ≠ Authz** | 인증은 Keycloak(OIDC)에 위임, 인가(RBAC)는 Console DB에서 자체 관리. 단일 원천 |
| **Server-rendered UI** | Hotwire(Turbo + Stimulus)로 SPA 없이 실시간 UI 구현. JavaScript 프레임워크 미사용 |

### 1.4 대상 사용자

| 역할 | 설명 |
|------|------|
| **팀 관리자** | Organization 하위에 Project를 생성하고 서비스 설정을 관리하는 타 부서 담당자 |
| **플랫폼 관리자** | AAP 전체 Organization을 관리하고 정책을 설정하는 운영팀 |
| **개발자** | 발급된 인증 정보 및 SDK Key를 활용하여 서비스를 개발하는 사용자 |

---

## 2. 용어 정의

| 용어 | 설명 |
|------|------|
| **AAP** | AI Assistant Platform. AI/LLM 서비스 구축을 위한 공통 플랫폼 |
| **Organization** | 최상위 관리 단위. 복수의 Project를 포함 |
| **Project** | Organization 하위의 관리 단위. Console에서 생성/관리하는 서비스 설정의 격리 단위 |
| **App (App ID)** | Project의 구현 단에서의 식별자. 공유 서비스들이 `x-application-id` 헤더로 Project를 식별할 때 사용하는 ID |
| **PAK** | Project API Key. 간편 인증을 위한 프로젝트 전용 API 키 |
| **LiteLLM** | LLM 모델 라우팅 및 프록시 게이트웨이. App ID로 Project별 요청을 식별 |
| **Langfuse** | LLM 호출에 대한 관측성(Observability) 및 트레이싱 플랫폼 |
| **aap-helm-charts** | AAP 서비스들의 K8s 배포용 Helm Chart 레포 |
| **Config Server** | Go 기반 설정 서버 (`aap-config-server`). 설정 읽기 API 서빙 + Admin API로 설정/시크릿 쓰기 처리. Console은 Config Server Admin API만 호출하고, 암호화/저장/적용 등 인프라 작업은 Config Server가 수행 |
| **Config Agent** | Config Server의 설정을 LiteLLM 등 대상 서비스에 전달하는 컴포넌트. Console 관점에서는 Config Server 이후의 전파 파이프라인 |
| **Provisioner** | Console 내부의 서비스 객체. Keycloak Admin API, Langfuse tRPC API 등 외부 서비스 API를 직접 호출하여 리소스를 생성/수정/삭제하는 Background Job 단위 |

---

## 3. 시스템 아키텍처 개요

```
                          ┌──────────────┐
                          │  사내 SSO IdP │
                          └──────┬───────┘
                                 │
                          ┌──────▼───────┐
                      ┌──▶│   Keycloak   │
                      │   │ (SSO Broker) │
                      │   └──────┬───────┘
                      │        인증 후
                      │   ┌──────┼───────────────┐
  Keycloak Admin API  │   ▼      ▼               ▼
                      │ ┌──────────┐ ┌─────────┐ ┌─────────┐
                      │ │  AAP     │ │ LiteLLM │ │Langfuse │──▶ S3
                      │ │ Console  │ │(LLM G/W)│ │ (관측성) │
                      │ │ (Rails)  │ └────▲────┘ └────▲────┘
                      │ └────┬─────┘      │           │
                      │      │            │ 설정 전파  │ tRPC API
                      │ ┌────▼──────┐     │           │
                      │ │Provisioner│     │           │
                      │ │(SolidQueue│     │           │
                      │ │ Bg Jobs)  │     │           │
                      │ └─┬──┬──────┘     │           │
                      │   │  │            │           │
                      └───┘  │ Admin API  │           │
                             │ (설정/시크릿│           │
                             │  CRUD)     │           │
                             ▼            │           │
                      ┌───────────────┐   │           │
                      │ Config Server │───┘           │
                      │  · Admin API  │               │
                      │  · 읽기 API   │               │
                      └───────────────┘               │
                                                      │
                      └───────────────────────────────┘
```

**흐름 설명**:
- **사용자 인증**: 사용자 → Keycloak(SSO IdP 브로커) → 인증 후 AAP Console / LiteLLM / Langfuse 접근
- **Project 설정 반영** (2경로):
  1. **리소스 생성 (API 직접 호출)**: Keycloak Admin REST API로 Client 생성, Langfuse tRPC API로 프로젝트 생성 등
  2. **동적 Config 반영 (Config Server Admin API)**:
     - Console이 Config Server Admin API를 호출하여 설정 값/시크릿 값 전달
     - Config Server가 내부적으로 암호화, 저장, 적용 등 인프라 작업을 수행
     - 이후 Config Server 전파 파이프라인을 통해 LiteLLM에 자동 반영

**Console → Config Server 인터페이스**:

Console은 Config Server Admin API만 호출한다. 설정의 저장/암호화/적용 방식은 Config Server 내부 관심사이며, Console은 알 필요 없다.

| Console 작업 | Config Server API | 상세 |
|---|---|---|
| **설정/시크릿 일괄 변경** | `POST /api/v1/admin/changes` | 설정 데이터 + 시크릿 평문을 한 번에 전달. Config Server가 atomic하게 처리 후 버전 식별자 반환 |
| **설정/시크릿 일괄 삭제** | `DELETE /api/v1/admin/changes` | 지정한 org/project/service의 설정 및 시크릿 제거. 단일 atomic 처리 |
| **버전 롤백** | `POST /api/v1/admin/changes/revert` | 버전 식별자 지정. Config Server가 해당 시점으로 설정/시크릿 복원 |
| **App Registry 변경** | `POST /api/v1/admin/app-registry/webhook` | App 등록/수정/삭제 시 Config Server의 인메모리 인증 캐시 갱신. Console은 **fire-and-forget + async retry** 방식으로 전송 — Console DB 저장 후 비동기 전송하며, Config Server 다운 시에도 Console CRUD는 정상 완료 |

**Console → Config Server 제공 API (Config Server가 Console을 호출)**:

| Console API | 호출 주체 | 상세 |
|---|---|---|
| **App Registry 벌크 조회** | Config Server (시작 시) | `GET /api/v1/apps?all=true` — Config Server가 시작 시 전체 App Registry를 로드하여 인메모리 인증 캐시를 구성. Console이 미준비 상태일 경우 Config Server가 자체 재시도 후 빈 캐시로 기동 (설정 서빙은 정상, App 인증만 불가) |

**시작 순서 독립성**: Console과 Config Server는 부팅 시 상호 의존하지 않도록 설계한다. 어느 쪽이 먼저 기동해도 데드락이 발생하지 않으며, 상대방이 복구되면 정상 기능이 점진적으로 회복된다.
- **Console 독립 기동**: Config Server가 다운이어도 Console DB CRUD는 정상 완료. webhook은 async retry queue에서 재시도. 단, Config Server 의존 화면(설정 조회/이력)은 에러 상태
- **Config Server 독립 기동**: Console API에서 App Registry 로드 실패 시 빈 캐시로 기동. Console 복구 후 webhook 수신으로 캐시 정합성 회복

> **설계 원칙 (Console Creates, Server Manages)**: Console은 "무엇을 설정할지"만 결정하고, Config Server는 "어떻게 저장하고 전파할지"를 담당한다. 이를 통해 Console은 인프라 의존성 없이 순수 관리 UI/API로 유지된다.

---

## 4. 리소스 계층 구조

```
Organization (조직)
 ├── Langfuse Org ─────────────── [Langfuse tRPC API]
 │
 └── Project (App ID 발급)
      │
      ├── 인증 설정
      │    ├── Keycloak Client ──── [Keycloak Admin REST API]
      │    │    └── SAML / OIDC / OAuth Client 자동 생성
      │    └── PAK ──────────────── [Console 자체 생성]
      │         └── Project API Key 발급 (Keycloak 미사용)
      │
      ├── Langfuse 설정 ─────────── [Langfuse tRPC API]
      │    ├── Langfuse Project 생성 (소속 Langfuse Org 하위)
      │    └── SDK Key 발급 (PK/SK)
      │         └── Console이 Config Server Admin API로 시크릿 전달
      │              → Config Server가 암호화/저장/적용 수행
      │
      └── LiteLLM 설정 ──────────── [Config Server Admin API]
           ├── 모델 라우팅 Config
           ├── 가드레일 설정
           ├── App별 S3 경로 (prefix)
           └── App별 S3 Retention 설정
```

- **생명주기**: Project 생성(설정 추가) → 운영 → 설정 변경 → 삭제(전체 롤백)

---

## 5. 핵심 기능 요구사항

### FR-1. Organization 관리 (CRUD)

| 항목 | 상세 |
|------|------|
| **생성** | 신규 Organization 등록. 조직명, 설명 입력. 생성 시 멤버 목록 관리 (초기 관리자 지정). Langfuse Org 자동 생성 (tRPC `organizations.create`) |
| **조회** | Organization 목록 및 상세 정보 (소속 Project 현황, 멤버 목록 포함) 확인 |
| **수정** | Organization 정보 변경 (이름, 설명) 및 멤버 추가/제거/권한 변경 |
| **삭제** | Organization 삭제 시 하위 모든 Project를 먼저 개별 삭제(각 Project의 롤백 대상 전체 정리, FR-3 참조)한 뒤, Langfuse Org 삭제 (tRPC `organizations.delete`) + Console DB의 org_memberships/project_permissions 정리. **플랫폼 관리자(`super_admin`)만 실행 가능** |

### FR-2. 접근제어 (RBAC) — Console DB 자체 관리

Organization/Project 단위로 사용자 접근 권한을 관리한다. **인증은 Keycloak(OIDC)**에 위임하고, **인가(역할/권한)는 Console DB에서 자체 관리**한다. Keycloak은 그룹/역할 관리에 관여하지 않는다.

#### 접근 모델 (열린 접근)

Console은 **열린 접근 모델**을 사용한다. 사내 SSO를 통해 누구나 Console에 로그인할 수 있지만, 어떤 Organization에도 소속되지 않은 사용자는 **접근 가능한 리소스가 없는 빈 화면**만 보게 된다.

| 시나리오 | 접근 범위 |
|----------|-----------|
| SSO 로그인 성공, Org 미소속 | 빈 화면. Org 생성 불가, 어떤 리소스도 조회 불가 |
| `super_admin` | 전체 Organization 생성/삭제, 전체 현황 조회, Org admin 할당 |
| Org `admin` | 해당 Org의 Project 생성/삭제, 멤버 관리, **모든 하위 Project 접근** |
| Org `write` + Project 권한 | **권한 부여된 Project**의 설정 변경 |
| Org `read` + Project 권한 | **권한 부여된 Project** 조회만 가능 |

**일반적인 온보딩 플로우**:
1. `super_admin`이 Organization을 생성
2. `super_admin`이 특정 사용자를 Org `admin`으로 지정 (사용자 사전 할당 가능 — 아래 참조)
3. Org `admin`이 Project를 생성하고, 다른 사용자에게 `read`/`write` 권한 및 **Project별 접근 권한** 부여
4. 권한을 부여받은 사용자가 로그인하면 소속 Org 및 **접근 권한이 있는 Project만** 조회 가능

#### Keycloak 구성 (순수 인증)

AAP는 **단일 Realm 정책**을 사용한다. Console은 OIDC Client로 등록되며, Keycloak은 **인증(로그인/토큰 발급)만** 담당한다. RBAC 관련 그룹/역할은 Keycloak에서 관리하지 않는다.

```
Realm: aap (단일)
 ├── Client: litellm           ← 기존 서비스
 ├── Client: langfuse          ← 기존 서비스
 ├── Client: {team}-agent      ← 타 팀 서비스
 └── Client: aap-console       ← Console
      ├── OIDC Confidential Client (Authorization Code Flow)
      └── Service Account 활성화 (Keycloak Admin API 호출용)
```

> **Keycloak 그룹 미사용**: Console의 Org 소속, 역할, Project 접근 권한은 모두 Console DB에서 관리한다. Keycloak 그룹 구조 생성, Client Scope, Group Membership Mapper 등이 불필요하다.

**Service Account 권한**: Console이 Project별 인증 Client 자동 구성(FR-4) 및 사용자 검색을 위해 Keycloak Admin API를 호출한다. `aap-console` Client의 Service Account에 최소 권한을 부여한다.

| Service Account Role | 용도 |
|---|---|
| `realm-management: manage-clients` | Client 생성/수정/삭제 (OIDC/SAML/OAuth) 및 Protocol Mapper 관리 |
| `realm-management: query-users` | 사용자 검색 (멤버 추가 시 이메일/이름 기반 검색) |
| `realm-management: manage-users` | 사전 할당 시 사용자 레코드 생성 |

> **이전 대비 축소**: `manage-groups`, `query-groups` 권한이 불필요해졌다. 그룹 관리를 Keycloak에 위임하지 않으므로.

#### 권한 모델

| 항목 | 상세 |
|------|------|
| **권한 수준** | `super_admin` — 플랫폼 전체 관리. Organization 생성/삭제, 전체 현황 조회. **유일하게 Keycloak에서 관리** (Realm Role `super_admin`으로 판별) <br> `admin` — Org 설정 및 멤버 관리, Project 생성/삭제, **모든 하위 Project 자동 접근** (Console DB) <br> `write` — 권한 부여된 Project 설정 변경 (Console DB) <br> `read` — 권한 부여된 Project 조회만 가능 (Console DB) |
| **데이터 저장** | Console DB의 `org_memberships` 테이블에 Org 역할 저장 (user_sub + role). `project_permissions` 테이블에 Project별 접근 권한 저장. **이메일 등 개인정보는 Console DB에 저장하지 않음** — 사용자 식별은 Keycloak `sub`(고유 ID)만 사용 |
| **사용자 정보 표시** | 멤버 목록 등 UI에서 사용자 이름/이메일이 필요한 경우 Keycloak Admin API로 실시간 조회 |
| **멤버 관리** | Console UI에서 사용자 검색 → Org 멤버십 생성(Console DB) → Project 권한 부여(Console DB). Keycloak 그룹 변경 없음 |
| **사용자 검색** | 멤버 추가 시 Keycloak Admin API (`GET /users?search={query}`)로 사용자 검색. 이메일 또는 이름으로 검색 가능 |
| **사용자 사전 할당** | 아직 Console에 로그인하지 않은 사용자도 권한 할당 가능. Keycloak에 사용자 레코드가 없으면 Admin API (`POST /users`)로 이메일 기반 최소 사용자를 사전 생성. Console DB에 해당 `user_sub`로 멤버십 레코드 생성. 해당 사용자가 나중에 SSO 로그인 시 Keycloak First Broker Login 플로우가 이메일 매칭으로 기존 레코드에 자동 링크 |
| **권한 범위** | Org `admin`은 해당 Org의 모든 Project에 암묵적 접근 권한. `read`/`write` 사용자는 `project_permissions`에 명시적으로 권한이 부여된 Project만 접근 가능 |
| **Console UI 제어** | Console DB의 멤버십/권한 정보를 기반으로 UI 요소(버튼, 메뉴 등) 활성/비활성 처리 |
| **API 제어** | 모든 API 엔드포인트에서 Console DB의 멤버십/권한 레코드를 조회하여 인가 처리 |

#### Keycloak Admin API 연동 (FR-2 관련)

| Console 작업 | Keycloak Admin API |
|---|---|
| 사용자 검색 | `GET /admin/realms/{realm}/users?search={query}` — 이메일/이름으로 사용자 검색 |
| 사용자 상세 조회 | `GET /admin/realms/{realm}/users/{id}` — sub로 이름/이메일 조회 (멤버 목록 표시용) |
| 사용자 사전 생성 | `POST /admin/realms/{realm}/users` — Keycloak 미등록 사용자를 이메일 기반으로 사전 생성 (사전 할당용) |

### FR-3. Project 관리 (CRUD)

| 항목 | 상세 |
|------|------|
| **생성** | Organization 하위에 신규 Project 등록. 이름, 설명 입력. 생성 시 App ID 자동 발급 |
| **조회** | Project 목록 및 상세 정보 (각 서비스에 추가된 설정 현황, 발급된 App ID) 확인 |
| **수정** | Project 설정 변경 (인증 방식, 모델 라우팅, S3 Retention 등) |
| **삭제** | Project 삭제 시 생성/수정 과정에서 추가된 **모든** 내역을 롤백. 아래 전체 대상 참고 |

**삭제 시 롤백 대상**:

| 대상 | 롤백 내용 |
|------|-----------|
| **Keycloak 리소스** | Keycloak Admin API로 해당 Project의 Client 삭제 (`DELETE /admin/realms/{realm}/clients/{id}`) |
| **Langfuse 리소스** | Langfuse tRPC API를 통해 프로젝트 및 SDK Key 삭제 |
| **Config Server (설정/시크릿)** | Config Server Admin API (`DELETE /api/v1/admin/changes`)로 해당 App의 설정 + 시크릿 일괄 삭제 |
| **Config Server (App Registry)** | Config Server Admin API (`POST /api/v1/admin/app-registry/webhook`, `action: delete`)로 App 등록 해제 |
| **Console DB (접근 권한)** | 해당 Project에 대한 `project_permissions` 레코드 삭제 |

> **구현 고려사항**: Config Server의 설정/시크릿 삭제 API가 해당 App의 데이터만 정확히 제거하고 다른 Project에 영향을 주지 않아야 한다. App ID 기반의 격리 전략은 Config Server 모듈에서 설계한다.

### FR-4. 인증 체계 자동 구성

사용자가 Project 생성 시 인증 방식을 선택하면 자동으로 구성된다.

| 인증 방식 | 구성 내용 |
|-----------|-----------|
| **SAML** | Keycloak에 SAML Client 자동 생성, SP 메타데이터 제공 |
| **OIDC** | Keycloak에 OIDC Confidential Client 자동 생성 (Authorization Code Flow), Client ID/Secret 발급 |
| **OAuth** | Keycloak에 OAuth 2.0 Public Client 자동 생성 (PKCE 기반, Client Secret 없음), Redirect URI 설정 |
| **PAK (Project API Key)** | Console에서 API Key 자동 생성 및 발급 (Keycloak 미사용) |

- **Keycloak Admin REST API**를 직접 호출하여 Client 생성/수정/삭제를 자동화한다. Console의 Service Account 토큰으로 인증한다.
- 발급된 Keycloak Client Secret 및 PAK는 생성 시 UI에 **일회성으로만 표시**하며, Console에서는 별도로 저장하지 않는다.

**Client 네이밍 컨벤션**:

Console이 자동 생성하는 Keycloak Client는 기존 수동 등록 Client와의 충돌을 방지하고 식별을 용이하게 하기 위해 아래 규칙을 따른다.

| 형식 | 예시 |
|------|------|
| `aap-{org-id}-{project-id}-{protocol}` | `aap-acme-chatbot-oidc`, `aap-acme-chatbot-saml` |

- `aap-` prefix로 Console이 생성한 Client임을 식별
- Console은 자신이 생성한 Client만 수정/삭제하며, `aap-` prefix가 없는 Client는 조작하지 않음 (코드 레벨 방어)

**Keycloak Admin API 연동 (Client 관리)**:

| Console 작업 | Keycloak Admin API |
|---|---|
| OIDC Client 생성 | `POST /admin/realms/{realm}/clients` — `protocol: openid-connect`, `publicClient: false`, `serviceAccountsEnabled: true` |
| SAML Client 생성 | `POST /admin/realms/{realm}/clients` — `protocol: saml`, SAML 설정 attributes 포함 |
| OAuth Client 생성 | `POST /admin/realms/{realm}/clients` — `protocol: openid-connect`, `publicClient: true`, PKCE 설정 |
| Client 설정 변경 | `PUT /admin/realms/{realm}/clients/{id}` |
| Client Scope 할당 | `PUT /admin/realms/{realm}/clients/{id}/default-client-scopes/{scopeId}` |
| Client 삭제 | `DELETE /admin/realms/{realm}/clients/{id}` |
| Client Secret 재발급 | `POST /admin/realms/{realm}/clients/{id}/client-secret` |
| Protocol Mapper 추가 | `POST /admin/realms/{realm}/clients/{id}/protocol-mappers/models` |

> **주의**: `PUT /clients/{id}` 요청 시 body의 `defaultClientScopes`, `optionalClientScopes` 필드는 **무시된다** ([keycloak#24920](https://github.com/keycloak/keycloak/issues/24920)). Client Scope 변경은 반드시 전용 엔드포인트(`/default-client-scopes/{scopeId}`, `/optional-client-scopes/{scopeId}`)를 사용해야 한다.

### FR-5. Langfuse 프로젝트 생성 및 SDK Key 발급

| 항목 | 상세 |
|------|------|
| **프로젝트 생성** | Langfuse 내부 tRPC API를 통해 Project별 독립 Langfuse 프로젝트 자동 생성 |
| **SDK Key 발급** | tRPC API로 API Key 생성 후 반환되는 Public Key, Secret Key 사용. Console은 SK/PK를 **저장하지 않고** 즉시 처리 |
| **시크릿 전달** | Console이 SK/PK 평문을 Config Server Admin API (`POST /api/v1/admin/changes`)로 설정 데이터와 함께 일괄 전달. Config Server가 암호화/저장/적용을 atomic하게 처리 후 버전 식별자 반환 |
| **프로젝트 삭제** | FR-3 삭제 시 롤백 대상 참조 |
| **트레이싱 연동** | Console이 Config Server Admin API로 설정/시크릿 전달 후, Config Server → LiteLLM 자동 전파 경로를 통해 Langfuse 트레이싱 자동 연동 |

**Langfuse tRPC API 연동**:

Langfuse 웹 UI가 내부적으로 사용하는 tRPC API를 직접 호출한다. EE 라이선스 없이 오픈소스 자체 호스팅 환경에서 사용 가능하다.

| Console 작업 | Langfuse tRPC Procedure | 인증 방식 |
|---|---|---|
| Langfuse Org 생성 | `organizations.create` | NextAuth 세션 쿠키 |
| Langfuse Org 수정 | `organizations.update` | NextAuth 세션 쿠키 |
| Langfuse Org 삭제 | `organizations.delete` | NextAuth 세션 쿠키 |
| Langfuse Project 생성 | `projects.create` | NextAuth 세션 쿠키 |
| Langfuse Project 삭제 | `projects.delete` | NextAuth 세션 쿠키 |
| Project API Key 생성 | `projectApiKeys.create` | NextAuth 세션 쿠키 |
| Project API Key 조회 | `projectApiKeys.byProjectId` | NextAuth 세션 쿠키 |
| Project API Key 삭제 | `projectApiKeys.delete` | NextAuth 세션 쿠키 |

> **tRPC 인증**: Langfuse tRPC API는 NextAuth.js 세션 쿠키(JWT 전략)로 인증한다. Console은 Langfuse에 서비스 계정을 생성하고, 해당 계정의 세션 쿠키를 획득하여 tRPC 호출에 사용한다. 세션 만료 시 자동 갱신 로직이 필요하다.
>
> **엔드포인트**: `POST /api/trpc/{procedure}` 형식. 예: `POST /api/trpc/projects.create`

> **설계 원칙**: Console은 시크릿 평문을 Config Server Admin API로 전달만 하고, 암호화/저장/적용은 Config Server가 수행한다. 시크릿 저장/암호화 방식은 Config Server 내부 관심사이다.
>
> **인가**: Console이 사용자 RBAC 권한을 검증한 후 Config Server Admin API를 호출한다 (비기능 요구사항 6.1 참조).

### FR-6. LiteLLM Config 자동 생성 및 동적 반영

| 항목 | 상세 |
|------|------|
| **모델 라우팅** | 사용할 LLM 목록 선택 및 모델별 정책(Rate Limit 등) 구성 |
| **가드레일** | 사용자 선택 기반의 보안 가드레일 적용 (컨텐츠 필터링, 토큰 제한 등) |
| **S3 경로** | App별 S3 버킷 경로 (prefix)를 Config에 포함. 기존 공유 버킷을 사용하며 별도 버킷 생성 불필요 |
| **S3 Retention** | App별 S3 데이터 보관 주기를 LiteLLM Config 변수로 설정. LiteLLM이 해당 변수를 읽어 커스텀 구현된 Retention 로직을 적용 (S3 Lifecycle Policy가 아닌 애플리케이션 레벨 처리) |
| **Config 반영** | Console이 Config Server Admin API (`POST /api/v1/admin/changes`)로 설정/시크릿 데이터를 일괄 전달. Config Server가 atomic하게 처리 후 버전 식별자 반환 |
| **Reload 방식** | Console은 Config Server Admin API 호출까지만 수행. 저장, 인메모리 갱신, LiteLLM 전파는 Config Server 모듈이 자동 처리 |

### FR-7. 프로비저닝 파이프라인 관리

Project 생성/수정/삭제 시 여러 외부 서비스(Keycloak, Langfuse, Config Server)에 순차/병렬로 리소스를 생성하는 프로비저닝 파이프라인의 실행, 실패 복구, 상태 추적을 관리한다.

#### FR-7.1 프로비저닝 상태 머신

각 프로비저닝 작업은 아래 상태를 거치며, Console DB에 단계별 상태가 기록된다.

```
pending → in_progress → completed
                │
                ├─→ failed → retrying → in_progress
                │                          │
                │                          └─→ failed (max retries 초과)
                │                                │
                └──────────────────────────────→ rolling_back → rolled_back
                                                     │
                                                     └─→ rollback_failed
```

| 상태 | 설명 |
|------|------|
| `pending` | 작업 대기 중 (SolidQueue에 enqueue됨) |
| `in_progress` | 프로비저닝 단계 실행 중 |
| `completed` | 모든 단계 성공 |
| `failed` | 특정 단계 실패. 자동 재시도 대상 |
| `retrying` | 재시도 진행 중 |
| `rolling_back` | 보상 트랜잭션 실행 중 (이미 생성된 리소스 정리) |
| `rolled_back` | 보상 트랜잭션 완료 |
| `rollback_failed` | 보상 트랜잭션 실패. **플랫폼 관리자 수동 개입 필요** |

#### FR-7.2 단계별 실행 및 실패 처리

프로비저닝은 단계(step)의 순서로 구성되며, **모든 단계가 성공해야만 완료**된다. 어떤 단계든 최종 실패 시 이미 생성된 모든 리소스를 롤백하여 원자성(atomicity)을 보장한다.

| 요구사항 | 상세 |
|----------|------|
| **원자성 보장** | 프로비저닝은 all-or-nothing. 모든 리소스 생성 단계가 성공하면 `completed`, 하나라도 최종 실패하면 전체 `rolling_back`. 부분 성공 상태로 사용자에게 노출되지 않음. **예외**: Health Check(FR-9) 실패는 롤백을 트리거하지 않고 경고(warning)로 처리 — 리소스는 이미 정상 생성된 상태이므로 |
| **단계별 상태 기록** | 각 단계(Keycloak Client 생성, Langfuse 프로젝트 생성, Config Server 설정 반영 등)의 시작/성공/실패 시각과 결과를 Console DB에 기록 |
| **자동 재시도** | 외부 API 호출 실패 시 자동 재시도. 재시도 횟수 및 정책은 단계별로 설정 가능 |
| **보상 트랜잭션** | 재시도 한도 초과 시 이미 완료된 단계를 역순으로 롤백 (예: Config Server 실패 시 → Langfuse 프로젝트 삭제 → Keycloak Client 삭제) |
| **멱등성** | 각 단계는 멱등하게 설계. 재시도 시 중복 리소스가 생성되지 않아야 함 (생성 전 존재 여부 확인) |

#### FR-7.3 프로비저닝 현황 화면

Project 생성/수정/삭제 요청 후 사용자가 프로비저닝 진행 상황을 실시간으로 확인할 수 있는 전용 화면을 제공한다.

**화면 전환 플로우**:

```
Project 생성 폼 제출
  │
  ▼
프로비저닝 현황 페이지로 즉시 리다이렉트
  │  (ActionCable로 실시간 상태 수신)
  │
  ├─ [진행중] 각 단계의 상태를 실시간 표시
  │   ├─ Step 1. App Registry 등록      ✓ 완료
  │   ├─ Step 2a. 인증 리소스 생성       ⟳ 진행중...
  │   ├─ Step 2b. Langfuse 리소스 생성   ⟳ 진행중...
  │   ├─ Step 3. Config 반영             ○ 대기
  │   └─ Step 4. Health Check            ○ 대기
  │
  ├─ [전체 완료 시] Project 상세 페이지로 이동 가능
  │
  └─ [실패 시] 실패 단계 및 오류 정보 표시 + 수동 재시도 버튼
```

| 항목 | 상세 |
|------|------|
| **자동 리다이렉트** | Project 생성 폼 제출 시 즉시 프로비저닝 현황 페이지로 이동. Turbo Drive로 SPA 없이 자연스러운 전환 |
| **실시간 상태 스트리밍** | ActionCable(WebSocket)로 각 단계의 상태 변경을 실시간 전송. Turbo Streams로 단계별 UI 요소를 동적 업데이트 |
| **단계별 상태 표시** | 각 단계(App Registry 등록, 인증 리소스, Langfuse, Config 반영, Health Check)의 대기/진행중/성공/실패/재시도중 상태를 시각적으로 표시 |
| **완료 후 네비게이션** | 전체 프로비저닝 완료 시 Project 상세 페이지로 이동할 수 있는 링크/버튼 제공. 자동 리다이렉트는 하지 않음 (사용자가 결과를 확인할 시간 제공) |
| **실패 시 액션** | 실패한 단계의 오류 메시지 표시. `failed` 또는 `rollback_failed` 상태의 작업을 관리자가 수동 재시도 가능 |
| **이력 보관** | 완료된 프로비저닝 로그(성공/실패 모두)는 저장하여 사후 조회 가능. Project 상세 페이지에서 과거 프로비저닝 이력 확인 |
| **직접 접근** | 프로비저닝 현황 페이지는 고유 URL을 가지며, 페이지를 떠났다 돌아와도 현재 상태 확인 가능 (새로고침 시 DB에서 최신 상태 로드 + ActionCable 재연결) |

### FR-8. 설정 변경 이력 관리 및 버전 롤백

| 항목 | 상세 |
|------|------|
| **이력 관리** | Project별 설정 변경 시마다 버전 기록. Config Server가 반환하는 버전 식별자를 Console DB에 저장하여 변경 이력과 연결 |
| **버전 조회** | Console에서 변경 이력 목록 및 diff 확인 |
| **롤백 — Keycloak** | Console DB에 기록된 이전 설정 스냅샷을 기반으로 Keycloak Admin API를 호출하여 Client 설정 복구 (`PUT /admin/realms/{realm}/clients/{id}`) |
| **롤백 — Langfuse** | Console DB에 기록된 이전 스냅샷을 기반으로 Langfuse tRPC API를 호출하여 Project 설정 복구 |
| **롤백 — Config Server** | Console이 저장된 버전 식별자로 Config Server revert API 호출 (`POST /api/v1/admin/changes/revert`). Config Server가 해당 시점으로 설정/시크릿 복원. Console은 시크릿 평문을 재전달할 필요 없음 — Config Server가 내부 이력에서 복원 |
| **원자적 버전 관리** | Config Server의 설정/시크릿 변경은 단일 atomic 처리되므로, 하나의 버전 식별자로 config + secret 모두 식별 가능 |
| **감사 로그** | 누가, 언제, 어떤 설정을 변경했는지 추적 |

### FR-9. Health Check 및 정합성 검증

| 항목 | 상세 |
|------|------|
| **Keycloak 검증** | 인증 Client 생성 결과를 Console에 표시. 실제 로그인 동작 검증은 관리자가 수동으로 수행 |
| **LiteLLM 검증** | Config 적용 후 API 호출 정상 여부 확인 |
| **Langfuse 검증** | 프로젝트 생성 후 SDK Key로 연결 테스트 |
| **종합 리포트** | 검증 결과를 Console에 표시하고, 실패 시 알림 |

---

## 6. 비기능 요구사항

### 6.1 보안

- Keycloak Client Secret, PAK는 생성 시 UI에 일회성 표시 후 Console 미저장
- Langfuse SK/PK는 Console 미저장. Config Server Admin API로 평문 전달 후 즉시 폐기. 암호화/저장/적용은 Config Server가 수행
- 시크릿 평문은 Config Server의 저장소에 직접 저장되지 않음 (암호화 처리). 시크릿 저장/암호화 방식은 Config Server 내부 관심사
- Console 접근은 조직 SSO를 통한 인증 필수
- Organization/Project 단위 RBAC (admin/write/read) 기반 접근제어 — Console DB 자체 관리 (FR-2 참조)
- Console → Config Server 요청 시 인증/인가 검증 (아래 상세)
- Project 간 서비스 설정 격리 (테넌트 격리)
- API 통신 시 TLS 필수

**Console → Config Server 인증/인가**:

Console은 Config Server Admin API만 호출한다. 암호화, 저장, 적용 등 인프라 작업은 Config Server가 수행한다.

| 계층 | 검증 주체 | 검증 내용 |
|------|-----------|-----------|
| **사용자 권한 검증** | **Console** | Console DB의 `org_memberships`/`project_permissions`를 조회하여 요청 사용자의 Org/Project 권한 검증. 권한 미달 시 Config Server API 호출을 수행하지 않음 |
| **Config Server 접근 제어** | **K8s Network Policy** | Config Server Admin API에 접근 가능한 Pod을 Console로 제한 |
| **Config Server 인증/인가** | **Config Server** | `X-App-ID` 헤더 기반 접근 제어. App Registry의 scope/permissions로 요청 범위 제한. 상세는 `aap-config-server` 모듈 참조 |

### 6.2 성능

| 지표 | 목표 | 측정 방법 |
|------|------|----------|
| Project 생성 → 전체 설정 완료 | ≤ 60초 | 프로비저닝 Job 시작~완료 시간 |
| Console UI 페이지 로드 | ≤ 2초 | 서버 응답 시간 (TTFB) |
| 실시간 로그 스트리밍 지연 | ≤ 1초 | Step 상태 변경 → ActionCable 수신 |
| Keycloak Admin API 응답 | ≤ 3초 | Client CRUD 단일 호출 |
| Config Server Admin API 응답 | ≤ 5초 | `POST /admin/changes` (Git commit 포함) |

### 6.3 확장성

- 동시 다수 Project 생성 요청 처리 가능 (Background Job 큐 기반 병렬 처리)
- 단일 인스턴스 배포 (SQLite 단일 writer 제약)이므로 쓰기 수평 확장 불가. 내부 관리 콘솔 규모에서는 충분. 읽기 확장이 필요하면 LiteFS 기반 Read Replica 구성 가능 (8.2절 참조)

### 6.4 가용성

- 외부 API 호출 실패 시 자동 재시도 및 보상 트랜잭션으로 복구. 프로비저닝은 all-or-nothing 원자성 보장 (FR-7.2 참조)
- 공유 서비스 장애 시 재시도 후 복구 불가하면 전체 롤백 (FR-7.2 참조)

### 6.5 동시성 제어

다수 사용자가 동시에 Project를 생성/수정/삭제해도 데이터 정합성이 보장되어야 한다.

| 대상 | 동시성 제어 방식 |
|------|------------------|
| **Console DB (SQLite)** | SQLite WAL 모드로 동시 읽기 허용, 쓰기는 단일 프로세스 직렬화. 단일 인스턴스 배포이므로 DB 레벨 동시성 문제 최소화. 프로비저닝 상태 머신(FR-7.1)으로 중복 처리 방지 |
| **외부 API 호출** | SolidQueue Job 직렬화로 동일 Project에 대한 동시 프로비저닝 방지. 각 단계는 멱등하게 설계 (FR-7.2) |
| **Config Server API** | 동일 Project에 대한 동시 API 호출은 SolidQueue Job 직렬화로 방지. **서로 다른 Project 간**: Config Server가 Project별 설정 격리를 보장하므로 동시 쓰기 시에도 충돌 없음. 동시성 제어는 Config Server 모듈 책임 |
| **Background Job (SolidQueue)** | 동일 Project에 대한 Job은 직렬 실행을 보장 (unique job 또는 큐 기반 직렬화). 서로 다른 Project의 Job은 병렬 실행 가능 |

**설계 원칙**:
- Project 단위로 격리된 잠금을 사용하여, 서로 다른 Project 간의 작업은 상호 차단하지 않음
- 동일 Project에 대해 생성/수정/삭제가 동시에 요청되면, 먼저 접수된 작업이 완료될 때까지 후속 요청은 대기 또는 거부
- 장시간 잠금 점유 시 타임아웃을 적용하여 교착 상태 방지

### 6.6 관측성

- Project 설정 작업 상태 모니터링 (성공/실패/진행중)
- 공유 서비스 연동 상태 대시보드

---

## 7. 신규 Project 생성 워크플로우

사용자가 Console에서 Project를 생성하면, 각 공유 서비스에 리소스가 생성되고 Config Server에 반영된다.

```
사용자: Project 생성 요청 (이름, 인증 방식, 모델 목록, S3 Retention 등 입력)
  │
  ▼
Step 1. Project 레코드 생성 (DB) + App ID 발급
  │
  ▼
Step 1b. App Registry 등록 [Config Server Admin API]
  └─ POST /api/v1/admin/app-registry/webhook — App ID 등록 (fire-and-forget + async retry)
     (이후 Config Server API 호출의 인증 전제조건)
  │
  │ ── 리소스 생성 (병렬 실행 가능) ──
  │
  ├──▶ Step 2a. 인증 리소스 생성
  │     ├─ SAML/OIDC/OAuth 선택 시: Keycloak Admin API로 Client 생성
  │     └─ PAK 선택 시: Console에서 API Key 직접 생성 (Keycloak 불필요)
  │
  └──▶ Step 2b. Langfuse 리소스 생성 [Langfuse tRPC API]
         ├─ Langfuse Project 생성 (FR-1에서 생성된 Langfuse Org 하위)
         └─ SDK Key (PK/SK) 발급 (Console은 미저장)
  │
  │ ── Step 2a/2b 완료 대기 후 설정 반영 ──
  │
  ▼
Step 3. Config 반영 [Config Server Admin API 호출]
  ├─ POST /api/v1/admin/changes — LiteLLM Config + Langfuse SK/PK를 일괄 전달
  └─ Config Server가 atomic 처리 후 버전 식별자 반환 → LiteLLM 자동 전파
  │
  ▼
Step 4. Health Check 실행 (정합성 검증)
  │
  ▼
Step 5. 완료 → 프로비저닝 현황 페이지에서 결과 확인 → Project 상세 페이지로 이동
```

> **UX 플로우**: 사용자가 생성 폼을 제출하면 즉시 **프로비저닝 현황 페이지**로 리다이렉트된다. 현황 페이지에서 각 단계의 진행/성공/실패 상태가 ActionCable을 통해 실시간 업데이트되며, 전체 완료 시 Project 상세 페이지로 이동할 수 있다 (FR-7.3 참조).

**실행 순서 및 의존성**:
- Step 2a / 2b: 상호 독립적이므로 **병렬 실행 가능**
- Step 3: Step 2b의 결과(Langfuse SK/PK)가 필요하므로 **Step 2a/2b 모두 완료 후** 실행
- Step 3 내의 설정 전파: Console의 책임은 Config Server Admin API 호출까지. 이후 저장 및 LiteLLM 전파는 Config Server 모듈이 처리
- Step 4: Step 3 완료 후 실행

---

## 8. 기술 스택

| 영역 | 기술 | 비고 |
|------|------|------|
| **Backend** | Ruby on Rails 8+ | API 서버, 비즈니스 로직, Background Job 처리. Solid 스택(SolidQueue, SolidCable) 활용 |
| **Frontend** | Rails View + Hotwire (Turbo/Stimulus) | SPA 없이 실시간 UI 업데이트 |
| **실시간 통신** | ActionCable + SolidCable | 프로비저닝 로그 스트리밍. SQLite 기반 pub/sub (Redis 불필요) |
| **Background Job** | SolidQueue | SQLite 기반 잡 큐 (Rails 8 기본). Sidekiq/Redis 불필요 |
| **Database** | SQLite (WAL 모드) | Organization/Project 메타데이터, 프로비저닝 단계별 상태/설정 스냅샷, 실행 이력, 감사 로그. DB 서버 불필요 — PVC에 단일 파일로 운영 |
| **DB 백업/복구** | Litestream | SQLite → S3 실시간 스트리밍 백업. Pod 재시작 시 S3에서 자동 복원 |
| **인증/인가** | Keycloak (OIDC 인증) + Console DB (RBAC) | SAML/OIDC/OAuth Client 자동 구성 (Admin API 직접 호출). Org/Project RBAC은 Console DB 자체 관리 (섹션 5 FR-2 참조) |
| **관측성** | Langfuse (오픈소스, tRPC API 연동) | LLM 트레이싱 프로젝트 및 키 관리. 내부 tRPC API로 Org/Project CRUD |
| **LLM 게이트웨이** | LiteLLM | 모델 라우팅, 가드레일, Rate Limit |
| **Config Server** | Go 서버 (`aap-config-server`) | Console은 Admin API 호출만 수행. 암호화/저장/적용/LiteLLM 전파는 Config Server 모듈 책임 |
| **K8s 배포** | Deployment (Recreate 전략) + PVC | 단일 인스턴스 배포. 미리 생성한 PVC에 SQLite 파일 저장. Litestream Sidecar로 백업/복구 |
| **테스트** | RSpec + FactoryBot | TDD 기반 개발. 단위/통합/시스템 테스트 |
| **CI/CD** | (미정) | GitOps 기반 배포 파이프라인 |

> **관련 ADR**: [ADR-004 인증/인가 분리](./adr-004-auth-authz-separation.md) · [ADR-005 SQLite + Litestream](./adr-005-sqlite-litestream.md) · [ADR-006 Hotwire vs SPA](./adr-006-hotwire-server-rendering.md)

### 8.1 개발 방법론

- **TDD (Test-Driven Development)**: 모든 기능은 테스트 코드 선행 작성 후 구현
- **테스트 커버리지 목표**: 90% 이상
- **테스트 유형**:
  - Unit Test: 모델, 서비스 객체 단위 테스트
  - Integration Test: Keycloak Admin API, Langfuse API 등 외부 API 연동 테스트 (Mock 활용)
  - System Test: E2E 워크플로우 테스트
- **개발 프로세스 상세**: [docs/development-process.md](./development-process.md) 참조

### 8.2 K8s 배포 전략 (SQLite + Litestream)

Console은 **DB 서버 없이** SQLite 파일 하나로 운영되며, Litestream Sidecar가 S3에 실시간 백업하여 데이터 안전성을 보장한다.

**배포 구성**:

| 항목 | 설정 |
|------|------|
| **K8s 리소스** | Deployment (StatefulSet 아님) |
| **배포 전략** | `strategy.type: Recreate` (단일 인스턴스, SQLite 파일 동시 접근 방지) |
| **PVC** | 미리 생성한 PersistentVolumeClaim을 Deployment에 마운트. SQLite DB 파일 저장 |
| **Replicas** | 1 (수평 확장 불가 — SQLite 단일 writer 제약) |
| **Litestream Sidecar** | SQLite WAL 변경을 S3에 실시간 스트리밍 복제. RPO(Recovery Point Objective) ≈ 수초 |

**Pod 구성**:

```
Pod
├── Init Container: litestream restore
│   └── S3에서 SQLite 파일 복원 (최초 배포 시 또는 PVC 데이터 유실 시)
├── Container 1: rails server (Main App)
│   └── PVC 마운트 경로의 SQLite 파일 사용
└── Container 2: litestream replicate (Sidecar)
    └── SQLite WAL → S3 실시간 스트리밍 백업
```

**복구 시나리오**:

| 시나리오 | 복구 방법 |
|----------|-----------|
| **Pod 재시작** | PVC 데이터 유지 → 즉시 복구. Litestream Sidecar가 S3 복제 재개 |
| **PVC 데이터 유실** | Init Container가 S3에서 최신 백업 자동 복원 후 앱 시작 |
| **노드 장애** | Deployment가 다른 노드에 Pod 재생성. PVC(RWO)가 재마운트되거나, 접근 불가 시 Init Container가 S3에서 복원 |
| **재해 복구 (DR)** | 다른 클러스터에서 동일 S3 버킷을 참조하는 Deployment 배포 → Litestream이 S3에서 복원 |

**제약사항 및 허용 범위**:

- 업그레이드/재배포 시 `Recreate` 전략으로 인한 **짧은 다운타임** (수십 초) → 내부 관리 콘솔이므로 허용 가능
- 단일 인스턴스 배포로 **수평 확장 불가** → 예상 사용자 수(팀 관리자/플랫폼 관리자) 고려 시 충분
- SQLite 쓰기 성능 제약 → 관리 콘솔 수준의 쓰기 빈도에는 문제 없음

**향후 확장 옵션 — LiteFS 기반 Read Replica**:

제로 다운타임 배포가 필요해지면, Litestream을 LiteFS로 교체하여 Primary(R/W) + Replica(R) 2-replica 구성이 가능하다. SQLite WAL 모드의 단일 writer 제약은 유지되지만, LiteFS가 각 Pod의 로컬 파일시스템 간 near real-time 복제를 수행하여 읽기 부하 분산 및 rolling update를 지원한다. 단, leader election(Consul 등) 인프라가 추가로 필요하다.

---

## 9. 마일스톤 및 우선순위

### Phase 1: 핵심 기반 구축 (MVP)

- [ ] Rails 8 프로젝트 초기 설정 (SQLite + SolidQueue + SolidCable) 및 Keycloak SSO 인증 연동
- [ ] Keycloak First Broker Login 플로우 설정 — 이메일 매칭 기반 기존 사용자 자동 링크 (사용자 사전 할당 전제조건)
- [ ] K8s 배포 구성 (Deployment Recreate + PVC + Litestream Sidecar 백업/복구)
- [ ] Organization CRUD + 멤버십 관리 — Console DB `org_memberships` (FR-1, Langfuse Org 연동은 Phase 2에서 Langfuse tRPC 통합 시 추가)
- [ ] 접근제어 RBAC — Console DB 기반 인가 (FR-2)
- [ ] Project CRUD + App ID 자동 발급 (FR-3)
- [ ] Keycloak Admin API 연동 — OIDC Client 자동 생성 우선 (FR-4)
- [ ] 기본 UI (Organization/Project 목록, 상세, 생성 폼)

### Phase 2: 서비스 설정 자동화 확장

- [ ] Config Server 연동 (`aap-config-server`) — Console에서 Config Server Admin API 호출로 설정/시크릿 CRUD
- [ ] LiteLLM Config 자동 생성 및 동적 반영 — S3 경로/Retention 포함 (FR-6)
- [ ] Langfuse 프로젝트 생성 및 SDK Key 발급 (FR-5)

### Phase 3: 운영 안정성 강화

- [ ] 프로비저닝 파이프라인 관리 — 상태 머신, 자동 재시도, 보상 트랜잭션, 실시간 로그 (FR-7)
- [ ] 설정 변경 이력 관리 및 버전 롤백 (FR-8)
- [ ] Health Check 자동화 (FR-9)
- [ ] Project 삭제 시 전체 롤백 자동화 (FR-3 삭제 요구사항)

### Phase 4: 고도화

- [ ] 다중 인증 방식 전체 지원 (SAML, OAuth, PAK)
- [ ] 관리자 대시보드 (전체 Organization/Project 현황, 서비스 설정 상태)
- [ ] 알림 시스템 (설정 완료/실패, 이상 감지)
- [ ] 성능 최적화 및 부하 테스트

---

## 10. 리스크 및 의존성

### 10.1 리스크

| 리스크 | 영향도 | 완화 방안 |
|--------|--------|-----------|
| Langfuse tRPC API 호환성 | 중간 | 내부 API이므로 Langfuse 버전 업그레이드 시 breaking change 가능. Langfuse 버전 고정 및 업그레이드 전 tRPC 호환성 테스트 필수 |
| 공유 서비스(Keycloak/Langfuse/LiteLLM) 장애 | 높음 | 프로비저닝 파이프라인 자동 재시도 후 복구 불가 시 전체 롤백 (FR-7.2). Circuit Breaker 패턴 적용 |
| 외부 API 호출 중 부분 실패 (일부 리소스만 생성됨) | 중간 | 프로비저닝 파이프라인의 자동 재시도 + 보상 트랜잭션으로 복구 (FR-7.1, FR-7.2) |
| Config Server 장애 시 LiteLLM config 갱신 불가 | 중간 | LiteLLM은 마지막 설정으로 운영 지속. Config Server 복구 시 자동 재동기화 |
| Config Server Admin API 장애 시 설정 변경 불가 | 중간 | 프로비저닝 파이프라인 자동 재시도 (FR-7.2). Config Server 복구 시 `failed` 상태 작업을 수동 재시도 가능 (FR-7.3) |
| SQLite 파일 손상 또는 PVC 유실 | 중간 | Litestream이 S3에 실시간 백업. Init Container가 S3에서 자동 복원. RPO ≈ 수초 |
| 단일 인스턴스 배포로 인한 다운타임 | 낮음 | Recreate 전략 다운타임은 수십 초. 내부 관리 콘솔이므로 허용 가능. Liveness/Readiness Probe로 빠른 복구 보장 |
| Console Service Account 권한 과다 | 중간 | `manage-clients`/`manage-users`가 Realm 전체 범위. Console 버그 시 타 팀 Client 영향 가능. **완화**: 코드 레벨에서 `aap-` prefix Client만 조작하도록 방어. Client 조작 전 prefix 검증 로직 필수. 통합 테스트로 범위 이탈 방지 |

### 10.2 외부 의존성

| 시스템 | 의존 유형 | 비고 |
|--------|-----------|------|
| Keycloak | Admin REST API | 순수 인증(OIDC) + SAML/OIDC/OAuth Client 자동 구성 + 사용자 검색/조회. **사전 설정 필요**: First Broker Login 플로우에서 이메일 매칭 기반 기존 사용자 자동 링크 설정 (사용자 사전 할당 기능의 전제조건) |
| Langfuse | 내부 tRPC API (오픈소스) | 웹 UI 내부 tRPC API로 Org/Project/API Key CRUD. NextAuth 세션 쿠키 인증 |
| LiteLLM | Config Server 경유 설정 전파 | 모델 라우팅, 가드레일, S3 경로 설정 |
| Config Server | `aap-config-server` Admin API | Console은 Admin API 호출만 수행. 암호화/저장/적용/전파는 Config Server 책임. Config Server 시작 시 Console의 `GET /api/v1/apps` 호출 (App Registry 로드) |
| S3 (Object Storage) | Litestream 백업 + Langfuse 데이터 | stg/prd: Managed S3 서비스. dev: MinIO (클러스터 내 자체 배포) |
| aap-helm-charts | Git Repo | AAP 서비스 배포용 Helm Chart 관리 |

---

## 11. 부록

- **업무 목표 상세**: [docs/business-objectives.md](./business-objectives.md)
- **UI 사양**: [docs/ui-spec.md](./ui-spec.md)
