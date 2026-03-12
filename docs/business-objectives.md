# AAP Console 업무 목표

> 본 문서는 AAP Console 프로젝트의 핵심 업무 목표를 정의합니다.

---

## BO-1. 타 팀 온보딩 전용 AAP Console 웹 인터페이스 개발

타 부서 사용자가 프로젝트(App)을 등록하고, 발급된 인프라 정보를 확인할 수 있는 전용 관리 콘솔을 구축한다.

## BO-2. 프로비저닝 파이프라인 백엔드 시스템 설계

Console의 요청을 받아 Keycloak, Langfuse, Config Server 등 공유 서비스의 API를 직접 호출하여 리소스를 생성하고, 실패 시 보상 트랜잭션으로 롤백하는 프로비저닝 파이프라인을 개발한다.

## BO-3. Keycloak Client 및 OIDC 인증 체계 자동 구성

Keycloak Admin REST API를 활용하여 신규 App용 Client ID/Secret 발급 및 인증 환경을 자동화한다.

## BO-4. Langfuse Project Isolation 및 SDK Key 자동 발급

타 팀별 독립적인 LLM 트레이싱 환경 제공을 위해 Langfuse tRPC API를 연동하여 프로젝트 생성 및 키 발급 프로세스를 구현한다.

## BO-5. LiteLLM 타겟 그룹별 전용 Config 자동 생성 모듈 개발

AAP 요구사항에 맞는 모델 라우팅 설정을 생성하고, Config Server Admin API를 통해 LiteLLM에 동적으로 반영하는 코드를 구현한다.

## BO-6. App별 리소스 생명주기 관리

각 App의 설정 상태를 Console DB와 Config Server 버전 관리로 추적하여 영향도를 최소화하고, App 삭제 시 모든 외부 리소스를 자동으로 정리(롤백)한다.

## BO-7. AAP Console 내 실시간 프로비저닝 로그 시각화

프로비저닝 파이프라인 실행 중 발생하는 단계별 상태를 Console UI에서 ActionCable을 통해 실시간으로 확인할 수 있는 스트리밍 서비스를 구현한다.

## BO-8. App별 설정 변경 이력 관리 및 버전 롤백 체계

설정 오류 발생 시 Config Server의 버전 식별자 기반으로 이전 안정 버전으로 즉시 복구할 수 있는 버전 관리 체계를 구축한다.

## BO-9. 프로비저닝 단계별 정합성 검증 및 테스트 자동화

프로비저닝 완료 후 Keycloak Client 생성 확인, LiteLLM API 호출 정상 여부, Langfuse SDK Key 연결 테스트 등 Health Check 자동화 로직을 추가한다.
