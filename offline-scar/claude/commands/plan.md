---
name: plan
description: needs를 Plan 문서로 구체화한다 (nPTiR n → P 진입). 템플릿 복사 후 채운다.
---

# /plan — 플랜 작성

needs(대화/메모)를 정식 Plan 문서로 만든다. nPTiR의 n→P 진입점이며,
이후 `/issue-reg`가 이 Plan을 이슈로 등록한다.

## 절차
1. 주제를 kebab-case `slug`로 정한다(예: `add-login-api`).
2. 템플릿을 복사한다:
   `cp _doc_work/plan/_TEMPLATE_plan.md _doc_work/plan/{slug}_plan.md`
   (템플릿이 없으면 아래 필수 섹션으로 새로 만든다.)
3. 프런트매터: `name: {slug}_plan`, `description`, `issue: TBD`,
   `task: _doc_work/tasks/{slug}_task.md`.
4. 필수 섹션을 채운다: **배경 / 목표 / 설계 / 단계별 계획 / 위험 및 트레이드오프 / 검증 기준**
   (doc-design-rules).
5. 완료되면 `/issue-reg`로 이슈 등록·Task 생성으로 진행한다.

규칙: [doc-design-rules](../rules/doc-design-rules.md), 절차: [nptir-flow](../skills/nptir-flow/SKILL.md).
