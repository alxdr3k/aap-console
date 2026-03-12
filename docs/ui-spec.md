# AAP Console — UI Specification (UI Spec)

> **Version**: 0.1
> **Date**: 2026-03-12
> **Status**: Draft
> **References**: [PRD v1.12](./PRD.md) · [HLD v1.6](./HLD.md)

---

## 목차

1. [설계 원칙](#1-설계-원칙)
2. [기술 기반](#2-기술-기반)
3. [화면 구조](#3-화면-구조)
4. [페이지 목록](#4-페이지-목록)
5. [프로비저닝 상태 표시 규칙](#5-프로비저닝-상태-표시-규칙)
6. [공통 UI 패턴](#6-공통-ui-패턴)
7. [접근제어와 UI](#7-접근제어와-ui)

---

## 1. 설계 원칙

| 원칙 | 설명 | 하지 않는 것 |
|------|------|-------------|
| **Server-rendered First** | Hotwire(Turbo + Stimulus)로 SPA 없이 실시간 UI 구현 | React/Vue 등 클라이언트 프레임워크 도입 |
| **Progressive Enhancement** | JavaScript 비활성화 시에도 핵심 기능(CRUD) 동작 | JS 필수 기능 의존 |
| **Minimal Interactivity** | 실시간 업데이트가 필요한 곳(프로비저닝 현황)에만 WebSocket 사용 | 모든 페이지에 실시간 연결 |
| **관리 콘솔 UX** | 정보 밀도 높은 테이블/폼 중심 레이아웃 | 마케팅 사이트 스타일의 넓은 여백 |
| **명확한 상태 전달** | 프로비저닝 상태를 색상 + 아이콘 + 텍스트로 중복 전달 | 색상만으로 상태 구분 (색각 이상 고려) |

---

## 2. 기술 기반

| 영역 | 기술 | 비고 |
|------|------|------|
| **템플릿** | ERB (Rails View) | |
| **실시간 UI** | Turbo Streams + ActionCable | 프로비저닝 현황 등 |
| **페이지 전환** | Turbo Drive | SPA 느낌의 전환, 전체 리로드 없음 |
| **인라인 편집** | Turbo Frames | 모달, 인라인 폼 등 |
| **클라이언트 로직** | Stimulus Controllers | 검색 자동완성, 토글, 클립보드 복사 등 |
| **스타일** | (미정 — Tailwind CSS 또는 Rails 기본) | Phase 1에서 결정 |

---

## 3. 화면 구조

### 3.1 전체 레이아웃

```
┌─────────────────────────────────────────────────────┐
│  [AAP Console 로고]              [사용자명 ▼ 로그아웃] │
├──────────┬──────────────────────────────────────────┤
│ 사이드바  │  메인 콘텐츠                               │
│          │                                          │
│ ◆ Orgs   │  Breadcrumb: Console > Acme > Chatbot    │
│  └ Acme  │  ─────────────────────────────────       │
│    └ ... │  [페이지별 콘텐츠]                         │
│  └ Beta  │                                          │
│          │                                          │
│ ── ──── │                                          │
│ ◇ 관리   │                                          │
│ (super   │                                          │
│  admin)  │                                          │
│          │                                          │
└──────────┴──────────────────────────────────────────┘
```

### 3.2 네비게이션 구조

```
AAP Console
├── Organizations (목록)
│   └── {Organization} (상세)
│       ├── Projects (탭 또는 섹션)
│       │   └── {Project} (상세)
│       │       ├── 인증 설정
│       │       ├── LiteLLM Config
│       │       ├── 변경 이력
│       │       ├── Playground (AI Chat)
│       │       └── 프로비저닝 이력
│       │           └── {Job} (프로비저닝 현황 — 실시간)
│       └── 멤버 관리
└── 관리 (super_admin)
    └── 전체 Organization 현황
```

---

## 4. 페이지 목록

### 4.1 Organization

| 페이지 | URL 패턴 | 주요 기능 | 관련 FR |
|--------|---------|-----------|---------|
| Organization 목록 | `/organizations` | 소속 Org 카드 목록, 검색 | FR-1 |
| Organization 상세 | `/organizations/:id` | Org 정보, Project 목록, 멤버 요약 | FR-1 |
| Organization 생성 | `/organizations/new` | 이름, 설명 입력 (super_admin) | FR-1 |
| 멤버 관리 | `/organizations/:id/members` | 멤버 목록, 추가/제거/권한 변경 | FR-2 |

### 4.2 Project

| 페이지 | URL 패턴 | 주요 기능 | 관련 FR |
|--------|---------|-----------|---------|
| Project 생성 | `/organizations/:org_id/projects/new` | 이름, 인증 방식, 모델 선택 | FR-3 |
| Project 상세 | `/organizations/:org_id/projects/:id` | 설정 현황, 인증 정보, Config 요약 | FR-3 |
| 인증 설정 | `/.../:id/auth_config` | 인증 방식 상세, Client Secret 재발급 | FR-4 |
| LiteLLM Config | `/.../:id/litellm_config` | 모델 라우팅, 가드레일, S3 설정 편집 | FR-6 |
| 변경 이력 | `/.../:id/config_versions` | 버전 목록, diff 조회, 롤백 | FR-8 |
| Playground | `/.../:id/playground` | 모델 선택, AI Chat, 요청 인스펙터 | FR-10 |
| 프로비저닝 이력 | `/.../:id/provisioning_jobs` | 과거 Job 목록 | FR-7.3 |

### 4.3 프로비저닝

| 페이지 | URL 패턴 | 주요 기능 | 관련 FR |
|--------|---------|-----------|---------|
| 프로비저닝 현황 | `/provisioning_jobs/:id` | 실시간 Step 상태, 오류 표시, 수동 재시도 | FR-7.3 |

---

## 5. 프로비저닝 상태 표시 규칙

> HLD Section 9.4의 UI 매핑 테이블을 UI 구현에 반영한다.

### 5.1 Job 전체 상태

| 내부 상태 | UI 텍스트 | 배지 색상 | 아이콘 |
|-----------|----------|----------|--------|
| `pending` | 대기 | `gray` | ○ |
| `in_progress` | 진행중 | `blue` | ⟳ |
| `completed` | 완료 | `green` | ✓ |
| `failed` | 실패 | `red` | ✗ |
| `retrying` | 재시도중 | `yellow` | ⟳ |
| `rolling_back` | 정리중 | `orange` | ⟳ |
| `rolled_back` | 실패 (정리 완료) | `red` | ✗ |
| `rollback_failed` | 실패 (수동 조치 필요) | `red` | ⚠ |

### 5.2 Step 상태

| 내부 상태 | UI 텍스트 | 설명 |
|-----------|----------|------|
| `pending` | 대기 | 아직 실행되지 않은 단계 |
| `in_progress` | 진행중... | 현재 실행 중인 단계 |
| `completed` | 완료 | 성공적으로 완료된 단계 |
| `failed` | 실패 | 실패한 단계 (오류 메시지 표시) |
| `rolled_back` | 롤백 완료 | 보상 트랜잭션으로 정리된 단계 |
| `rollback_failed` | 롤백 실패 | 보상 트랜잭션 실패 (수동 개입 필요) |

### 5.3 표시 규칙

- **색상 + 아이콘 + 텍스트** 3중 전달 — 색각 이상 사용자를 위해 색상만으로 구분하지 않음
- 실패 상태(`failed`, `rolled_back`, `rollback_failed`)는 모두 **빨간색 계열**로 통일 — 사용자에게 "실패"를 명확히 전달
- `rolling_back` → `rolled_back` 전환 시 자동 정리가 완료됨을 텍스트로 표현 ("정리중" → "실패 (정리 완료)")
- **실시간 전환**: ActionCable + Turbo Streams로 페이지 새로고침 없이 상태 배지 업데이트

---

## 6. 공통 UI 패턴

### 6.1 일회성 시크릿 표시

**적용 대상**: Keycloak Client Secret, PAK, Langfuse SDK Key

```
┌──────────────────────────────────────────────────┐
│  ⚠ 이 값은 한 번만 표시됩니다. 안전하게 보관하세요.  │
│                                                    │
│  Client Secret: ●●●●●●●●●●●●●●●●  [👁 표시] [📋] │
│                                                    │
│  [확인 — 안전하게 저장했습니다]                       │
└──────────────────────────────────────────────────┘
```

- 기본적으로 마스킹 처리 (●●●)
- "표시" 버튼으로 일시적 표시 가능
- 클립보드 복사 버튼 제공
- "확인" 후 다시 조회 불가

### 6.2 위험 액션 확인

**적용 대상**: Organization 삭제, Project 삭제, 롤백

```
┌──────────────────────────────────────────────────┐
│  ⚠ Organization "Acme Corp" 삭제                  │
│                                                    │
│  이 작업은 되돌릴 수 없습니다.                       │
│  하위 3개 Project와 모든 설정이 삭제됩니다.           │
│                                                    │
│  확인하려면 Organization 이름을 입력하세요:           │
│  [                    ]                             │
│                                                    │
│  [취소]  [삭제] (비활성 → 이름 일치 시 활성)          │
└──────────────────────────────────────────────────┘
```

### 6.3 멤버 검색 자동완성

- Stimulus Controller로 구현
- Keycloak Admin API 검색 결과를 드롭다운으로 표시
- 디바운스 300ms 적용
- 검색 결과에 없는 이메일은 직접 입력하여 사전 할당 가능

### 6.4 Breadcrumb

모든 페이지에 현재 위치를 표시하는 Breadcrumb을 제공한다.

```
Console > {Organization} > {Project} > {하위 페이지}
```

### 6.5 빈 상태 (Empty State)

각 목록 페이지에 데이터가 없을 때 안내 메시지를 표시한다.

| 페이지 | 빈 상태 메시지 |
|--------|--------------|
| Org 목록 (일반 사용자) | "소속된 Organization이 없습니다. 관리자에게 문의하세요." |
| Org 목록 (super_admin) | "Organization이 없습니다. 새 Organization을 생성하세요." |
| Project 목록 | "Project가 없습니다. 새 Project를 생성하세요." |
| 멤버 목록 | (항상 최소 1명 — 생성자) |

---

## 7. 접근제어와 UI

역할에 따라 UI 요소의 표시/비표시 및 활성/비활성을 제어한다.

### 7.1 역할별 UI 요소 가시성

| UI 요소 | `super_admin` | Org `admin` | Org `write` | Org `read` |
|---------|:------------:|:-----------:|:-----------:|:----------:|
| "새 Organization" 버튼 | ✓ | — | — | — |
| Organization 삭제 | ✓ | — | — | — |
| "새 Project" 버튼 | ✓ | ✓ | — | — |
| Project 삭제 | ✓ | ✓ | — | — |
| 멤버 관리 (추가/제거) | ✓ | ✓ | — | — |
| 설정 편집 (Config, Auth) | ✓ | ✓ | ✓* | — |
| 설정 조회 | ✓ | ✓ | ✓* | ✓* |
| 프로비저닝 수동 재시도 | ✓ | ✓ | — | — |

> `*` = 해당 Project에 대한 `project_permissions` 레코드가 있는 경우에만

### 7.2 구현 방식

- **서버 사이드**: ERB 템플릿에서 `CurrentUser`의 권한을 확인하여 조건부 렌더링
- **API 사이드**: Controller `before_action`에서 권한 검증 (UI 우회 방지)
- **비활성 표시**: 권한 부족 시 버튼을 숨기거나 `disabled` 처리. 툴팁으로 이유 표시
