#!/usr/bin/env bash
# rollback.sh —— 切换到指定版本；默认上一版。切换后同样过健康闸门。
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/scripts/lib/common.sh"

TO=""
case $# in
  0) ;;
  2) [ "$1" = "--to" ] || { echo "用法: rollback.sh [--to <版本>]" >&2; exit 64; }; TO="$2" ;;
  *) echo "用法: rollback.sh [--to <版本>]" >&2; exit 64 ;;
esac

require_root
load_env
lock_deploy
CUR="$(current_version)"
[ -n "$CUR" ] || { echo "[FAIL] current 不存在，没有可回滚的基线" >&2; exit 65; }

if [ -z "$TO" ]; then
  mapfile -t ALL < <(release_list)
  for i in "${!ALL[@]}"; do
    if [ "${ALL[$i]}" = "$CUR" ] && [ "$i" -gt 0 ]; then
      TO="${ALL[$((i - 1))]}"
    fi
  done
fi
[ -n "$TO" ] || { echo "[FAIL] 找不到上一版，请用 --to 指定" >&2; exit 65; }
[ -d "$APP_ROOT/releases/$TO" ] || { echo "[FAIL] 目标版本不存在: $TO" >&2; exit 65; }

if [ "$CUR" = "$TO" ]; then
  echo "already on version $TO, nothing changed"
  exit 0
fi

switch_current "$TO"
systemctl reload deploy-kit-site 2>/dev/null || systemctl restart deploy-kit-site
GATE_RC=0
bash "$SCRIPT_DIR/scripts/health-gate.sh" "$TO" \
  >> "$APP_ROOT/shared/logs/deploy.log" 2>&1 || GATE_RC=$?
if [ "$GATE_RC" -ne 0 ]; then
  audit rollback "$TO" gate-failed
  echo "[FAIL] 回滚到 $TO 后闸门失败，现场保持在 $TO（原因见 shared/logs/deploy.log）" >&2
  exit 2
fi

audit rollback "$TO" success
echo "[OK] 已回滚到 $TO，current -> releases/$TO"
exit 0
