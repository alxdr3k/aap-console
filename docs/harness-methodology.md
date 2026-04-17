# AI 코딩 하네스 방법론 (Harness Methodology)

> **Version**: 1.0
> **Date**: 2026-04-17
> **Status**: Draft
> **대상 독자**: AAP Console 프로젝트에 AI 코딩 에이전트를 도입·운용할 엔지니어
> **관련 문서**: [AI 활용 프로젝트 설계/구현 노하우](./ai-assisted-project-design-guide.md) · [개발 프로세스](./development-process.md)

---

## 목차

1. [개요 — 하네스란 무엇인가](#1-개요--하네스란-무엇인가)
2. [이론적 배경 — 하네스 엔지니어링의 등장](#2-이론적-배경--하네스-엔지니어링의-등장)
3. [하네스의 6대 구성요소](#3-하네스의-6대-구성요소)
4. [하네스 방법론 — 에이전트 루프와 미들웨어](#4-하네스-방법론--에이전트-루프와-미들웨어)
5. [설계 5대 원칙](#5-설계-5대-원칙)
6. [Claude Code 하네스 레퍼런스 아키텍처](#6-claude-code-하네스-레퍼런스-아키텍처)
7. [AAP Console 프로젝트 하네스 적용 전략](#7-aap-console-프로젝트-하네스-적용-전략)
8. [운영 · 진화 · 평가](#8-운영--진화--평가)
9. [부록 — 용어 및 참고자료](#9-부록--용어-및-참고자료)

---

## 1. 개요 — 하네스란 무엇인가

### 1.1 정의

**하네스(Harness)** 는 LLM을 감싸고 있는 런타임 오케스트레이션 계층 전체를 의미한다. "에이전트"라고 부르는 것은 결국 **모델 + 하네스** 의 합성이며, 하네스는 모델을 제외한 **모든 것** 을 포괄한다.

```
Agent = Model + Harness

Harness = Orchestration Loop
        + Tools (정의, 권한, 호출 규약)
        + Context (어셈블리, 압축, 메모리)
        + Verification (린터, 타입체크, 테스트, 훅)
        + State (세션, 체크포인트, 히스토리)
        + Safety (권한, 가드레일, 샌드박스)
        + Lifecycle (세션 시작·종료, 컴팩션, 하위 에이전트)
```

### 1.2 왜 지금 "하네스"인가

2025년이 "에이전트의 해"였다면, 2026년은 "하네스의 해"로 자리잡고 있다. 모델 품질이 한계수확체감에 접어들면서, **실제 제품 품질을 결정하는 것은 하네스** 임이 드러났기 때문이다. 동일한 기반 모델을 사용하는 두 제품이 완전히 다른 사용자 경험을 내는 이유는 모델이 아니라 하네스 설계에 있다.

> 모델은 지능(intelligence)을 제공하지만, 하네스는 통제(control)를 제공한다.
> 잘 설계된 하네스는 평범한 모델도 신뢰할 수 있게 만들고, 나쁜 하네스는 최고의 모델도 위험하게 만든다.

### 1.3 이 문서의 범위

- 하네스 개념의 이론적 토대와 방법론 정리
- Claude Code 하네스 아키텍처를 레퍼런스로 삼아 실전 설계 원칙 도출
- AAP Console 프로젝트 고유의 제약(Rails 8, TDD, 다수 외부 서비스 연동, 한글 도메인 문서, 정합성 민감도)을 반영한 **프로젝트 맞춤형 하네스 구성** 설계

이 문서는 "마케팅 용어로서의 하네스"가 아닌 **런타임 엔지니어링 대상으로서의 하네스** 에 초점을 맞춘다.

---

## 2. 이론적 배경 — 하네스 엔지니어링의 등장

### 2.1 용어의 발전

| 시기 | 지배적 개념 | 핵심 관심사 |
|------|-------------|-------------|
| ~2023 | Prompt Engineering | 단일 프롬프트의 문구 설계 |
| 2024 | Context Engineering | 컨텍스트 윈도우에 무엇을 얼마나 넣을지 |
| 2025 | Agent Engineering | ReAct 루프, 도구 호출, 멀티턴 계획 |
| 2026~ | **Harness Engineering** | 루프·도구·검증·상태·안전·수명주기의 통합 설계 |

"하네스 엔지니어링"이라는 용어는 2026년 초 OpenAI, Anthropic, Martin Fowler, Red Hat, LangChain 등 복수 진영에서 거의 동시에 정착되었다. OpenAI Codex 팀이 "100만 줄 코드베이스를 인간이 한 줄도 안 쓰고 구축했다"고 발표한 사례가 결정적이었는데, 그들이 실제로 한 일은 **코드를 쓴 게 아니라 AI가 코드를 안정적으로 쓰도록 만드는 하네스를 설계한 것** 이었다.

### 2.2 왜 "하네스"라는 비유인가

하네스는 원래 **말에게 씌우는 마구(馬具)**, 혹은 **추락 방지용 안전벨트** 를 가리킨다. 공통 요소는 다음과 같다.

- 강력하지만 통제되지 않은 대상에게 **방향과 제약** 을 부여한다
- 의도치 않은 이탈을 **물리적으로 막는다**
- 작업자(인간)가 **개입할 수 있는 지점** 을 남긴다

이 은유는 LLM에 정확히 대응된다. 모델 자체는 통제 불가능한 확률적 생성기이며, 하네스는 그 주변에 **결정론적 제약 구조** 를 감싸 예측 가능한 시스템으로 만든다.

### 2.3 "하네스가 제품을 만든다" 명제

- 같은 모델 + 나쁜 하네스 → 데모용 장난감
- 같은 모델 + 좋은 하네스 → 프로덕션 시스템

하네스의 품질은 다음을 통해 드러난다.

- 에이전트가 **같은 실수를 반복하지 않는가** (메모리·규칙)
- 에이전트가 **잘못된 작업을 시작하기 전에 막을 수 있는가** (훅·권한)
- 에이전트의 산출물이 **기계적으로 검증되는가** (린터·테스트·타입체커)
- 에이전트가 **컨텍스트 한계에서 무너지지 않는가** (컴팩션·하위 에이전트)
- **누가 무엇을 승인하는가** 가 명확한가 (권한 모델)

---

## 3. 하네스의 6대 구성요소

현업 합의가 모이고 있는 하네스의 구성요소는 6가지이다. 각각이 어떻게 구현되는지는 다르지만, 어떤 하네스에도 이 6개 축은 반드시 존재한다.

### 3.1 Context Engineering (컨텍스트 엔지니어링)

> "에이전트에게 1,000페이지짜리 매뉴얼이 아니라 **지도** 를 줘라." — OpenAI Codex 팀

**핵심 질문**: *매 스텝마다 모델이 실제로 보는 토큰 집합을, 원하는 결과 확률을 최대화하는 최소 고신호 집합으로 어떻게 좁힐 것인가?*

컨텍스트는 계층화되어 조립된다.

```
[System Prompt]              ← 하네스 자체가 고정
[Tool Definitions]           ← 활성화된 도구 스키마
[Memory Files]               ← CLAUDE.md, MEMORY.md, rules/*.md
[Path-scoped Rules]          ← 열람 중인 파일 경로와 매칭된 규칙
[Skills / Subagent Prompts]  ← 컨텍스트에 따라 on-demand 로드
[Conversation History]       ← 사용자/어시스턴트/도구 결과
[Current User Turn]          ← 현재 사용자 입력
```

관련 기법:
- **하이어라키 메모리(CLAUDE.md hierarchy)**: 프로젝트·유저·로컬·머지정책 4단 스코프
- **경로 스코프 규칙(path-scoped rules)**: 특정 파일을 읽을 때만 로드
- **컴팩션(compaction)**: 컨텍스트 윈도우 포화 시 요약 오프로드
- **하위 에이전트 오프로드(subagent offload)**: 저가치 중간결과를 별도 컨텍스트에서 소화

### 3.2 Tool Orchestration (도구 오케스트레이션)

**핵심 질문**: *모델이 외부 세계와 상호작용하는 모든 경로를, 어떻게 명시하고 어떻게 제한하며 어떻게 검증할 것인가?*

도구는 세 축으로 설계된다.

1. **도구 표면(Surface)** — 내장 도구(`Read`, `Edit`, `Bash` 등), MCP 도구, 사용자 정의 서브에이전트, 스킬
2. **권한(Permissions)** — `allow` / `deny` / `ask` / `defer` 4원 결정. 세션·프로젝트·유저·관리정책 4단 스코프 병합
3. **호출 규약(Convention)** — 입력 스키마, 출력 형식, 타임아웃, 비동기 여부

> 도구 설계의 3대 원칙:
> - **구체적 입력 → 일관된 출력** (파일 경로·심볼명·기존 패턴 명시)
> - **좁은 권한 기본값** (기본은 read-only, 명시적 승격만 쓰기)
> - **기계 검증 가능한 출력** (자연어 대신 구조화된 결과 반환)

### 3.3 Verification Loops (검증 루프)

**핵심 질문**: *모델 출력이 "진짜 맞는지"를 인간이 보지 않아도 기계가 판단하게 하는 방법은?*

검증은 속도와 엄격성 면에서 이중화된다.

| 계층 | 예시 | 차단력 |
|------|------|--------|
| **Fast verifiers** | 문법·린트·타입체크·포매터 | 저렴, 매 편집마다 실행 |
| **Medium verifiers** | 유닛 테스트, 스키마 검증 | 커밋/PR 단위 |
| **Slow verifiers** | 통합/시스템 테스트, 정적 분석, security scan | CI/머지 게이트 |
| **Semantic verifiers** | 별도 LLM 리뷰어(서브에이전트 훅) | 주관적 정합성 검증 |

**TDD 루프는 검증 루프의 자연스러운 구현체다.**

- RED: 실패 테스트가 에이전트 진행을 물리적으로 막는 검증 자산이 된다
- GREEN: 에이전트는 테스트 출력을 직접 관찰하고 수정한다
- REFACTOR: 테스트 통과 유지 조건이 리팩토링의 안전망이 된다

하네스는 검증 루프를 **훅(hook)** 을 통해 에이전트 루프 안으로 끌어들인다. `PostToolUse: Write|Edit` 훅에서 린트·타입체크를 실행하고, 실패 시 `decision: "block"` 을 반환하면 에이전트는 결과를 보고 스스로 수정한다.

### 3.4 State Management (상태 관리)

**핵심 질문**: *세션이 끊어지거나 컨텍스트가 포화되어도 에이전트가 "어제 한 일" 을 기억하려면?*

상태는 네 계층으로 분산된다.

1. **Ephemeral state** — 현재 세션의 대화 히스토리, 도구 호출 결과. 컴팩션 시 일부 손실
2. **Session-persistent state** — 세션 재개(resume) 시 복원되는 트랜스크립트
3. **Project memory** — CLAUDE.md, `.claude/rules/`, `.claude/skills/`. 버전관리됨, 팀 공유
4. **Auto memory** — 에이전트가 스스로 쓰는 `MEMORY.md` 및 토픽 파일. 머신 로컬, 워크트리 단위

설계 레버:
- **컴팩션 생존성(survives-compaction)**: 프로젝트 루트 CLAUDE.md는 `/compact` 후 재주입되지만, 중첩 CLAUDE.md는 재로드 조건이 붙는다
- **체크포인트**: 모든 파일 편집의 자동 스냅샷으로 되돌릴 수 있는 구조
- **워크트리 격리(worktree isolation)**: 하위 에이전트를 임시 git worktree에서 실행하여 본 작업 공간을 오염시키지 않음

### 3.5 Human-in-the-Loop Controls (HITL 통제)

**핵심 질문**: *에이전트가 고위험 결정을 하기 전에 인간을 반드시 끼워 넣을 지점은 어디인가?*

HITL은 "모든 것을 사람이 본다"가 아니라 "중요한 것만 사람에게 에스컬레이션한다"의 기술이다.

| 위험 등급 | 예시 | 기본 정책 |
|-----------|------|-----------|
| **낮음 (자동)** | 파일 읽기, grep, 로컬 테스트 실행 | auto-allow |
| **중간 (plan/설명)** | 파일 생성·수정, 로컬 커맨드 | plan 모드 또는 기본 ask |
| **높음 (승인)** | git push, DB 마이그레이션, 외부 API 쓰기 | 항상 ask, 권한 설정 필요 |
| **매우 높음 (차단)** | `rm -rf`, force push to main, 시크릿 변경 | deny + 훅으로 이중 차단 |

**권한 파이프라인(4단)**:
1. 일반 규칙 평가 (`allow` → `deny` → `ask` 목록)
2. 도구별 커스텀 로직 (예: `Bash(git push:*)` 서브매처)
3. 자동 분류기(훅)의 fast-path 결정
4. 인간 승인 대화상자(대화형) 또는 `defer`(비대화형)

### 3.6 Lifecycle Management (수명주기 관리)

**핵심 질문**: *세션 시작부터 종료까지 에이전트의 동작을 이벤트 기반으로 어떻게 오케스트레이션하는가?*

현대 하네스는 **이벤트 기반 훅 시스템** 을 통해 수명주기를 엔지니어링 대상으로 끌어낸다. Claude Code는 24개 훅 이벤트를 제공하며, 대표적 타이밍은:

- `SessionStart` — 컨텍스트 시드, 환경 변수 주입
- `UserPromptSubmit` — 입력 검증·리라이팅·컨텍스트 주입
- `PreToolUse` / `PermissionRequest` — 도구 호출 차단·수정·자동 승인
- `PostToolUse` / `PostToolUseFailure` — 검증기 실행, 자동 롤백
- `SubagentStart` / `SubagentStop` — 하위 에이전트 경계에서 컨텍스트 교환
- `PreCompact` / `PostCompact` — 컴팩션 직전/직후 상태 지속화
- `Stop` / `SessionEnd` — 최종 체크·요약 저장·알림
- `FileChanged` — 외부 파일 변경 반응형 훅 (예: `.env` 재로드)

훅의 4가지 구현 형태: `command`(쉘), `http`(HTTP POST), `prompt`(단발 LLM 평가), `agent`(서브에이전트 실행).

---

## 4. 하네스 방법론 — 에이전트 루프와 미들웨어

### 4.1 TAO / ReAct 루프

하네스의 심장은 **Thought-Action-Observation(TAO)** 루프, 또는 같은 개념의 다른 이름인 ReAct 루프이다.

```
 ┌─────────────────────────────────────────────┐
 │                                             │
 │   ┌── assemble prompt ──┐                   │
 │   ▼                     │                   │
 │  LLM ──▶ parse output ──┤                   │
 │                         ▼                   │
 │                      tool call?             │
 │                    ┌────┴────┐              │
 │                  yes         no             │
 │                    │          │             │
 │                    ▼          ▼             │
 │              execute tool   done?           │
 │                    │     ┌───┴───┐          │
 │                    ▼    yes      no         │
 │              feed result │        │         │
 │              into context│        │         │
 │                    │     ▼        │         │
 │                    └──▶ stop      │         │
 │                                   │         │
 │                     (continue) ◀──┘         │
 │                                             │
 └─────────────────────────────────────────────┘
```

루프는 다음 중 하나로 종료한다.
- 모델이 도구 호출 없이 최종 응답을 생성 (자연 종료)
- 도구가 `stop` 신호를 반환 (명시적 종료)
- 훅 또는 미들웨어가 루프를 강제 종료 (예산 초과, 안전 위반)
- 최대 턴 수 초과

### 4.2 관찰(observe) → 분석(inspect) → 선택(choose) → 행동(act)

TAO를 더 자세히 쪼개면 4단 사이클이 된다.

| 단계 | 내용 | 하네스 개입점 |
|------|------|---------------|
| **Observe** | 환경·파일·도구 결과 수집 | 어떤 정보를 어디까지 제공할지 결정 |
| **Inspect** | 수집된 정보를 분석·요약 | 서브에이전트 오프로드, 컴팩션 |
| **Choose** | 다음 스텝 선택 (도구·인자·종료) | 권한 파이프라인, 훅 차단/수정 |
| **Act** | 선택된 액션 실행 | 샌드박스, 타임아웃, 실패 복구 |

### 4.3 미들웨어 패턴

에이전트 루프 주변에 **미들웨어** 를 쌓아올리는 것이 현대 하네스의 표준 패턴이다. 웹 프레임워크의 미들웨어와 동일한 개념이다.

대표적 미들웨어:

- **CallBudgetMiddleware** — 턴 수, 토큰 수, 도구 호출 수 상한 강제
- **PolicyMiddleware** — 권한 규칙 평가, 차단/승인 결정
- **AuditMiddleware** — 모든 도구 호출과 응답을 구조화된 로그로 기록
- **ContextBudgetMiddleware** — 컨텍스트 윈도우 임계 도달 시 컴팩션 트리거
- **RetryMiddleware** — 일시적 실패(네트워크·Rate limit)의 자동 재시도
- **VerificationMiddleware** — 편집 후 린트·테스트 자동 실행

Claude Code의 **훅 시스템** 은 사실상 사용자 정의 미들웨어를 꽂을 수 있는 표준 인터페이스이다.

### 4.4 컨텍스트 조립 전략

#### "지도를 줘라" 원칙

모델이 필요한 순간에 필요한 부분만 보도록 설계한다.

- 전체 아키텍처는 **짧은 개요 + 파일 포인터** 로 제공 (예: `@docs/HLD.md`)
- 상세는 **경로 스코프 규칙** 으로 on-demand 로드
- 작업 과정의 중간 탐색 결과는 **서브에이전트 컨텍스트** 에 격리

#### 컨텍스트 예산(Budget) 관리

- **CLAUDE.md ≤ 200줄** — 초과 시 `.claude/rules/` 로 분할
- **MEMORY.md 로딩 캡**: 첫 200줄 또는 25KB 중 먼저 도달하는 쪽
- **토픽 파일**은 on-demand (`debugging.md` 등)
- 매 세션마다 CLAUDE.md 파일들의 **합산 크기** 를 의식하며 운영

#### 컴팩션 생존성

| 항목 | 컴팩션 후 생존 여부 |
|------|---------------------|
| 프로젝트 루트 CLAUDE.md | 자동 재주입 |
| 중첩 CLAUDE.md (하위 디렉토리) | 해당 디렉토리 파일 재열람 시 재로드 |
| 대화 중 사용자가 말로 준 규칙 | **소실 가능** — CLAUDE.md에 승격해야 함 |
| 자동 메모리(MEMORY.md) | 세션마다 재로드 (200줄 또는 25KB) |

### 4.5 하위 에이전트 오프로드 전략

**원칙**: *본 대화에는 "결론"만, "과정"은 하위 에이전트에 격리.*

- 탐색·검색·분석 → `Explore` 또는 커스텀 read-only 에이전트
- 장기 계획 수립 → `Plan`
- 다수 독립 조사 → 병렬 `general-purpose` 호출
- 별도 컨텍스트가 필요한 실험·리팩토링 → `isolation: worktree`

하위 에이전트는 세 가지 절약을 제공한다.
1. **컨텍스트 절약** — 낮은 신호의 중간 결과가 본 대화에 쌓이지 않음
2. **비용 절약** — Haiku 등 저가 모델로 라우팅
3. **권한 절약** — 탐색 에이전트에서 쓰기 도구를 제거하여 위험 제거

---

## 5. 설계 5대 원칙

현업이 수렴하고 있는 하네스 설계 원칙은 다음 다섯 가지이다.

### 5.1 Constrain — 제약하라

에이전트가 **할 수 있는 범위** 를 좁혀라. 범위를 좁힐수록 예측 가능성이 높아진다.

- 기본은 read-only. 쓰기는 명시적 allow에만.
- `Bash(git push:*)` 같은 세밀한 매처 사용
- `disallowedTools` 로 서브에이전트의 쓰기 차단
- 샌드박스·워크트리로 **블래스트 반경(blast radius)** 제한

### 5.2 Inform — 알려주라

에이전트가 **해야 하는 일** 을 명확히 전달하라.

- CLAUDE.md에 프로젝트 상수(빌드·테스트·네이밍) 기록
- `.claude/rules/` 로 경로 스코프별 규칙 제공
- 도구 스키마에 **입력 제약 명시** (파일 경로·심볼명 요구)
- 스킬로 반복 워크플로우 패키징

### 5.3 Verify — 검증하라

출력을 **기계적으로 판정** 할 수 있게 하라.

- 린터·타입체커·테스트를 훅으로 자동 실행
- 실패를 모델에게 **그대로 반환** — 모델은 이를 보고 수정
- 의미 검증이 필요하면 서브에이전트 리뷰어 훅

### 5.4 Correct — 교정하라

에이전트가 실수했을 때 **복구 가능** 하게 하라.

- 체크포인트로 모든 편집 되돌리기
- 워크트리 격리로 본 트리 오염 차단
- 실패한 도구 호출을 **다시 맥락에 노출** 하여 스스로 수정

### 5.5 Escalate — 에스컬레이션하라

**고위험 결정은 인간에게** 돌려라.

- 권한 4등급 분류 (5.1의 HITL 표)
- push·배포·시크릿 변경 등은 `ask` 고정
- `Stop` 훅으로 "머지/푸시 전 수동 승인" 구현

---

## 6. Claude Code 하네스 레퍼런스 아키텍처

### 6.1 구성 파일 계층

```
[Managed Policy]   ─── 조직 정책 (IT/DevOps가 MDM 배포)
       │
       ▼
[User Settings]    ─── ~/.claude/settings.json, ~/.claude/CLAUDE.md,
                       ~/.claude/agents/*.md, ~/.claude/rules/*.md
       │
       ▼
[Project Settings] ─── .claude/settings.json, ./CLAUDE.md 또는
                       .claude/CLAUDE.md, .claude/agents/*.md,
                       .claude/rules/*.md, .claude/skills/*.md
       │
       ▼
[Local Settings]   ─── .claude/settings.local.json, CLAUDE.local.md
                       (gitignore, 개인용)
```

상위 계층은 **병합(merge)** 되며, 충돌 시 더 구체적인(local에 가까운) 쪽이 우선이다.

### 6.2 메모리 모델

| 메모리 유형 | 소유자 | 위치 | 라이프사이클 |
|-------------|--------|------|--------------|
| **CLAUDE.md** | 사람 | 프로젝트/유저/정책 | 수동 작성, 버전관리 |
| **Path-scoped rules** | 사람 | `.claude/rules/**.md` | YAML `paths:` 조건 로딩 |
| **Auto memory** | 에이전트 | `~/.claude/projects/<proj>/memory/` | 에이전트가 자율 기록 |
| **Subagent memory** | 하위 에이전트 | `memory:` 필드 스코프 | 하위 에이전트 간 공유/격리 |
| **Skills** | 사람 | `.claude/skills/**.md` | 요청 시점에만 로드 |

### 6.3 훅 이벤트 맵 (요약)

| 타이밍 | 이벤트 | 주 용도 |
|--------|--------|---------|
| Once per session | `SessionStart`, `SessionEnd` | 컨텍스트 시드, 요약 저장 |
| Once per turn | `UserPromptSubmit`, `Stop`, `StopFailure` | 입력 검증, 최종 게이트 |
| Per tool call | `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied` | 도구별 제약·검증 |
| Async/reactive | `FileChanged`, `CwdChanged`, `ConfigChange`, `InstructionsLoaded`, `Notification`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact` | 환경 변화 반응 |
| Agent | `SubagentStart`, `SubagentStop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted` | 하위 에이전트 경계 |
| MCP | `Elicitation`, `ElicitationResult` | MCP 도구 상호작용 |

훅의 3가지 결정: `allow` / `deny` / `ask` / `defer` 중 반환. `exit 2` 는 차단 에러(stderr를 모델에게 전달).

### 6.4 서브에이전트 프런트매터

```yaml
---
name: <identifier>           # 필수, lowercase + hyphen
description: <when-to-use>   # 필수, Claude가 언제 위임할지 결정
tools: Read, Grep, Glob      # 허용 도구 (생략 시 전체 상속)
disallowedTools: Write, Edit # 거부 도구
model: sonnet|opus|haiku|inherit
permissionMode: default|acceptEdits|auto|dontAsk|bypassPermissions|plan
maxTurns: 20
skills: [skill-a, skill-b]
mcpServers: [github]
hooks: { ... }               # 하위 에이전트 한정 훅
memory: user|project|local
background: false
effort: low|medium|high|xhigh|max
isolation: worktree          # 임시 git worktree에서 실행
color: red|blue|...
---

<system prompt in markdown>
```

### 6.5 권한 규칙 문법

```
Bash                         # 모든 Bash 호출
Bash(npm test)               # 정확히 매치
Bash(npm test:*)             # npm test로 시작하는 모든 호출
Bash(git push:*)             # git push 계열 차단에 사용
Edit(**/*.rb)                # 특정 glob 파일만 편집 허용
mcp__github__*               # 특정 MCP 서버 도구
```

규칙은 `permissions.allow` / `permissions.deny` / `permissions.ask` 배열에 넣는다. 병합은 **deny 우선** 이다.

---

## 7. AAP Console 프로젝트 하네스 적용 전략

### 7.1 이 프로젝트의 하네스 요구사항

AAP Console은 다른 일반 프로젝트와 다른 제약을 가진다. 하네스 설계는 이 제약을 정면으로 반영해야 한다.

| 프로젝트 특성 | 하네스 요구사항 |
|---------------|------------------|
| **문서가 먼저, 코드는 이제부터** | 현재 단계에선 **문서 정합성 검증** 이 핵심 검증 루프 |
| **한글 문서 + 영문 커밋 메시지 혼재** | AI가 반복 위반 → CLAUDE.md + 훅에 명시 고정 |
| **TDD 필수 (RSpec + WebMock)** | GREEN 단계 테스트 실행 훅 필수. 테스트 없는 구현 차단 |
| **다수 외부 서비스 연동 (Keycloak, Langfuse, LiteLLM, Config Server)** | 외부 서비스에 대한 mock 강제. 실제 API 호출 차단 |
| **Rails 8 + Hotwire + SolidQueue + SQLite** | Rails 관례 전용 서브에이전트·규칙 필요 |
| **Secret Zero-Store 원칙** | 시크릿 값을 실수로 파일에 쓰지 않도록 훅으로 차단 |
| **All-or-Nothing Provisioning** | 롤백 테스트 강제. 부분 성공 상태 금지 |
| **PRD ↔ HLD ↔ ADR 교차 정합성** | 다수 문서 간 불일치 검증 서브에이전트 필요 |
| **대규모 한글 도메인 문서 (HLD 2000줄+, PRD 1500줄+)** | 경로 스코프 규칙으로 on-demand 로드 |

### 7.2 단계별 하네스 진화 계획

프로젝트는 문서 단계 → 초기 코드 → 성숙한 코드로 진화한다. 하네스도 이 단계를 반영하여 진화해야 한다.

| 단계 | 하네스 집중 | 주 훅 | 주 서브에이전트 |
|------|-------------|-------|-----------------|
| **S1: 문서 정합성** (현재) | 문서 교차 검증, 대화 맥락 유출 방지, 커밋 영문화 | `PostToolUse(Edit)` 문서 리뷰, `Stop` 커밋 메시지 검사 | `docs-consistency-checker`, `docs-declutter` |
| **S2: 초기 Rails 스캐폴딩** | Rails 관례, 외부 서비스 mock 강제, 시크릿 누출 방지 | `PreToolUse(Write)` 시크릿 스캔, `PostToolUse(Write|Edit)` rubocop | `rails-scaffolder`, `external-api-mocker` |
| **S3: 기능 구현 (TDD)** | RED→GREEN→REFACTOR 강제, 테스트 커버리지 유지 | `PostToolUse(Write|Edit)` RSpec 실행, `Stop` 커버리지 체크 | `rspec-runner`, `tdd-red-writer`, `tdd-green-implementer` |
| **S4: 외부 연동 실구현** | API 스펙 정합성, 롤백 플로우 검증 | `PostToolUse(Edit service files)` 스펙 체크 | `provisioner-reviewer`, `rollback-tester` |
| **S5: 성숙기** | 회귀 방지, 성능·보안 리뷰 | PR 리뷰 서브에이전트 훅 | `security-reviewer`, `pr-reviewer` |

현재 구성은 **S1을 충실히, S2~S3의 발판을 마련** 하는 수준으로 설계한다. S4~S5는 해당 시점에 추가한다.

### 7.3 구체적 하네스 컴포넌트 설계

#### 7.3.1 CLAUDE.md (프로젝트 헌장, ≤200줄)

담길 내용:
- 프로젝트 정체성 한 문단
- 참조 문서 목록 (`@docs/PRD.md` 등)
- 커밋 메시지 언어 = **영어** (반복 위반 규칙)
- 문서 언어 = **한글** (본문), 코드 주석 = **영문**
- 기본 툴링 명령 (`bundle exec rspec`, `bundle exec rubocop`)
- 외부 API 호출 원칙: **실제 호출 금지, WebMock 필수**
- 시크릿 금지 목록 (환경변수명, 파일 패턴)
- TDD 사이클 요약 (RED→GREEN→REFACTOR)
- 하네스 문서 링크 (`@docs/harness-methodology.md`)

#### 7.3.2 `.claude/rules/` (경로 스코프 규칙)

| 파일 | 경로 스코프 | 목적 |
|------|-------------|------|
| `docs-style.md` | `docs/**/*.md` | 문서 형식, 한글 사용, 다이어그램 규칙 |
| `rails-conventions.md` | `app/**/*.rb`, `spec/**/*.rb` | Rails 네이밍, Service Object 패턴 |
| `external-api-clients.md` | `app/services/**/*_client.rb`, `spec/services/**/*_client_spec.rb` | 외부 API 클라이언트 규칙, WebMock 사용 강제 |
| `jobs.md` | `app/jobs/**/*.rb` | SolidQueue Job 패턴, idempotency |
| `security.md` | 없음 (전역) | Secret Zero-Store, SQL injection, XSS 방지 |

#### 7.3.3 서브에이전트 (S1 단계 우선)

| 이름 | 주 용도 | 모델 | 도구 |
|------|---------|------|------|
| `docs-consistency-checker` | PRD/HLD/ADR 교차 정합성 검증 | sonnet | Read, Grep, Glob |
| `docs-declutter` | 대화 맥락 유출·중복·비대화 탐지 | haiku | Read, Grep, Glob |
| `commit-lint` | 영문 커밋 메시지 검사·제안 | haiku | Read, Bash(git log *), Bash(git diff *) |
| `rails-architect` (S2 대비) | Rails 8 + Hotwire 패턴 자문 | sonnet | Read, Grep, Glob |

#### 7.3.4 훅 설계

**SessionStart**
- 현재 브랜치와 작업 대상 안내
- `git status` 요약을 additionalContext로 주입

**UserPromptSubmit**
- 프롬프트에 "커밋해" / "commit" 등 커밋 지시가 포함된 경우 경고 주입 ("커밋 전에 테스트 통과 확인 필요")

**PreToolUse**
- `Bash(git push:*)` → 차단(ask). 브랜치 보호
- `Bash(rm -rf *)` → 차단(deny). 파괴적 명령
- `Write` / `Edit` 에 시크릿 패턴(`sk-`, `BEGIN PRIVATE KEY`, `.env` 평문) 포함 시 차단
- `Bash(bundle exec rspec*)` → 자동 allow

**PostToolUse**
- `Edit(docs/**/*.md)` → 문서 정합성 서브에이전트 훅 (비차단, 조언 제공)
- `Write|Edit(spec/**/*.rb)` → RSpec 구문 유효성 체크 (추후 S3)
- `Write|Edit(app/**/*.rb)` → rubocop 실행 (추후 S2)

**Stop**
- 커밋 메시지가 한글로 작성되었을 경우 경고
- TDD 사이클 중인데 테스트 실행 이력이 없으면 경고 (S3)

**FileChanged**
- `.env` / `.envrc` 변경 감지 시 경고 (시크릿 커밋 방지 리마인더)

#### 7.3.5 권한 기본값

**Allow (자동 승인)**:
- `Read`, `Grep`, `Glob`
- `Bash(bundle exec rspec*)`, `Bash(bundle exec rubocop*)`
- `Bash(git status)`, `Bash(git log*)`, `Bash(git diff*)`, `Bash(git branch*)`
- `Bash(bin/rails test*)`, `Bash(bin/rails db:migrate:status)`

**Ask (사용자 승인 필요)**:
- `Write`, `Edit`, `NotebookEdit`
- `Bash(git commit*)`, `Bash(git add*)`, `Bash(git stash*)`
- `Bash(bin/rails db:migrate)`
- `Bash(bundle install*)`, `Bash(bundle update*)`

**Deny (절대 차단)**:
- `Bash(git push --force*)`, `Bash(git push -f*)` (main 강제 푸시)
- `Bash(rm -rf*)`, `Bash(sudo*)`
- `Bash(curl *keycloak*)`, `Bash(curl *langfuse*)` — 실제 외부 API 호출 금지
- `Bash(gh pr merge*)` — 머지는 사람이

### 7.4 S3 TDD 강제 전략 (향후)

코드 단계에서 **TDD 위반을 하네스 레벨에서 차단** 하기 위한 설계:

1. `app/**/*.rb` 에 대한 `Write` 를 실행하려 할 때, 해당 구현을 테스트하는 `spec/**/*_spec.rb` 파일 존재 여부 확인
2. 존재하지 않으면 `PreToolUse` 훅이 block → 모델은 "테스트 먼저 작성해야 함" 에러 수신
3. `PostToolUse(Write|Edit spec/**/*.rb)` → 해당 spec 실행, 실패해야 정상 (RED 단계 확인)
4. `PostToolUse(Write|Edit app/**/*.rb)` → 관련 spec 실행, 통과해야 정상 (GREEN)

이 구조는 문서 단계에는 과도하므로 S3 진입 시 활성화한다.

### 7.5 외부 API 실호출 차단

`development-process.md` 2.3절이 정의하는 "외부 API 항상 Mock" 원칙을 하네스가 물리적으로 강제한다.

- `Bash(curl*)`, `Bash(wget*)` 중 외부 서비스 호스트 패턴을 포함하는 호출은 `permissions.deny`
- `Write|Edit` 시 외부 서비스 실제 엔드포인트 URL 하드코딩을 탐지하면 경고
- `spec/**/*` 이외에서 `WebMock.disable!` 등 mock 해제 구문 탐지 시 차단

### 7.6 Secret Zero-Store 강제

- `Write|Edit` 훅에서 시크릿 패턴 탐지 (정규식):
  - `sk-[a-zA-Z0-9]{20,}` (API key 패턴)
  - `-----BEGIN (RSA |EC )?PRIVATE KEY-----`
  - `(password|secret|token)\s*[:=]\s*["'][^"']{8,}["']`
- 탐지 시 `decision: block` + 이유를 모델에 전달하여 환경변수화·config server 사용 유도
- 예외: 스펙 파일의 dummy token (`spec/support/` 이하)

---

## 8. 운영 · 진화 · 평가

### 8.1 하네스 성숙도 모델

| 레벨 | 특징 | 신호 |
|------|------|------|
| L0 | 기본 Claude Code만 사용, 맨 손 | 같은 실수 반복, 검증 없음 |
| L1 | CLAUDE.md 작성 | 프로젝트 관례가 1회 입력으로 반영됨 |
| L2 | 권한·hooks 기초 구성 | 위험 명령 차단, 자동 승인 허용 |
| L3 | 서브에이전트·rules 활용 | 컨텍스트 효율 상승, 전문화 |
| L4 | TDD/린트 자동화 루프 | 회귀 거의 없음, 사람 개입 최소 |
| L5 | 메트릭 기반 개선 사이클 | 하네스 자체가 버전 관리되고 평가됨 |

본 프로젝트는 **L2~L3** 부터 시작하여 코드 단계 진입 시 L4로 승급한다.

### 8.2 하네스 자체의 변경 관리

- `docs/harness-methodology.md` (이 문서) 는 **방법론** 문서로 유지
- `.claude/**` 는 **구현** 이며, 커밋 메시지 스코프를 `harness:` 로 통일
- 훅 스크립트는 `.claude/hooks/` 에 쉘로 작성하고 실행 권한 부여
- 변경 시 동기화: 이 문서의 7.3절과 `.claude/settings.json` 이 일치해야 함

### 8.3 평가 지표(제안)

- **Precision**: 훅에 의해 차단된 작업 중 "정말 차단돼야 했던" 비율
- **Recall**: 실패한 작업(실수·회귀) 중 "하네스가 사전에 잡을 수 있었던" 비율
- **Friction**: 사용자가 하루에 `ask` 에 응답한 횟수
- **Context efficiency**: CLAUDE.md·rules 총량 대비 성공 턴 비율

이 지표는 자동 측정이 어려우므로 주간 회고에서 주관적으로 평가한다.

### 8.4 안티패턴 — 하네스에서 피해야 할 것

- **하네스가 사람 대신 판단을 독점하는 구조** — 고위험은 반드시 HITL
- **거대 CLAUDE.md** — 200줄 초과 시 rules로 분할
- **훅 과다** — 매 도구 호출마다 3초씩 기다리면 전체 느려짐. 훅은 `async: true` 또는 빠른 스크립트로
- **정책을 코드 대신 프롬프트로만 강제** — CLAUDE.md는 enforced가 아니며, 실제 차단은 permissions/hooks
- **서브에이전트 중첩 남용** — 하위 에이전트는 하위 에이전트를 호출할 수 없다. 복잡도가 늘면 agent teams로
- **로컬 전용 시크릿을 .claude/settings.json에 커밋** — 로컬 전용은 `.claude/settings.local.json` (gitignore)

---

## 9. 부록 — 용어 및 참고자료

### 9.1 용어

| 용어 | 정의 |
|------|------|
| **Harness** | LLM을 감싼 런타임 오케스트레이션 계층 전체 |
| **Agent Loop / TAO / ReAct** | Thought-Action-Observation 반복 구조 |
| **Context Engineering** | 모델 입력 컨텍스트 조립·압축 설계 |
| **Hook** | 수명주기 이벤트에 바인딩되는 쉘/HTTP/프롬프트/에이전트 콜백 |
| **Subagent** | 자체 컨텍스트와 권한을 가진 위임형 AI |
| **Skill** | 요청 시점에 로드되는 반복 워크플로우 패키지 |
| **Rules** | 경로 스코프로 조건부 로드되는 지침 조각 |
| **CLAUDE.md** | 프로젝트/유저/정책 스코프의 고정 지침 파일 |
| **Auto memory** | 에이전트가 스스로 기록하는 `MEMORY.md` 집합 |
| **Compaction** | 컨텍스트 포화 시 요약 오프로드 |
| **Worktree isolation** | 서브에이전트를 임시 git worktree에서 실행하여 본 트리 보호 |
| **Permission pipeline** | allow/deny/ask/defer 결정 4단 파이프라인 |
| **HITL** | Human-in-the-loop — 인간 개입 지점 |
| **Blast radius** | 실패 시 영향 범위 |

### 9.2 참고자료 (2026년 기준)

- Martin Fowler — *Harness engineering for coding agent users*
- OpenAI — *Harness engineering: leveraging Codex in an agent-first world*
- Anthropic (Claude Code) — *How Claude remembers your project*, *Create custom subagents*, *Hooks*
- LangChain — *The Anatomy of an Agent Harness*
- HumanLayer — *Skill Issue: Harness Engineering for Coding Agents*
- Red Hat — *Harness engineering: Structured workflows for AI-assisted development*
- Simon Willison — TDD 루프 기반 에이전트 패턴

### 9.3 이 프로젝트의 관련 문서

- [PRD](./PRD.md) — 제품 요구사항
- [HLD](./HLD.md) — High-Level Design
- [ADR 001~006](./adr-001-provisioning-orchestration.md) — 아키텍처 의사결정
- [개발 프로세스](./development-process.md) — TDD 워크플로우
- [AI 활용 설계 노하우](./ai-assisted-project-design-guide.md) — 프롬프팅·대화 패턴


