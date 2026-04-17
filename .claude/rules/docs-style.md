---
description: Style and scope rules for docs/*.md prose.
paths:
  - docs/**/*.md
---

# Documentation Style Rules

Applies whenever you edit any markdown under `docs/`.

## Language

- **Prose: Korean.** This is the domain language.
- **Identifiers, URLs, filenames, Ruby/Rails symbols, environment variables, commit-message examples in docs: English.**
- Do not translate technical terms that have no standard Korean equivalent. Keep `Provisioner`, `Worker`, `Turbo Streams` as-is.

## Version and date metadata

- Every PRD/HLD/ADR/UI-spec starts with `> Version` and `> Date`. Bump both when editing material content.
- Use ISO dates (`YYYY-MM-DD`).

## Scope discipline (critical)

- **PRD** describes *what* the system does. It may reference Config Server's API surface but must not describe Config Server internals (encryption algorithm, storage layout, git commit flow).
- **HLD** describes *how* Console is structured. It must not dictate UI copy (leave that to `ui-spec.md`) and must not duplicate PRD business rules.
- **ADRs** stay focused on a single decision with alternatives and rationale. Do not expand ADRs into mini-HLDs.
- **UI Spec** describes UI patterns and copy. It must not define data schemas or API contracts.

## Anti-patterns (remove on sight)

- Conversation artifacts: "이전에 논의한 바와 같이", "위에서 설명한 것처럼", "앞서 언급했듯이".
- Marketing tone: "최첨단", "혁신적인", "강력한" without justification.
- Vague futures: "추후 고려", "필요 시 추가" without a concrete trigger.
- Duplicated sections across documents. Link to the authoritative one instead.

## Diagrams

- ASCII diagrams must have closed boxes (no dangling pipe characters) and arrows that do not cross box borders.
- Mermaid diagrams are allowed for flows that would be ambiguous in ASCII. Prefer ASCII otherwise.
- Validate box alignment: every opening `┌` must have a matching `┐`, every `│` column must align.

## Cross-document consistency

After any substantive edit, run the `docs-consistency-checker` subagent to verify:
- Terminology matches the PRD glossary (§2).
- FR numbers referenced in HLD/ADRs still exist in PRD.
- Table-of-contents entries still resolve to real section titles.

## Editing etiquette

- When removing or renaming a section, update all in-document anchors and cross-document references.
- Do not add TODO markers to documents — decisions are either made (recorded) or deferred (noted in a dedicated "Open Questions" section).
