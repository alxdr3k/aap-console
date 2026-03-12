# ADR-006: 프론트엔드 아키텍처 — Hotwire (서버 렌더링) vs SPA

> **상태**: Accepted
> **일자**: 2026-03-12
> **결정자**: Console 팀

## 컨텍스트

Console은 프로비저닝 현황의 실시간 업데이트, 폼 기반 설정 관리 등 동적 UI가 필요하다. 프론트엔드 아키텍처를 SPA(React/Vue)와 서버 렌더링(Hotwire) 중 선택해야 한다.

개발 팀은 Rails 백엔드를 사용하며, 프론트엔드 전담 인력이 별도로 없다.

## 선택지

### 1. SPA (React / Vue + API 서버) — 미채택

별도 프론트엔드 앱을 구축하고, Rails는 JSON API 서버로만 사용.

**장점**:
- 풍부한 클라이언트 인터랙션
- 프론트엔드/백엔드 독립 배포 가능
- React/Vue 생태계 활용

**단점**:
- **이중 코드베이스**: API 직렬화/역직렬화, 상태 관리, 라우팅 등 프론트엔드 인프라 별도 구축 필요
- **빌드 파이프라인 추가**: Node.js 빌드, 번들링, 프론트엔드 테스트 인프라
- **인력 부담**: 프론트엔드 전담 인력 없이 두 스택 유지 비용 높음
- **실시간 통신 복잡도**: WebSocket 클라이언트 상태 관리, 재연결 로직 등 직접 구현
- **내부 관리 콘솔에 과도**: 복잡한 클라이언트 상태가 필요한 서비스가 아님

### 2. Hotwire (Turbo + Stimulus) — 채택

Rails 서버에서 HTML을 렌더링하고, Turbo로 페이지 전환/부분 업데이트, Stimulus로 경량 JS 인터랙션 처리.

**장점**:
- **단일 코드베이스**: Rails View 내에서 HTML + 동적 업데이트 모두 처리. API 직렬화 불필요
- **실시간 통신 내장**: ActionCable + Turbo Streams로 서버 푸시 → DOM 자동 업데이트. 클라이언트 상태 관리 불필요
- **빌드 단순화**: Node.js 빌드 파이프라인 불필요. Rails asset pipeline만으로 충분
- **Rails 8 네이티브**: Hotwire는 Rails의 기본 프론트엔드 스택. 문서, 컨벤션, 커뮤니티 지원 풍부
- **개발 속도**: 서버 사이드 렌더링으로 빠른 프로토타이핑. 폼 기반 CRUD에 최적

**단점**:
- 오프라인/복잡한 클라이언트 상태 관리에 부적합 (Console에는 해당 없음)
- JavaScript 생태계의 UI 컴포넌트 라이브러리 직접 사용 어려움

## 결정

**Hotwire (Turbo + Stimulus) 채택**.

핵심 이유:
1. Console은 폼 기반 CRUD + 실시간 상태 표시가 주요 UI 패턴 → Hotwire의 강점에 정확히 부합
2. 프론트엔드 전담 인력 없이 단일 Rails 코드베이스로 유지 가능
3. ActionCable + Turbo Streams로 프로비저닝 실시간 업데이트(FR-7.3)를 최소 코드로 구현
4. SPA 도입 시의 이중 코드베이스/빌드 파이프라인 오버헤드가 내부 관리 콘솔에 과도

## 주요 활용 패턴

| 패턴 | Hotwire 기능 | 용도 |
|------|-------------|------|
| 페이지 전환 | Turbo Drive | SPA 같은 부드러운 네비게이션 (전체 페이지 리로드 없음) |
| 부분 업데이트 | Turbo Frames | 폼 제출 후 특정 영역만 교체 |
| 실시간 푸시 | Turbo Streams (ActionCable) | 프로비저닝 단계별 상태 실시간 업데이트 |
| JS 인터랙션 | Stimulus Controllers | 토글, 드롭다운, 폼 유효성 검사 등 경량 동작 |

## 관련 문서

- PRD Section 8: 기술 스택
- PRD Section FR-7.3: 프로비저닝 현황 화면
- HLD Section 6: 실시간 통신 (ActionCable)
- HLD Section 9: UI 와이어프레임
