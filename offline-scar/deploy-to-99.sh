#!/usr/bin/env bash
# deploy-to-99.sh — 린 SCAR 추가분을 서버 99(ds=spark-1) 네이티브 ~/.claude 로 배포.
#
# 단독망 서버 99 전용. ADDITIVE only — 기존 파일·서버 값(settings/credentials/docker/모델)
# 절대 변경 금지. rsync 는 --ignore-existing 으로 신규 파일만 보낸다(기존 SCAR 덮어쓰지 않음).
# CLAUDE.md 하네스 인덱스 1줄 연결만 백업 후 수행한다.
set -euo pipefail

REMOTE="ds"                       # ~/.ssh/config alias (admin@192.168.0.181)
SRC="$(cd "$(dirname "$0")/claude" && pwd)"
DRY=""
[ "${1:-}" = "--dry-run" ] && DRY="-n"

echo "== 1. 추가분 rsync (--ignore-existing, 삭제 없음) =="
rsync -av $DRY --ignore-existing \
  "$SRC/rules/"    "$REMOTE:.claude/rules/"
rsync -av $DRY --ignore-existing \
  "$SRC/commands/" "$REMOTE:.claude/commands/"

if [ -n "$DRY" ]; then
  echo "== dry-run 종료 (CLAUDE.md 미수정) =="
  exit 0
fi

echo "== 2. CLAUDE.md 하네스 인덱스 연결 (백업 후, 멱등) =="
ssh "$REMOTE" 'python3 - <<PY
import io, datetime, pathlib, shutil
p = pathlib.Path.home()/".claude"/"CLAUDE.md"
s = p.read_text(encoding="utf-8")
bak = p.with_suffix(".md.bak-"+datetime.date.today().isoformat())
if not bak.exists():
    shutil.copy2(p, bak)
old_rules = "SSOT 베이스 [base-rules](rules/base-rules.md) + 도메인 오버라이드(`doc-design-`)."
new_rules = "SSOT 베이스 [base-rules](rules/base-rules.md) + 도메인 오버라이드(`doc-design-`) + 공통 [md-rules](rules/md-rules.md)·[offline-exec-rules](rules/offline-exec-rules.md)."
old_cmd = "`/issue-reg` → `/issue-fix` → `/issue-closer`."
new_cmd = "`/plan` → `/issue-reg` → `/issue-fix` → `/issue-closer`."
ch = 0
if old_rules in s and new_rules not in s:
    s = s.replace(old_rules, new_rules); ch += 1
if old_cmd in s and new_cmd not in s:
    s = s.replace(old_cmd, new_cmd); ch += 1
p.write_text(s, encoding="utf-8")
print(f"CLAUDE.md 변경 라인: {ch} (백업: {bak.name})")
PY'

echo "== 3. 검증 =="
ssh "$REMOTE" 'ls -1 ~/.claude/rules/md-rules.md ~/.claude/rules/offline-exec-rules.md ~/.claude/commands/plan.md && grep -n "md-rules\|offline-exec\|/plan" ~/.claude/CLAUDE.md'
echo "== 완료 =="
