# Current Implementation Docs

이 디렉터리는 구현된 현재 상태를 빠르게 찾기 위한 얇은 navigation 문서다.

이 문서들은 code, tests, migrations, generated schema를 대체하지 않는다.

또한 roadmap / status inventory를 소유하지 않는다. milestone, track, phase,
slice, gate, evidence, next-work tracking은
[`../04_IMPLEMENTATION_PLAN.md`](../04_IMPLEMENTATION_PLAN.md)를 사용한다.

| File | Purpose |
|---|---|
| `CODE_MAP.md` | 코드 위치와 책임 |
| `DATA_MODEL.md` | 현재 schema/model map |
| `RUNTIME.md` | 실제 request/job/event flow |
| `TESTING.md` | 검증 명령과 CI check mapping |
| `OPERATIONS.md` | local run/env/debug/deploy/CD note |

CI/CD design guidance lives in [`../11_CI_CD.md`](../11_CI_CD.md).
