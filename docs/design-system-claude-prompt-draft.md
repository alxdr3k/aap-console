# AAP Console Design System Prompt Draft

아래 프롬프트는 Claude Design에 넣기 위한 디자인 시스템 초안이다.

```text
AAP Console의 디자인 시스템을 만들어줘.

이 제품은 AI/LLM 서비스를 셀프서비스로 생성/관리하는 엔터프라이즈 관리 콘솔이다. 사용자는 Organization과 Project를 만들고, Keycloak 인증 설정, Langfuse 관측성, LiteLLM 모델 라우팅/가드레일/S3 설정, 프로비저닝 상태, 멤버 권한, 변경 이력, Playground를 관리한다.

디자인 방향은 마케팅 사이트가 아니라 운영자가 매일 쓰는 관리 콘솔이다. 정보 밀도는 높고, 테이블/폼/상태 표시가 중심이어야 한다. 장식적인 hero, 과한 카드 레이아웃, 넓은 여백, 단색 계열 위주의 팔레트는 피하고, 반복 작업과 상태 파악이 빠른 실무형 UI로 설계해줘.

핵심 IA:
- 전체 App Shell: 상단 바, 좌측 사이드바, 메인 콘텐츠
- Breadcrumb: Console > Organization > Project > 하위 페이지
- Organizations 목록/상세/생성
- Members 관리
- Projects 목록/상세/생성
- Auth Config 편집
- LiteLLM Config 편집
- Config Versions / diff / rollback
- Provisioning Job 실시간 현황
- Playground 채팅/요청 인스펙터
- 전역 Toast, Empty State, Loading, Error, Permission 상태

반드시 포함할 디자인 시스템 산출물:
1. Design Tokens
   - color, typography, spacing, radius, border, shadow, z-index, motion
   - 상태 색상: pending, in_progress, completed, completed_with_warnings, failed, retrying, rolling_back, rolled_back, rollback_failed
   - 권한 색상: super_admin, admin, write, read
   - 위험/경고/정보/성공/오류 색상
   - 색상만으로 의미를 전달하지 말고 아이콘 + 텍스트를 같이 쓰는 규칙 포함

2. Layout System
   - App Shell
   - Top Navigation
   - Sidebar with Organization tree
   - Main content width rules
   - Page Header
   - Breadcrumb
   - Section layout
   - Responsive rules for desktop/tablet/mobile
   - 관리 콘솔답게 모바일에서도 기능은 유지하되, 데스크톱 최적화 우선

3. Core Components
   - Button: primary, secondary, tertiary, destructive, icon-only, disabled, loading
   - Input, Textarea, Select, Checkbox, Radio, Number input
   - Form field with label, help text, validation error
   - Search input / autocomplete
   - Data table with row action, empty, loading, error
   - Tabs / segmented navigation
   - Badge: status, role, permission, pending invite
   - Toast / flash alert
   - Banner: warning, conflict, realtime disconnected, health warning
   - Modal / confirmation dialog
   - Empty State
   - Skeleton / spinner / progress bar
   - Tooltip
   - Copy-to-clipboard control
   - Collapsible panel
   - Diff viewer
   - Code/JSON viewer

4. Domain-Specific Components
   - OrganizationCard
   - ProjectTableRow
   - ProjectStatusBadge
   - RoleBadge
   - MemberRow
   - MemberAddModal
   - ProjectPermissionSelector
   - SecretRevealPanel
     - 기본 마스킹
     - 표시/숨김 토글
     - 복사 버튼
     - "확인 — 안전하게 저장했습니다" 액션
     - 10분 TTL 안내
   - ProvisioningTimeline
     - Step row
     - parallel step 표시
     - duration
     - error message
     - retry count
     - rollback section
     - manual retry action
   - ConfigSummaryCard
   - ConfigVersionRow
   - UnifiedDiffPanel
   - PlaygroundChatMessage
   - PlaygroundParameterPanel
   - RequestResponseInspector

5. 상태 매핑 규칙
   Job 상태:
   - pending: 대기, gray, circle icon
   - in_progress: 진행중, blue, spinner icon
   - completed: 완료, green, check icon
   - completed_with_warnings: 완료(경고 있음), amber, warning icon
   - failed: 실패, red, x icon
   - retrying: 재시도중, yellow, spinner icon
   - rolling_back: 정리중, orange, spinner icon
   - rolled_back: 실패(정리 완료), red, x icon
   - rollback_failed: 실패(수동 조치 필요), red, warning icon

   Step 상태:
   - pending: 대기
   - in_progress: 진행중...
   - completed: 완료
   - failed: 실패
   - skipped: 완료처럼 표시
   - rolled_back: 롤백 완료
   - rollback_failed: 롤백 실패

6. 주요 화면 예시를 컴포넌트 조합으로 만들어줘
   - Organization 목록
   - Organization 상세: Project 테이블 + 멤버 요약
   - 멤버 관리: 멤버 테이블 + 추가 모달
   - Project 상세: 인증/Langfuse/LiteLLM/이력 요약
   - Project 생성 폼
   - LiteLLM Config 편집 폼
   - Auth Config 편집 폼
   - Provisioning 현황: 진행중/실패+롤백/완료+시크릿 표시
   - Config Version diff + rollback
   - Playground

7. UX 원칙
   - 서버 렌더링 Rails + Hotwire 환경을 전제로 한다.
   - React/Vue 중심 패턴처럼 보이지 않게, 링크/폼/테이블 중심의 점진적 향상 UI로 설계한다.
   - Turbo Frame, Turbo Stream, Stimulus에 어울리는 컴포넌트 상태를 정의한다.
   - 위험 액션은 이름 입력 확인 또는 명확한 확인 모달을 사용한다.
   - 권한이 없을 때는 숨김/disabled/tooltip 규칙을 명확히 한다.
   - 프로비저닝처럼 실시간성이 중요한 영역은 상태 변화가 즉시 눈에 들어오게 설계한다.
   - 시크릿은 보안 중심 UX로 설계한다. 평문 저장을 암시하지 않는다.
   - 접근성: 키보드 탐색, focus ring, aria-label, color contrast, 색상+아이콘+텍스트 중복 전달을 포함한다.

8. 출력 형식
   - 디자인 시스템 문서 구조로 작성해줘.
   - 먼저 Foundation, 그 다음 Components, 그 다음 Patterns, 마지막에 Page Templates 순서로 정리해줘.
   - 각 컴포넌트마다 목적, anatomy, variants, states, usage rules, do/don't를 포함해줘.
   - 가능한 경우 컴포넌트 이름은 실제 구현에 쓰기 좋은 PascalCase로 제안해줘.
   - 시각 스타일은 과하지 않은 B2B SaaS/운영 콘솔 톤으로 잡아줘.
```
