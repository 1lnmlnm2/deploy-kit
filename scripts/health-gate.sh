#!/usr/bin/env bash
# health-gate.sh —— 切链后三项闸门：8090 监听、health.txt 含版本、GET / 200 且含版本。
# 连查 3 次、间隔 2 秒；任一项不符即返回 2，由 deploy.sh 统一回滚。
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
load_env
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "用法: health-gate.sh <期望版本号>" >&2
  exit 64
fi
BASE="http://127.0.0.1:${PORT}"
REASON=""
for i in 1 2 3; do
  REASON=""
  if ! ss -lntp 2>/dev/null | grep -q ":${PORT}"; then
    REASON="端口 ${PORT} 未监听"
  fi
  if [ -z "$REASON" ]; then
    BODY="$(curl --max-time 3 -fsS "${BASE}${HEALTH_PATH}" 2>/dev/null || true)"
    case "$BODY" in
      *"$VERSION"*) ;;
      *) REASON="health.txt 返回 ${BODY:-<空>}，期望含 $VERSION" ;;
    esac
  fi
  if [ -z "$REASON" ]; then
    PAGE="$(curl --max-time 3 -fsS "${BASE}/" 2>/dev/null || true)"
    case "$PAGE" in
      *"$VERSION"*) ;;
      *) REASON="GET / 未返回 200 或响应体不含 $VERSION" ;;
    esac
  fi
  if [ -z "$REASON" ]; then
    echo "[OK] 第 ${i} 次闸门通过：端口 / health.txt / 首页版本一致"
    exit 0
  fi
  echo "[WARN] 第 ${i} 次闸门未过: $REASON" >&2
  [ "$i" -lt 3 ] && sleep 2
done
echo "[FAIL] 健康闸门失败: $REASON" >&2
exit 2
