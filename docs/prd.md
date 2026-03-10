# AAP Console — Product Requirements Document (PRD)

> 버전: 1.3
> 작성일: 2026-03-05
> 최종 수정일: 2026-03-10
> 상태: Draft

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

### 1.3 대상 사용자

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
| **Config Server** | Go 기반 경량 설정 관리 서버. Git을 source of truth로 사용하여 설정 파일을 인메모리에 적재하고 REST API로 서빙한다 (읽기 전용). 시크릿은 Git에 메타데이터(secret_ref)만 저장하고, 실제 값은 K8s Secret을 Volume Mount로 읽어 resolve한다. mTLS로 전송 보호. 별도 레포(`aap-config-server`)로 관리 |
| **Config Agent** | Config Server에서 설정을 fetch하여 클라이언트 서비스(LiteLLM 등)가 읽을 수 있는 로컬 파일로 변환하는 Sidecar 컨테이너. Init Container로 초기 설정 로드, Sidecar로 long polling 기반 변경 감지 및 hot reload 수행 |
| **Provisioner** | Console 내부의 서비스 객체. Keycloak Admin API, Langfuse API 등 외부 서비스 API를 직접 호출하여 리소스를 생성/수정/삭제하는 Background Job 단위 |

---

## 3. 시스템 아키텍처 개요

```
                         ┌──────────────┐
                         │  사내 SSO IdP │
                         └──────┬───────┘
                                │
                         ┌──────▼───────┐
                         │   Keycloak   │◄─── Admin REST API ───┐
                         │ (SSO Broker) │                       │
                         └──────┬───────┘                       │
                       인증 후   │                               │
               ┌────────────────┼────────────────┐              │
               ▼                ▼                ▼              │
        ┌────────────┐  ┌────────────┐  ┌──────────────┐       │
        │ AAP Console│  │  LiteLLM   │  │   Langfuse   │──▶ S3 │
        │  (Rails)   │  │ (LLM G/W)  │  │  (관측성)     │       │
        └─────┬──────┘  └────────────┘  └───┬──────────┘       │
              │               ▲ 로컬 파일 읽기  │ ◄─── Langfuse API
              │         ┌─────┴──────┐         │                │
              │         │Config Agent│         │                │
              │         │  (Go CLI)  │  Sidecar (init + watch)  │
              │         └─────┬──────┘                          │
              │          fetch │ (mTLS + App ID/Secret)         │
    ┌─────────▼─────┐  ┌─────▼──────────┐                      │
    │ Provisioner   │  │ Config Server  │  Go 인메모리 서버      │
    │ (SolidQueue   │──│  · Git Sync    │  (aap-config-server)  │
    │  Bg Jobs)     │  │  · Secret Vol. │                       │
    └───┬───┬───────┘  └────────────────┘                       │
        │   │                 ▲                                 │
        │   │  git push       │ git poll / volume mount         │
        │   │                 │                                 │
        │   ▼                 │                                 │
        │  Config Git Repo    │    K8s Secrets                  │
        │  (설정 YAML)        │    (시크릿 실제 값)              │
        │                     │                                 │
        └─────────────────────┴─────────────────────────────────┘
              Keycloak / Langfuse API 직접 호출 + Git 커밋 + K8s Secret 관리

┌─ K8s Cluster ──────────────────────────────────────────┐
│                                                         │
│  Keycloak · LiteLLM · Langfuse · Config Server · ...   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**흐름 설명**:
- **사용자 인증**: 사용자 → Keycloak(SSO IdP 브로커) → 인증 후 AAP Console / LiteLLM / Langfuse 접근
- **Project 설정 반영** (2경로):
  1. **리소스 생성 (Admin API 직접 호출)**: Keycloak Admin REST API로 Client 생성, Langfuse API로 프로젝트 생성 등
  2. **동적 Config 반영 (Config Git + K8s Secret)**:
     - Console이 설정 파일(config.yaml, secrets.yaml 등)을 Config Git Repo에 직접 커밋
     - 시크릿 실제 값은 Console이 `kubectl apply`로 K8s Secret에 저장
     - Config Server가 Git 변경을 감지(webhook/poll)하여 인메모리 갱신
     - Config Agent Sidecar가 long polling으로 변경 감지 → 로컬 파일 갱신 → LiteLLM hot reload (재배포 불필요)

**Config Server 동작 방식**:
- Go 기반 인메모리 서버. 시작 시 Git clone → 설정 파싱 → 메모리 적재
- REST API로 설정을 읽기 전용 서빙 (쓰기 API 없음)
- 시크릿은 K8s Secret Volume Mount로 읽기만 함 (kubectl 미사용)
- `resolve_secrets=true` 요청 시 메타데이터 ID로 Volume에서 실제 값 조회 → mTLS 채널로 응답
- DB 없이 Git으로만 데이터와 변경 이력을 관리
- Config Agent Sidecar가 long polling + init container 패턴으로 클라이언트 서비스에 설정 전달

---

## 4. 리소스 계층 구조

```
Organization (조직)
 └── Project (App ID 발급)
      │
      ├── 인증 설정
      │    ├── Keycloak Client ──── [Keycloak Admin REST API]
      │    │    └── SAML / OIDC / OAuth Client 자동 생성
      │    └── PAK ──────────────── [Console 자체 생성]
      │         └── Project API Key 발급 (Keycloak 미사용)
      │
      ├── Langfuse 설정 ─────────── [Langfuse API]
      │    ├── Langfuse Org/Project 생성
      │    └── SDK Key 발급 (PK/SK)
      │         ├── 메타데이터(secret_ref) → Config Git Repo에 커밋
      │         └── 실제 SK/PK → K8s Secret (Console이 kubectl apply)
      │
      └── LiteLLM 설정 ──────────── [Config Git Repo]
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
| **생성** | 신규 Organization 등록. 조직명, 설명 입력. 생성 시 멤버 목록 관리 (초기 관리자 지정) |
| **조회** | Organization 목록 및 상세 정보 (소속 Project 현황, 멤버 목록 포함) 확인 |
| **수정** | Organization 정보 변경 (이름, 설명) 및 멤버 추가/제거/권한 변경 |
| **삭제** | Organization 삭제 시 하위 모든 Project의 설정도 함께 제거. **플랫폼 관리자(`super_admin`)만 실행 가능** |

### FR-2. 접근제어 (RBAC) — Keycloak 위임

Organization 단위로 사용자 접근 권한을 관리한다. **RBAC은 Keycloak 그룹에 위임**하며, Console은 별도의 권한 테이블을 유지하지 않는다. 하위 Project에 대한 접근 범위도 Organization 멤버십에 의해 결정된다.

#### Keycloak 구성 (단일 Realm)

AAP는 **단일 Realm 정책**을 사용한다. Console은 LiteLLM, Langfuse 등과 동일한 레벨의 OIDC Client로 등록되며, Console 전용 RBAC 정보는 **전용 Client Scope**로 격리하여 다른 Client의 토큰에 영향을 주지 않는다.

```
Realm: aap (단일)
 ├── Client: litellm           ← 기존 서비스 (기본 scope만)
 ├── Client: langfuse          ← 기존 서비스 (기본 scope만)
 ├── Client: {team}-agent      ← 타 팀 서비스 (기본 scope만)
 └── Client: aap-console       ← Console (기본 scope + console-rbac scope)
      ├── OIDC Confidential Client (Authorization Code Flow)
      ├── Service Account 활성화 (Keycloak Admin API 호출용)
      └── Client Scope: "console-rbac" (aap-console에만 할당)
           └── Protocol Mapper: Group Membership
                ├── claim.name: groups
                ├── full.path: true
                └── add.to.access.token: true
```

**Client Scope 분리 원칙**: `console-rbac` Client Scope는 `aap-console` Client에만 할당한다. LiteLLM, Langfuse 등 다른 Client의 토큰에는 Console RBAC용 `groups` 클레임이 포함되지 않는다.

**Service Account 권한**: Console이 Org 생성/멤버 관리 및 Project별 인증 Client 자동 구성을 위해 Keycloak Admin API를 호출한다. `aap-console` Client의 Service Account에 최소 권한을 부여한다.

| Service Account Role | 용도 |
|---|---|
| `realm-management: manage-clients` | Client 생성/수정/삭제 (OIDC/SAML/OAuth) 및 Protocol Mapper 관리 |
| `realm-management: manage-groups` | 그룹 생성/삭제 (Organization 생성/삭제 시 하위 그룹 CRUD) |
| `realm-management: query-groups` | 그룹 목록/상세 조회 |
| `realm-management: manage-users` | 사용자-그룹 멤버십 변경 |
| `realm-management: query-users` | 사용자 검색 |

#### 권한 모델

| 항목 | 상세 |
|------|------|
| **권한 수준** | `super_admin` — 플랫폼 전체 관리. Organization 생성/삭제, 전체 현황 조회, 정책 설정 (플랫폼 관리자 전용) <br> `admin` — Org 설정 및 멤버 관리, Project 생성/삭제 가능 <br> `write` — Project 설정 변경 가능 <br> `read` — Project 조회만 가능 |
| **Keycloak 그룹 구조** | 계층적 그룹으로 Organization별 권한을 관리한다. `/console` prefix로 다른 서비스의 그룹과 충돌을 방지한다. 구조: `/console/orgs/{org-id}/admin`, `/console/orgs/{org-id}/write`, `/console/orgs/{org-id}/read`. 플랫폼 전체 `super_admin`은 별도 **Realm Role**로 관리 |
| **JWT 토큰 클레임** | `console-rbac` Client Scope의 Group Membership mapper에 의해 `aap-console` Client의 JWT에만 `groups` 클레임이 포함된다 (`full.path: true`). 예: `["\/console\/orgs\/acme-corp\/admin"]` |
| **멤버 관리** | Organization 생성/수정 시 `aap-console` Service Account로 Keycloak Admin API를 호출하여 사용자를 해당 Org 그룹에 추가/제거/역할 변경. Console은 Keycloak을 단일 진실 공급원(SSOT)으로 사용 |
| **권한 상속** | Organization 멤버십이 하위 모든 Project에 동일하게 적용 |
| **Console UI 제어** | JWT 토큰의 `groups` 클레임을 파싱하여 권한 수준에 따라 UI 요소(버튼, 메뉴 등) 활성/비활성 처리 |
| **API 제어** | 모든 API 엔드포인트에서 JWT 토큰의 `groups` 클레임을 검증하여 요청자의 권한 수준을 확인. DB 조회 없이 토큰만으로 인가 처리 |

#### Keycloak Admin API 연동

| Console 작업 | Keycloak Admin API |
|---|---|
| Org 생성 | `POST /admin/realms/{realm}/groups` → `/console/orgs/{org-id}` 하위 그룹(admin/write/read) 자동 생성 |
| 멤버 추가 | `PUT /admin/realms/{realm}/users/{user-id}/groups/{group-id}` |
| 멤버 제거 | `DELETE /admin/realms/{realm}/users/{user-id}/groups/{group-id}` |
| 권한 변경 | 기존 그룹에서 제거 → 새 권한 그룹에 추가 |
| Org 삭제 | `DELETE /admin/realms/{realm}/groups/{group-id}` (하위 그룹 포함 삭제) |

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
| **Langfuse 리소스** | Langfuse API를 통해 프로젝트 및 SDK Key 삭제 |
| **Config Git Repo** | 해당 App의 LiteLLM Config 및 Langfuse 시크릿 메타데이터를 Git에서 제거 후 커밋 → Config Server가 변경 감지 → Config Agent가 long polling으로 갱신 |
| **K8s Secret** | 해당 App의 시크릿 값이 저장된 K8s Secret을 Console이 `kubectl delete`로 삭제 |

> **구현 고려사항**: 동일 파일 내에서 여러 Project의 설정이 공존할 수 있으므로, Project별 설정 격리 전략이 필요하다. 삭제 시 다른 Project의 설정을 훼손하지 않도록 App ID 기반의 섹션 분리 또는 파일 분리 방식을 설계해야 한다.

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

**Keycloak Admin API 연동 (Client 관리)**:

| Console 작업 | Keycloak Admin API |
|---|---|
| OIDC Client 생성 | `POST /admin/realms/{realm}/clients` — `protocol: openid-connect`, `publicClient: false`, `serviceAccountsEnabled: true` |
| SAML Client 생성 | `POST /admin/realms/{realm}/clients` — `protocol: saml`, SAML 설정 attributes 포함 |
| OAuth Client 생성 | `POST /admin/realms/{realm}/clients` — `protocol: openid-connect`, `publicClient: true`, PKCE 설정 |
| Client 설정 변경 | `PUT /admin/realms/{realm}/clients/{id}` |
| Client 삭제 | `DELETE /admin/realms/{realm}/clients/{id}` |
| Client Secret 재발급 | `POST /admin/realms/{realm}/clients/{id}/client-secret` |
| Protocol Mapper 추가 | `POST /admin/realms/{realm}/clients/{id}/protocol-mappers/models` |

### FR-5. Langfuse 프로젝트 생성 및 SDK Key 발급

| 항목 | 상세 |
|------|------|
| **프로젝트 생성** | Langfuse API를 통해 Project별 독립 Langfuse 프로젝트 자동 생성 |
| **SDK Key 발급** | Public Key, Secret Key 자동 발급. Console은 SK/PK를 **저장하지 않고** 즉시 처리 |
| **시크릿 메타데이터 커밋** | Console이 SK/PK의 메타데이터(`secret_ref`: ID, K8s Secret 이름/키 등)를 `secrets.yaml`로 작성하여 Config Git Repo에 직접 커밋 (실제 SK/PK 값 미포함) |
| **K8s Secret 생성** | Console이 `kubectl apply`로 K8s Secret을 생성하여 실제 SK/PK 값을 저장. Config Server Pod에 Volume Mount로 자동 반영 |
| **트레이싱 연동** | Config Agent Sidecar가 Config Server API를 호출(`resolve_secrets=true`) → Config Server가 `secret_ref`로 Volume Mount에서 실제 값을 조회하여 mTLS 응답 → Config Agent가 로컬 config 파일에 시크릿 resolve하여 기록 → LiteLLM이 Langfuse 트레이싱 자동 연동 |

> **설계 원칙**: Git에는 시크릿 값이 올라가지 않는다. 실제 SK/PK는 K8s Secret에만 존재하며, `secrets.yaml`의 `secret_ref`를 통해 참조한다. Config Server는 Volume Mount로 읽기만 하고, K8s Secret 생성/삭제는 Console이 수행한다.
>
> **인가**: Console이 사용자 RBAC 권한을 검증한 후 Git 커밋 및 K8s Secret 생성을 수행한다. Config Server는 App ID/Secret + mTLS 기반 서비스 인증 및 scope 검증만 수행한다 (비기능 요구사항 6.1 참조).

### FR-6. LiteLLM Config 자동 생성 및 동적 반영

| 항목 | 상세 |
|------|------|
| **모델 라우팅** | 사용할 LLM 목록 선택 및 모델별 정책(Rate Limit 등) 구성 |
| **가드레일** | 사용자 선택 기반의 보안 가드레일 적용 (컨텐츠 필터링, 토큰 제한 등) |
| **S3 경로** | App별 S3 버킷 경로 (prefix)를 Config에 포함. 기존 공유 버킷을 사용하며 별도 버킷 생성 불필요 |
| **S3 Retention** | App별 S3 데이터 보관 주기를 LiteLLM Config 변수로 설정. LiteLLM이 해당 변수를 읽어 커스텀 구현된 Retention 로직을 적용 (S3 Lifecycle Policy가 아닌 애플리케이션 레벨 처리) |
| **Config 반영** | Console이 생성한 Config를 Config Git Repo에 직접 커밋 (`config.yaml`, `env_vars.yaml`, `secrets.yaml` 등 Config Server 저장소 구조에 맞춰 작성) |
| **Reload 방식** | Git 커밋 → Config Server가 webhook/poll로 변경 감지 → 인메모리 갱신 → Config Agent Sidecar가 long polling으로 변경 감지 → 로컬 config 파일 atomic write → LiteLLM hot reload (재배포 불필요) |

### FR-7. 실시간 프로비저닝 로그 시각화

| 항목 | 상세 |
|------|------|
| **로그 스트리밍** | Project 생성/수정/삭제 시 각 단계(Keycloak Client 생성, Langfuse 프로젝트 생성, Config 반영 등)의 진행 상황을 실시간 전송 |
| **UI 표시** | Console에서 프로비저닝 진행 상황을 실시간으로 확인 가능 (단계별 성공/실패/진행중 표시) |
| **구현 방식** | ActionCable(WebSocket) 기반 실시간 스트리밍 |
| **이력 보관** | 완료된 프로비저닝 로그는 저장하여 사후 조회 가능 |

### FR-8. 설정 변경 이력 관리 및 버전 롤백

| 항목 | 상세 |
|------|------|
| **이력 관리** | Project별 설정 변경 시마다 버전 기록 (Console DB 이력 + Config Git 커밋 기반) |
| **버전 조회** | Console에서 변경 이력 목록 및 diff 확인 |
| **롤백 — Keycloak** | Console DB에 기록된 이전 설정 스냅샷(Client 생성 시 파라미터를 버전별로 저장)을 기반으로 Keycloak Admin API를 호출하여 Client 설정 복구 (`PUT /admin/realms/{realm}/clients/{id}`) |
| **롤백 — Config Server** | Config Git Repo 이력을 기반으로 LiteLLM Config 및 Langfuse 메타데이터를 이전 버전으로 복구 (Console이 Git revert 커밋) → Config Server 인메모리 자동 갱신 → Config Agent long polling으로 전파 |
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
- Langfuse SK/PK는 Console 미저장. 메타데이터(`secret_ref`)는 Git에, 실제 값은 K8s Secret에 분리 저장. Config Server는 Volume Mount로 읽기만 수행
- Git 레포에는 시크릿 실제 값이 저장되지 않음 (메타데이터 ID 참조 방식)
- Console 접근은 조직 SSO를 통한 인증 필수
- Organization 단위 RBAC (admin/write/read) 기반 접근제어 — Keycloak 그룹에 위임 (FR-2 참조)
- Console → Config Server 요청 시 인증/인가 검증 (아래 상세)
- Project 간 서비스 설정 격리 (테넌트 격리)
- API 통신 시 TLS 필수

**Console → Config Server / Config Git Repo 인증/인가**:

Config Server는 읽기 전용 API만 제공한다. 설정 변경은 Console이 Config Git Repo에 직접 커밋하고, K8s Secret은 Console이 직접 `kubectl apply/delete`로 관리한다.

| 계층 | 검증 주체 | 검증 내용 |
|------|-----------|-----------|
| **사용자 권한 검증** | **Console** | API 요청 수신 시 JWT 토큰의 `groups` 클레임(`/console/orgs/{org-id}/...` 경로)을 파싱하여 요청 사용자가 대상 Org/Project에 대한 `write` 이상 권한을 보유하는지 검증. DB 조회 없이 토큰만으로 인가 처리. 권한 미달 시 Git 커밋 및 K8s Secret 조작을 수행하지 않음 |
| **Config Git 접근** | **Console** | Config Git Repo에 대한 쓰기 권한은 Console 서비스 계정에만 부여. 커밋 시 Org/Project 디렉토리 범위 내에서만 파일 변경 |
| **Config Server API 인증** | **Config Server** | mTLS(TLS 1.3) 상호 인증 + App ID/App Secret 기반 API 인증. AAP Console이 발급한 App Registry를 주기적으로 동기화하여 검증 |
| **Config Server 접근 범위** | **Config Server** | App Registry의 scope(org/project/service)와 permissions(`config_read`, `resolve_secrets` 등)를 기반으로 요청 범위 제한 |

### 6.2 성능

- Project 생성 요청 후 전체 설정 완료까지 목표: 1분 이내
- Console UI 페이지 로드 시간: 2초 이내
- 실시간 로그 스트리밍 지연: 1초 이내

### 6.3 확장성

- 동시 다수 Project 생성 요청 처리 가능 (Background Job 큐 기반)
- Organization 및 Project 수 증가에 따른 수평 확장 고려

### 6.4 가용성

- 외부 API 호출 실패 시 자동 재시도 및 롤백 메커니즘 (이미 생성된 리소스 정리)
- 공유 서비스(Keycloak, Langfuse, LiteLLM) 장애 시 부분 실패 처리 및 재시도

### 6.5 동시성 제어

다수 사용자가 동시에 Project를 생성/수정/삭제해도 데이터 정합성이 보장되어야 한다.

| 대상 | 동시성 제어 방식 |
|------|------------------|
| **Console DB (SQLite)** | SQLite WAL 모드로 동시 읽기 허용, 쓰기는 단일 프로세스 직렬화. 단일 인스턴스 배포이므로 DB 레벨 동시성 문제 최소화. Project 상태를 `pending → provisioning → active → deleting` 등의 상태 머신으로 관리하여 중복 처리 방지 |
| **외부 API 호출** | SolidQueue Job 직렬화로 동일 Project에 대한 동시 프로비저닝 방지. Keycloak/Langfuse API 호출은 멱등성을 고려하여 설계 (생성 전 존재 여부 확인) |
| **Config Git Repo** | Console이 Git 커밋 시 App ID 단위 디렉토리 분리로 충돌 최소화. 동일 Project에 대한 동시 커밋은 SolidQueue Job 직렬화로 방지. 충돌 발생 시 자동 rebase 후 재시도 |
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
  │ ── 리소스 생성 (병렬 실행 가능) ──
  │
  ├──▶ Step 2a. 인증 리소스 생성
  │     ├─ SAML/OIDC/OAuth 선택 시: Keycloak Admin API로 Client 생성
  │     └─ PAK 선택 시: Console에서 API Key 직접 생성 (Keycloak 불필요)
  │
  └──▶ Step 2b. Langfuse 리소스 생성 [Langfuse API]
         ├─ Langfuse Org/Project 생성
         └─ SDK Key (PK/SK) 발급 (Console은 미저장)
  │
  │ ── Step 2a/2b 완료 대기 후 설정 반영 ──
  │
  ▼
Step 3. Config 반영 [Console이 직접 Git 커밋 + K8s Secret 생성]
  ├─ LiteLLM Config (config.yaml, env_vars.yaml) → Config Git Repo에 커밋
  ├─ Langfuse SK/PK 시크릿 메타데이터 (secrets.yaml) → Config Git Repo에 커밋
  ├─ SK/PK 실제 값 → Console이 kubectl apply로 K8s Secret 생성
  └─ Config Server가 Git 변경 감지 → 인메모리 갱신
       → Config Agent Sidecar가 long polling으로 변경 감지
       → 로컬 config 파일 갱신 → LiteLLM hot reload
  │
  ▼
Step 4. Health Check 실행 (정합성 검증)
  │
  ▼
Step 5. 완료 → Console에 결과 표시
```

**실행 순서 및 의존성**:
- Step 2a / 2b: 상호 독립적이므로 **병렬 실행 가능**
- Step 3: Step 2b의 결과(Langfuse SK/PK)가 필요하므로 **Step 2a/2b 모두 완료 후** 실행
- Step 3 내의 설정 전파: Git 커밋 → Config Server 자동 감지 → Config Agent 자동 감지 (비동기, Console이 직접 제어하지 않음)
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
| **인증/인가** | Keycloak (Admin REST API + RBAC) | SAML/OIDC/OAuth Client 자동 구성 (Admin API 직접 호출). Organization 단위 RBAC을 Keycloak 그룹으로 관리 (섹션 5 FR-2 참조) |
| **관측성** | Langfuse (API 연동) | LLM 트레이싱 프로젝트 및 키 관리 |
| **LLM 게이트웨이** | LiteLLM + Config Agent Sidecar | 모델 라우팅, 가드레일, Rate Limit. Config Agent가 Config Server에서 설정 fetch하여 로컬 파일로 제공 |
| **Config Server** | Go 인메모리 서버 (`aap-config-server`) | Git sync → 인메모리 적재 → REST API 서빙 (읽기 전용). K8s Secret Volume Mount로 시크릿 resolve. mTLS + App ID/Secret 인증. Helm Chart는 `aap-helm-charts`에 포함 |
| **Config Agent** | Go CLI (Sidecar/Init Container) | Config Server에서 설정 fetch → 네이티브 config 파일 생성. Long polling으로 변경 감지 및 hot reload |
| **K8s 배포** | Deployment (Recreate 전략) + PVC | 단일 인스턴스 배포. 미리 생성한 PVC에 SQLite 파일 저장. Litestream Sidecar로 백업/복구 |
| **테스트** | RSpec + FactoryBot | TDD 기반 개발. 단위/통합/시스템 테스트 |
| **CI/CD** | (미정) | GitOps 기반 배포 파이프라인 |

### 8.1 개발 방법론

- **TDD (Test-Driven Development)**: 모든 기능은 테스트 코드 선행 작성 후 구현
- **테스트 커버리지 목표**: 90% 이상
- **테스트 유형**:
  - Unit Test: 모델, 서비스 객체 단위 테스트
  - Integration Test: Keycloak Admin API, Langfuse API 등 외부 API 연동 테스트 (Mock 활용)
  - System Test: E2E 워크플로우 테스트

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

---

## 9. 마일스톤 및 우선순위

### Phase 1: 핵심 기반 구축 (MVP)

- Rails 8 프로젝트 초기 설정 (SQLite + SolidQueue + SolidCable) 및 Keycloak SSO 인증 연동
- K8s 배포 구성 (Deployment Recreate + PVC + Litestream Sidecar 백업/복구)
- Organization CRUD + 멤버십 관리 — Keycloak 그룹 연동 (FR-1)
- 접근제어 RBAC — Keycloak 그룹 기반 JWT 인가 (FR-2)
- Project CRUD + App ID 자동 발급 (FR-3)
- Keycloak Admin API 연동 — OIDC Client 자동 생성 우선 (FR-4)
- 기본 UI (Organization/Project 목록, 상세, 생성 폼)

### Phase 2: 서비스 설정 자동화 확장

- Config Server 연동 (`aap-config-server`) — Console에서 Config Git Repo 커밋 + K8s Secret 관리
- Config Agent Sidecar를 통한 LiteLLM 동적 설정 반영 파이프라인 구축
- LiteLLM Config 자동 생성 및 동적 반영 — S3 경로/Retention 포함 (FR-6)
- Langfuse 프로젝트 생성 및 SDK Key 발급 (FR-5)

### Phase 3: 운영 안정성 강화

- 실시간 프로비저닝 로그 스트리밍 — ActionCable (FR-7)
- 설정 변경 이력 관리 및 버전 롤백 (FR-8)
- Health Check 자동화 (FR-9)
- Project 삭제 시 전체 롤백 자동화 (FR-3 삭제 요구사항)

### Phase 4: 고도화

- 다중 인증 방식 전체 지원 (SAML, OAuth, PAK)
- 관리자 대시보드 (전체 Organization/Project 현황, 서비스 설정 상태)
- 알림 시스템 (설정 완료/실패, 이상 감지)
- 성능 최적화 및 부하 테스트

---

## 10. 리스크 및 의존성

### 10.1 리스크

| 리스크 | 영향도 | 완화 방안 |
|--------|--------|-----------|
| 공유 서비스(Keycloak/Langfuse/LiteLLM) 장애 | 높음 | Circuit Breaker 패턴, 부분 실패 허용, 재시도 로직 |
| 외부 API 호출 중 부분 실패 (일부 리소스만 생성됨) | 중간 | 보상 트랜잭션 패턴으로 이미 생성된 리소스 자동 정리. Console DB에 프로비저닝 단계별 상태 기록 |
| Config Server 장애 시 LiteLLM config 갱신 불가 | 중간 | Config Agent가 마지막으로 기록한 로컬 config 파일로 LiteLLM 운영 지속. Config Server 복구 시 Config Agent long polling이 자동 재연결 |
| Config Git Repo 충돌 | 낮음 | Retry with rebase, 충돌 감지 및 알림 |
| SQLite 파일 손상 또는 PVC 유실 | 중간 | Litestream이 S3에 실시간 백업. Init Container가 S3에서 자동 복원. RPO ≈ 수초 |
| 단일 인스턴스 배포로 인한 다운타임 | 낮음 | Recreate 전략 다운타임은 수십 초. 내부 관리 콘솔이므로 허용 가능. Liveness/Readiness Probe로 빠른 복구 보장 |

### 10.2 외부 의존성

| 시스템 | 의존 유형 | 비고 |
|--------|-----------|------|
| Keycloak | Admin REST API | RBAC 그룹 관리 + SAML/OIDC/OAuth Client 자동 구성 |
| Langfuse | REST API | 프로젝트/키 관리 |
| LiteLLM | Config Agent Sidecar → Config Server | 모델 라우팅, 가드레일, S3 경로 설정 |
| Config Server | Go 인메모리 서버 + Git + K8s Secret Volume (`aap-config-server`) | 읽기 전용 설정 API + 시크릿 resolve 서빙 |
| Config Git Repo | Git | Console이 설정 파일을 직접 커밋. Config Server가 poll/webhook으로 동기화 |
| aap-helm-charts | Git Repo | AAP 서비스 배포용 Helm Chart 관리 |

---

## 11. 부록

- **업무 목표 상세**: [docs/business-objectives.md](./business-objectives.md)
