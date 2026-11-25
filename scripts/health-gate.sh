#!/usr/bin/env bash
# health-gate.sh —— 连查 3 次健康接口，响应体必须含期望版本号；只读，不发版。
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
load_env

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "用法: health-gate.sh <期望版本号>" >&2
  exit 64
fi

URL="http://127.0.0.1:${PORT}${HEALTH_PATH}"
BODY=""
for i in 1 2 3; do
  BODY="$(curl --max-time 3 -fsS "$URL" 2>/dev/null || true)"
  case "$BODY" in
    *"$VERSION"*)
      echo "[OK] 第 ${i} 次闸门通过: $URL -> $BODY"
      exit 0
      ;;
  esac
  echo "[WARN] 第 ${i} 次闸门未过: 期望含 $VERSION，实际 ${BODY:-<空>}" >&2
  [ "$i" -lt 3 ] && sleep 2
done

echo "[FAIL] 健康闸门失败: $URL 连续 3 次未返回版本 $VERSION" >&2
exit 2
