# AAP Console Design System Prompt v2

```text
AAP Console의 디자인 시스템과 핵심 화면 템플릿을 만들어줘.

첨부한 PRD와 UI Spec을 제품 기능의 기준으로 삼되, 문서의 Phase 구분을 반드시 지켜줘. PRD의 FR은 최종 제품 범위이고, 실제 화면 노출은 Phase/MVP 상태에 따라 달라진다. Playground, SAML/OAuth/PAK 전체 지원, 전용 관리자 대시보드는 디자인 시스템에는 포함하되 구현 전에는 숨김 또는 disabled + "준비 중" 툴팁으로 처리한다.

제품 성격:
- AAP Console은 Organization과 Project 단위로 AI/LLM 서비스 설정을 생성/관리하는 B2B 운영 콘솔이다.
- 핵심 기능은 RBAC, Project 생성, Keycloak 인증 설정, Langfuse 연동 상태, LiteLLM 모델 라우팅/가드레일/S3 설정, 프로비저닝 현황, 설정 변경 이력/롤백, 일회성 시크릿 표시, 멤버 관리다.
- Rails + Hotwire(Turbo/Stimulus) 기반 서버 렌더링 UI다. SPA스러운 과한 클라이언트 앱이 아니라 폼, 테이블, 링크, Turbo Frame, Turbo Stream에 잘 맞는 패턴으로 설계한다.

디자인 방향:
- 마케팅 페이지가 아니라 매일 쓰는 관리 콘솔이다. 첫 화면부터 실제 업무 화면이어야 한다.
- 정보 밀도는 높지만 답답하거나 투박하지 않게, 정돈된 B2B SaaS 톤으로 세련되게 만든다.
- 넓은 hero, 장식 일러스트, 과한 gradient, 큰 카드 남발, 단색 계열로만 만든 팔레트는 피한다.
- 주요 객체(Organization, Project, Job, Config Version, Member)가 빠르게 스캔되어야 한다.
- 상태는 색상만 쓰지 말고 아이콘 + 텍스트 + 배지/라인 스타일을 함께 사용한다.

먼저 Design System을 정의해줘:
1. Foundations
   - Color tokens: neutral, surface, border, text, focus, semantic, role, provisioning status
   - Typography: 콘솔용 조밀한 hierarchy. 큰 hero 타입 금지
   - Spacing scale: dense/default/comfortable density 지원
   - Radius: 카드/패널은 8px 이하, 테이블/폼은 절제된 radius
   - Border/shadow: 카드 그림자보다 border와 surface hierarchy 중심
   - Motion: Turbo 전환, loading, realtime update에 필요한 최소 motion
   - Icon rules: 상태/액션에는 일관된 아이콘 사용

2. Core Components
   - AppShell, TopBar, Sidebar, Breadcrumb, PageHeader
   - Button: primary, secondary, ghost, destructive, icon-only, loading, disabled
   - FormField, Input, Textarea, Select, RadioGroup, CheckboxGroup, NumberInput, URIList
   - SearchAutocomplete
   - DataTable: sorting-ready, row action, empty/loading/error, clickable row
   - Tabs / SectionNav
   - Badge: StatusBadge, RoleBadge, PermissionBadge, PendingInviteBadge
   - Toast / Flash
   - Banner: warning, conflict, realtime disconnected, health warning
   - Modal / ConfirmationDialog / DestructiveNameConfirm
   - EmptyState
   - Skeleton / Spinner / TurboProgress
   - Tooltip
   - CopyButton
   - CollapsiblePanel
   - CodeBlock / JSONViewer / UnifiedDiffViewer

3. Domain Components
   - OrganizationCard
   - OrganizationSummary
   - ProjectTable
   - ProjectStatusCell
   - ProjectHeader
   - MemberTable
   - MemberAddModal
   - ProjectPermissionSelector
   - AuthConfigPanel
   - LangfuseStatusPanel: SDK Key 값은 표시하지 말고 "발급됨 / Config Server 전달됨" 상태만 표시
   - LiteLLMConfigEditor
   - ConfigVersionList
   - RollbackConfirmDialog
   - ProvisioningTimeline
   - ProvisioningStepRow
   - RollbackSection
   - SecretRevealPanel
   - PlaygroundShell, ChatMessage, ParameterPanel, RequestResponseInspector (Phase 4)

상태 매핑은 반드시 반영해줘:
- pending: 대기, gray, circle icon
- in_progress: 진행중, blue, spinner icon
- completed: 완료, green, check icon
- completed_with_warnings: 완료(경고 있음), amber, warning icon
- failed: 실패, red, x icon
- retrying: 재시도중, yellow, spinner icon
- rolling_back: 정리중, orange, spinner icon
- rolled_back: 실패(정리 완료), red, x icon
- rollback_failed: 실패(수동 조치 필요), red, warning icon

보안 UX:
- Keycloak Client Secret과 PAK는 기본 마스킹, 표시 토글, 복사, "확인 - 안전하게 저장했습니다" 플로우를 가진다.
- 10분 TTL 안내를 명확히 한다.
- Console DB/로그/설정 이력에는 저장하지 않는다는 느낌이 UI 문구에 드러나야 한다.
- Langfuse SDK Key(PK/SK)는 사용자에게 표시하지 않는다.

화면 템플릿을 만들어줘:
- Organization 목록
- Organization 상세: Project 테이블 + 멤버 요약
- Organization 생성
- 멤버 관리: 멤버 테이블 + 추가 모달 + Project 권한 모달
- Project 생성: Phase 1은 OIDC만 활성, SAML/OAuth/PAK는 disabled 준비 중
- Project 상세: header, auth/langfuse/litellm/history sections, Phase 4 Playground는 숨김/disabled
- Auth Config 편집: 인증 방식은 read-only, Redirect URI와 Secret 재발급 중심
- LiteLLM Config 편집
- Config Versions: 버전 목록, diff, rollback
- Provisioning Job: 진행중, 실패+롤백, 완료+시크릿 표시 상태
- Playground: Phase 4 화면 템플릿

각 컴포넌트와 화면마다 다음을 포함해줘:
- purpose
- anatomy
- variants
- states
- interaction rules
- accessibility notes
- do/don't

특히 UI가 투박해지지 않도록 다음을 신경 써줘:
- 테이블, 폼, 배너, 배지의 visual hierarchy를 섬세하게 잡기
- 상태 배지는 색 면적을 과하게 쓰지 말고 텍스트/아이콘 가독성을 우선하기
- 반복 카드보다 테이블과 섹션형 summary를 우선하기
- destructive action은 확실히 눈에 띄지만 화면 전체를 위협적으로 만들지 않기
- 빈 상태는 과한 일러스트보다 작고 명확한 아이콘 + 다음 행동 중심으로 처리하기
- 모바일에서는 sidebar collapse, table horizontal scroll 또는 stacked rows 규칙을 정의하기

최종 출력은 다음 순서로 작성해줘:
1. Product UI Principles
2. Foundations
3. Component Library
4. Domain Patterns
5. Page Templates
6. Phase Gating Rules
7. Accessibility Checklist
```
