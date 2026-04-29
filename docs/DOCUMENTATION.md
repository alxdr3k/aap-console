# AAP Console — Documentation Policy

## Purpose

이 docs tree는 product/architecture decision, roadmap/status tracking, 구현 단계의
current state를 분리한다.

## Source-of-truth Hierarchy

1. 구현이 존재하는 영역은 code, tests, migrations, generated schema가 authoritative source다.
2. Roadmap / status ledger는 `docs/04_IMPLEMENTATION_PLAN.md`가 소유한다.
3. 압축된 현재 상태는 `docs/context/`와 `docs/current/`의 thin docs가 제공한다.
4. Product/spec/runbook/acceptance 문서는 `01`-`10` numbered docs에 둔다.
5. ADR과 Decision Register는 결정 history를 보존한다.
6. Discovery와 archive 문서는 authority가 아니다.

## Rules

- Current docs는 빠른 orientation용이며 full history가 아니다.
- `docs/04_IMPLEMENTATION_PLAN.md`는 milestone, track, phase, slice, gate, status, evidence, next work의 canonical 위치다.
- `docs/context/current-state.md`는 active roadmap position만 요약한다.
- `docs/current/`는 구현된 상태의 navigation layer이며 future roadmap inventory를 소유하지 않는다.
- Accepted ADR은 새 behavior에 맞춰 수정하지 않는다. 필요한 경우 superseding ADR을 만든다.
- Discovery note와 archived design note는 current implementation authority가 아니다.
- 긴 historical note를 구현 변경마다 갱신하지 않는다.
- 넓은 rewrite보다 작고 targeted한 doc patch를 선호한다.
- Schema/API/enum은 generator가 있으면 generated docs를 선호한다.
- Code가 behavior/schema/runtime을 바꾸면 같은 PR에서 관련 thin current doc을 갱신한다.

## What To Update When

| Change type | Required doc action |
|---|---|
| Product scope changes | `docs/01_PRD.md` 갱신; 필요하면 DEC/ADR 추가 |
| Architecture changes | `docs/02_HLD.md` 갱신; ADR 추가 또는 supersede |
| Roadmap taxonomy or slice status changes | `docs/04_IMPLEMENTATION_PLAN.md` 갱신 |
| Active milestone / track / phase / slice changes | `docs/context/current-state.md` 갱신 |
| Gate definition or acceptance status changes | `docs/06_ACCEPTANCE_TESTS.md` 갱신 |
| Runtime behavior changes | `docs/current/RUNTIME.md` 갱신 |
| Module/file layout changes | `docs/current/CODE_MAP.md` 갱신 |
| DB/schema/data model changes | `docs/current/DATA_MODEL.md` 갱신 |
| Test/lint/typecheck/eval command changes | `docs/current/TESTING.md` 갱신 |
| Operational/env/deployment changes | `docs/current/OPERATIONS.md` 또는 `docs/05_RUNBOOK.md` 갱신 |
| New open question | `docs/07_QUESTIONS_REGISTER.md`에 Q 추가 |
| Lightweight accepted decision | `docs/08_DECISION_REGISTER.md`에 DEC 추가 |
| Major accepted decision | `docs/adr/` 아래 ADR 추가 |
| Cross-document impact | `docs/09_TRACEABILITY_MATRIX.md` 갱신 |
| Historical exploration | `docs/discovery/` 또는 `docs/design/archive/`에 둠 |
| Reusable lesson discovered | Retrospective에 candidate 추가; `docs/templates/EXTRACTION_TEMPLATE.md`로 외부 knowledge-base promotion 준비 |
| Milestone completion | `docs/04_IMPLEMENTATION_PLAN.md`, `docs/context/current-state.md`, `docs/09_TRACEABILITY_MATRIX.md`, `docs/10_PROJECT_RETROSPECTIVE.md` 갱신 |
| Major project completion | Final retrospective와 extraction packet 준비 |
| Raw Q&A / discovery produces reusable knowledge | Raw transcript를 promote하지 말고 distill한다 |
| Rejected / stale recommendation identified | Extraction packet의 `Do not promote`에 rationale과 함께 추가 |

## Roadmap / Status Migration

기존 프로젝트에 boilerplate를 적용할 때 흩어진 roadmap language를
`docs/04_IMPLEMENTATION_PLAN.md` taxonomy로 정규화한다.

1. Product / user-facing gate를 Milestone으로 mapping한다.
2. Technical stream을 Track으로 mapping한다.
3. Track 내부의 순서 있는 구현 단계를 Phase로 mapping한다.
4. Commit/PR 크기의 구현 단위를 Slice로 mapping한다.
5. Acceptance criteria, automated test, staging check, manual verification을 Gate로 mapping한다.
6. 모호한 `done` / `pending` 상태를 implementation status와 gate status로 분리한다.
7. Canonical inventory를 `04_IMPLEMENTATION_PLAN.md`로 옮긴 뒤 current-state, runtime, architecture, agent instruction의 중복 inventory를 줄인다.
8. Source anchor(path, commit, PR, ADR, DEC, Q, AC, TEST, issue ID)를 보존한다. 모르면 `anchor missing`이라고 쓴다.

## Enforcement Mechanisms

아래는 convention이며, 각 프로젝트가 자기 stack에 맞춰 wiring한다.

### Doc Freshness CI

PR 또는 push diff를 base와 비교해 code path 변경이 roadmap/status, acceptance
gate, thin current-state doc, generated doc, ADR 중 필요한 문서 갱신 없이 들어온
경우 soft warning을 남기는 GitHub Action이다. Merge gate가 아니라 drift를 빠르게
드러내기 위한 장치다.

Skeleton workflow는 `.github/workflows/doc-freshness.yml.example`에 있다. 실제로
켜려면 `.github/workflows/doc-freshness.yml`로 복사하고 source/migration pattern을
프로젝트에 맞게 조정한다.

Untrusted GitHub event input은 shell `run:`에 직접 inline하지 말고 `env:`를 통해서만 전달한다.

### SHA Freshness Headers

빠르게 바뀌는 logic을 설명하는 thin current-state doc은 3-5번째 줄에 다음 header를 둘 수 있다.

```text
> Last verified against code: <commit-SHA> (<YYYY-MM-DD>)
```

Rule: 이 header가 설명하는 code behavior를 바꾸는 commit은 같은 PR에서 SHA와 date도
갱신해야 한다. Stale header는 cosmetic issue가 아니라 doc gap이다.

모든 thin doc에 넣지 않는다. 실제로 빠르게 변하는 logic을 추적하는 문서에만 넣는다.

### Generated Docs

`docs/generated/`는 code, schema, migrations, config에서 파생된 output을 둔다.
각 generated file은 project에 commit된 generator script와 짝을 이룬다.

규칙:

- Generated doc은 손으로 수정하지 않는다.
- Source change와 같은 PR에서 generator를 실행하고 output을 commit한다.
- PR template에 이를 확인하는 checkbox를 둔다.
- Active generator는 `docs/generated/README.md`에 기록한다.
