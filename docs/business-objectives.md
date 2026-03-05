# AAP Console 업무 목표

> 본 문서는 AAP Console 프로젝트의 핵심 업무 목표를 정의합니다.

---

## BO-1. 타 팀 온보딩 전용 AAP Console 웹 인터페이스 개발

타 부서 사용자가 프로젝트(App)을 등록하고, 발급된 인프라 정보를 확인할 수 있는 전용 관리 콘솔을 구축한다.

## BO-2. Terraform 기반 인프라 프로비저닝 백엔드 시스템 설계

Console의 요청을 받아 Terraform 워크스페이스를 생성하고 실행을 제어하는 API 서버 및 상태 관리 로직을 개발한다.

## BO-3. Keycloak Client 및 OIDC 인증 체계 자동 구성

Keycloak Terraform Provider를 활용하여 신규 App용 Client ID/Secret 발급 및 인증 환경을 자동화한다.

## BO-4. Langfuse Project Isolation 및 SDK Key 자동 발급

타 팀별 독립적인 LLM 트레이싱 환경 제공을 위해 Langfuse API를 연동하여 프로젝트 생성 및 키 발급 프로세스를 구현한다.

## BO-5. LiteLLM 타겟 그룹별 전용 Config 자동 생성 모듈 개발

AAP 요구사항에 맞는 모델 라우팅 설정을 생성하고, LiteLLM 서버의 config.yaml에 동적으로 반영하는 코드를 구현한다.

## BO-6. Terraform State 분리 및 테넌트별 리소스 생명주기 관리

각 App의 인프라 상태를 개별 State 파일로 관리하여 영향도를 최소화하고, App 삭제 시 자원 회수(destroy)를 자동화한다.

## BO-7. AAP Console 내 실시간 Terraform 실행 로그 시각화

인프라 배포 중 발생하는 로그를 Console UI에서 실시간으로 확인할 수 있는 스트리밍 서비스를 구현한다.

## BO-8. App별 인프라 설정 변경 이력 관리 및 버전 롤백 체계

설정 오류 발생 시 이전 안정 버전의 Terraform 구성으로 즉시 복구할 수 있는 GitOps 기반 버전 관리를 연동한다.

## BO-9. 인프라 프로비저닝 단계별 정합성 검증 및 테스트 자동화

Terraform 적용 후 Keycloak 로그인 및 LiteLLM API 호출이 정상인지 확인하는 Health Check 자동화 로직을 추가한다.
