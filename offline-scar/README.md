---
name: README
description: 단독망 ollama Claude(서버 99 / DGX Spark) 전용 린 SCAR 번들 — 소스·배포
date: 2026-06-05
---

# offline-scar — 단독망 린 SCAR 번들

서버 99(`ds` = `spark-1`, DGX Spark, aarch64, 단독망)에서 **로컬 ollama 모델**로
구동되는 네이티브 Claude Code 용 **린(lean) SCAR** 소스. 작은 컨텍스트·로컬 모델·
인터넷 차단 환경에 맞춰 최소 자산만 둔다. 목적: **웹앱 개발 + 프로젝트 관리**.

## 배경 (왜 별도 번들인가)
- 호스트 글로벌 `~/.claude`(jm4)는 풀 Opus 온라인용으로 비대(commands 47·rules 14·skills 119) → 로컬 모델엔 과중.
- 서버 99는 컨테이너가 아니라 **호스트 네이티브** Claude Code(`admin@spark-1:~/.claude`)로 동작하며, 이미 린 SCAR 기반(`base-rules`·`doc-design-rules`·issue 사이클·`nptir-flow`)이 깔려 있다.
- 본 번들은 거기에 **부족한 코어 SCAR만 추가**한다(기존 자산·서버 값 불변).

## 포함 자산 (추가분)
| 경로 | 역할 |
| :--- | :--- |
| `claude/rules/md-rules.md` | 마크다운 규약(프런트매터·아웃라인·불릿·표). base-rules 상속 |
| `claude/rules/offline-exec-rules.md` | 단독망(인터넷 금지)+로컬모델 실행 규율(종료조건·재시도·승인). base-rules 상속 |
| `claude/commands/plan.md` | nPTiR n→P 진입 커맨드(plan 스캐폴딩). 기존 issue-reg→fix→closer 앞단 보완 |

> 서버 99에 이미 있는 자산(`base-rules`·`doc-design-rules`·`issue-reg/fix/closer`·`nptir-flow`·`agents/reviewer`)은 건드리지 않는다.

## 배포 (서버 99 전용)
```bash
./deploy-to-99.sh            # rsync 추가분 → admin@spark-1:~/.claude (additive, 삭제 없음)
./deploy-to-99.sh --dry-run  # 미리보기
```
- **서버 값 불변**: `settings.json`·`.credentials.json`·docker/compose·모델·플랫폼 specs는 절대 변경하지 않는다.
- `CLAUDE.md` 하네스 인덱스(Rules/Commands 목록)에 신규 자산을 잇는 1줄 추가만 백업 후 수행(스크립트가 처리).

## 다음 증분 (요청 시)
- 웹 도메인 룰 `web-rules.md`(`-w`, base 상속: REST API 규약·gradle 빌드·mariadb·`f` 접두사).
- 웹앱 개발 사이클 커맨드(`/verify` 등) — springboot(`~/Desktop/nowage/app`) 대상.
