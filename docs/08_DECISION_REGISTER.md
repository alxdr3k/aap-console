# AAP Console — Decision Register

작은 ~ 중간 크기의 결정을 가벼운 레코드로 남긴다. 큰 결정은 `docs/adr/`.

## Decisions

### DEC-001: Boilerplate roadmap/status taxonomy 채택

- Date: 2026-04-29
- Status: accepted
- Deciders: Platform TG
- Supersedes: —
- Superseded by: —
- Resolves: —
- Impacts: `docs/04_IMPLEMENTATION_PLAN.md`, `docs/context/current-state.md`, `docs/current/`, `AGENTS.md`

**Context**

`../boilerplate` commit `24851cf`가 `04_IMPLEMENTATION_PLAN.md`를 roadmap / status ledger의 canonical 위치로 확장했고, `24b47f1`이 PR template과 doc freshness workflow에 roadmap/status 및 gate drift checks를 추가했다.

**Decision**

AAP Console은 milestone / track / phase / slice / gate / evidence taxonomy를 채택한다. 구현 상태 inventory는 `docs/04_IMPLEMENTATION_PLAN.md`에 두고, `docs/context/current-state.md`와 `docs/current/*`에는 전체 backlog를 복제하지 않는다. PR template과 doc freshness 예시는 roadmap/status ledger와 acceptance gates drift도 확인하도록 둔다.

**Rationale**

기존 `docs/implementation-status.md`의 완료/부분/미구현 표는 구현 상태와 acceptance gate 상태를 섞고 있었다. 새 taxonomy는 `landed`와 `passing`, `planned`와 `defined`를 분리한다.

**Consequences**

- 긍정: 신규 세션과 리뷰에서 현재 위치, evidence, next work를 한 곳에서 확인할 수 있다.
- 부정: 기존 status matrix 링크를 새 ledger로 정리해야 한다.
- Follow-ups: `DOC-1A.2`, `DOC-1A.3`, `AC-DOC-001`

---

### DEC-002: PRD/HLD canonical path를 numbered docs로 전환

- Date: 2026-04-29
- Status: accepted
- Deciders: Platform TG
- Supersedes: —
- Superseded by: —
- Resolves: —
- Impacts: `docs/01_PRD.md`, `docs/02_HLD.md`, `README.md`, `CLAUDE.md`, `.claude/agents/*`

**Context**

Boilerplate source-of-truth map은 PRD/HLD를 `01_PRD.md`와 `02_HLD.md`로 둔다. AAP Console은 기존에 `PRD.md`와 `HLD.md`를 사용했다.

**Decision**

기존 PRD/HLD 본문을 numbered canonical path로 이동하고, `docs/PRD.md`와 `docs/HLD.md`는 compatibility pointer로 남긴다.

**Rationale**

외부/기존 링크를 즉시 깨뜨리지 않으면서 boilerplate 문서 순서를 채택한다.

**Consequences**

- 긍정: Boilerplate read order와 repo 문서명이 일치한다.
- 부정: 과거 링크가 남아 있을 수 있어 link scan이 필요하다.
- Follow-ups: `AC-DOC-001`
