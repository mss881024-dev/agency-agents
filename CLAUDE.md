# 작업 원칙

## Skill 자동 적용
- 어떤 skill을 쓸지 묻지 말고 요청에 맞는 skill을 직접 골라 적용한다. 사용한 skill은 응답에 한 줄로만 알린다.
- 상식적인 범위에서 적용한다. 간단한 질문에 무거운 skill을 쓰지 않는다.
- 아래 skill이 이 PC에 설치되어 있지 않으면 skill 없이 같은 원칙대로 작업한다.

## 영역별 기본 skill
- 업무 분석·리서치: deep-research, research-ops, market-research, 경쟁 분석은 competitive-platform-analysis → benchmark-methodology → competitive-report-structure, 기획 검증은 product-lens, 요구사항 정리는 intent-driven-development
- 품질·제조: quality-nonconformance(일탈, CAPA, 8D)
- 제약 IT·규제: pharma-it-compliance (GxP, CSV, Data Integrity, ISO27001, 망분리, 개인정보보호법 관점으로 검토)
- 문서 작성: 한국어 문서는 개조식·두괄식·정량 중심으로 쓴다(humanizer). Office 파일은 docx/xlsx/pptx, 의사결정 기록은 architecture-decision-records
- Python 자동화: python-patterns, error-handling, python-testing을 기본으로 쓴다. 새로 만들기 전에 search-first로 기존 라이브러리를 찾는다. 작업을 마치면 verification-loop로 검증한다.
- 코드 작업: 기능 개발은 superpowers:brainstorming/writing-plans, 버그는 superpowers:systematic-debugging, 변경 후에는 언어별 ecc reviewer로 리뷰한다.
- 프로젝트 관리·보고: senior-pm, status-report, risk-assessment

## 문서(MD) 작업 규칙
- 모든 문서는 결론 한 줄로 시작하고, 수치(%, 일수, 금액)로 쓴다. 수치는 확인된 값만 쓴다.
- 기존 문서를 고칠 때는 덮어쓰지 말고 기존 구조와 파일 위치를 따른다.

## 커뮤니케이션·Git
- 답변은 한국어로 하고, 결론부터 쓴다.
- Git 커밋·푸시는 이 저장소에 정해진 기존 워크플로(자동 커밋·동기화 규칙)를 따른다. 정해진 규칙이 없으면 실행 전에 확인을 받는다.
- 외부 발송(메일, Slack 등)과 삭제·강제 푸시는 항상 실행 전에 확인을 받는다.
