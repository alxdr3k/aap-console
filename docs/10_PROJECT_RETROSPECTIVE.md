# 10 Project Retrospective

프로젝트 중/후의 회고. Milestone마다 갱신하고, 종료 시 외부 knowledge base
승격을 위한 extraction packet을 준비한다.

회고는 "무엇을 배웠는가"를 기록하고, extraction packet은 "그 중 무엇을 외부
knowledge base로 승격할 후보인가"를 기록한다. 두 단계를 분리한다.

## Cadence

- Milestone 회고 (milestone 종료 시): 아래 사본 추가. lesson 후보를 식별만 하고 자동 승격은 하지 않는다.
- Final 회고 (프로젝트 종료 시): extraction packet 준비
  ([`templates/EXTRACTION_TEMPLATE.md`](templates/EXTRACTION_TEMPLATE.md)).

승격 자체는 외부 knowledge base의 자체 review / ingestion 프로세스를 통해
이뤄진다. 회고에서 candidate로 표시했다고 해서 자동 승격되는 것은 아니다.

## Milestone Retrospective — <Milestone name>

- Date:
- Attendees:

### What went well

- ...

### What didn't

- ...

### What confused us

- ...

### Lesson candidates

| Candidate | 간단 설명 | Cross-project 가치? | Promote later? |
|---|---|---|---|
|  |  | yes / no | yes / no / later |

> Milestone 회고는 lesson candidate를 식별만 한다. 외부 knowledge base로의 정식
> 승격은 Final Retrospective의 extraction packet에서 일괄 처리한다.
>
> 즉시 승격이 필요한 reusable cross-project 지식 또는 major decision
> candidate가 있을 때만 milestone 시점에서
> [`templates/EXTRACTION_TEMPLATE.md`](templates/EXTRACTION_TEMPLATE.md)을
> 적용한다.

### Actions

| Action | Owner | Due |
|---|---|---|
|  |  |  |

---

## Final Retrospective

프로젝트 종료 시 작성.

### Outcomes vs Goals

- PRD 목표 대비 달성도:
- 주요 성공/실패:

### Durable Lessons

이 프로젝트에서 지속 가치가 있다고 판단된 교훈. 각 항목은 한 줄 제목과 한 줄
요약으로 짧게 유지한다. 정식 외부 knowledge base 승격 후보 정의는 아래
extraction packet에서 구조적으로 다룬다.

| Lesson 제목 | 한 줄 요약 | Extraction packet 연결 (EX-###) |
|---|---|---|

### Extraction packet

프로젝트 종료 시
[`templates/EXTRACTION_TEMPLATE.md`](templates/EXTRACTION_TEMPLATE.md)을 채워
외부 knowledge base 승격 범위를 명시한다. Template이 canonical이며, 본 문서는
template 사본을 인라인으로 복제하지 않는다.

Extraction packet의 핵심 약속:

- candidate vs promoted를 구분한다 — 회고는 candidate만 만든다. 승격은 외부 knowledge base가 결정한다.
- `Do not promote`는 필수 — `None — reviewed` 라고라도 명시한다. 빈 채로 두지 않는다.
- raw Q&A / draft / 임시 비교표는 그대로 승격하지 않는다. 필요하면 distill 후 lesson 또는 resource candidate로.
- source anchor (repo / path / commit / PR / ADR / DEC / Q) 를 가능한 한 채운다. 알 수 없으면 `anchor missing` 으로 명시한다.
- `drop` 은 "외부 knowledge base에 승격하지 않음" 을 의미한다. 프로젝트 repo, transcript, artifact store, git history 의 원본 삭제를 의미하지 않는다.

`Created / Modified / Promoted / Dropped` 보고 포맷도 template에 따른다.

### Numbers

- Elapsed time:
- Scope changes:
- Incidents: Runbook 참고.
