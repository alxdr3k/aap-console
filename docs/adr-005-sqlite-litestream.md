# ADR-005: 데이터베이스 — SQLite + Litestream vs PostgreSQL

> **상태**: Accepted
> **일자**: 2026-03-12
> **결정자**: Platform TG

## 컨텍스트

Console은 Organization/Project 메타데이터, 프로비저닝 상태, 설정 스냅샷, 감사 로그를 저장할 데이터베이스가 필요하다. 내부 관리 콘솔로서 사용자 수는 소수(팀 관리자/플랫폼 관리자)이며, 쓰기 빈도가 낮다.

Rails 8은 SQLite를 1급 프로덕션 데이터베이스로 지원하며, SolidQueue/SolidCable 등 Solid 스택이 SQLite 위에서 동작한다.

## 선택지

### 1. PostgreSQL — 미채택

전통적인 프로덕션 데이터베이스 서버.

**장점**:
- 동시 쓰기 성능 우수. 수평 확장 가능
- 프로덕션 데이터베이스로 검증된 성숙도
- 복제, 페일오버 등 HA 구성 용이

**단점**:
- **별도 서버 운영 필요**: DB 서버/PaaS 인프라 추가. 운영 복잡도 증가
- **과도한 스펙**: 내부 관리 콘솔의 낮은 쓰기 빈도에 PostgreSQL은 과도
- **Redis 추가 필요**: SolidQueue/SolidCable 대신 Sidekiq/AnyCable 사용 시 Redis 서버도 필요
- **인프라 의존성 증가**: Console의 독립 배포 원칙에 위배

### 2. SQLite (WAL 모드) + Litestream — 채택

SQLite 파일을 PVC에 저장하고, Litestream Sidecar로 S3에 실시간 스트리밍 백업.

**장점**:
- **DB 서버 불필요**: 단일 파일로 운영. 인프라 의존성 최소화
- **Solid 스택 통합**: SolidQueue(잡 큐) + SolidCable(WebSocket pub/sub)이 동일 SQLite DB 사용. Redis 불필요
- **배포 단순화**: Deployment + PVC + Litestream Sidecar. 관리 포인트 최소
- **백업/복구 자동화**: Litestream이 WAL 변경을 S3에 실시간 복제. RPO ≈ 수초
- **Pod 재시작 시 자동 복원**: Init Container가 S3에서 최신 백업 복원

**단점**:
- **단일 writer 제약**: 쓰기 수평 확장 불가. Replicas = 1 고정
- **Recreate 배포**: 업그레이드 시 짧은 다운타임 (수십 초)
- **동시 쓰기 제한**: WAL 모드에서도 쓰기는 직렬화

## 결정

**SQLite (WAL 모드) + Litestream 채택**.

핵심 이유:
1. 내부 관리 콘솔의 사용 규모(소수 관리자, 낮은 쓰기 빈도)에 PostgreSQL은 과도
2. DB 서버/Redis 없이 단일 Pod으로 운영 가능 → 인프라 복잡도 대폭 감소
3. Rails 8 Solid 스택과 자연스러운 통합
4. Litestream으로 데이터 안전성 확보 (S3 실시간 백업, 자동 복원)

## 제약 및 허용 범위

| 제약 | 영향 | 허용 근거 |
|------|------|-----------|
| 단일 인스턴스 | 수평 확장 불가 | 내부 관리 콘솔 규모에 충분 |
| Recreate 배포 다운타임 | 업그레이드 시 수십 초 중단 | 내부 도구이므로 허용 가능 |
| 쓰기 직렬화 | 동시 쓰기 성능 제한 | SolidQueue Job이 직렬 처리하므로 문제 없음 |

## 향후 확장 경로

읽기 부하 분산 또는 제로 다운타임 배포가 필요하면, Litestream을 **LiteFS**로 교체하여 Primary(R/W) + Replica(R) 구성이 가능하다. 단, leader election(Consul 등) 인프라가 추가로 필요하다.

## 관련 문서

- PRD Section 8: 기술 스택
- PRD Section 8.2: K8s 배포 전략 (SQLite + Litestream)
- PRD Section 6.3: 확장성
- PRD Section 6.5: 동시성 제어
