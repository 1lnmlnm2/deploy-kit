#!/usr/bin/env bash
# verify.sh —— 只读自检 6 行：unit / 端口 / current / health.txt / releases 数 / 审计行数。
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../scripts/lib/common.sh"
load_env
RC=0
say() { # $1 级别 $2 说明
  printf '[%s] %s\n' "$1" "$2"
  case "$1" in FAIL) RC=2 ;; WARN) [ "$RC" -ge 1 ] || RC=1 ;; esac
}

if systemctl is-active --quiet deploy-kit-site; then
  say OK "unit deploy-kit-site: active"
else
  say FAIL "unit deploy-kit-site: 未 active"
fi

if ss -lntp 2>/dev/null | grep -q ":${PORT}"; then
  say OK "端口 ${PORT}: 已监听"
else
  say FAIL "端口 ${PORT}: 未监听"
fi

CUR="$(current_version)"
if [ -n "$CUR" ] && [ -d "$APP_ROOT/releases/$CUR" ]; then
  say OK "current: releases/$CUR"
else
  say FAIL "current: 缺失或指向不存在的版本"
fi

BODY="$(curl --max-time 3 -fsS "http://127.0.0.1:${PORT}${HEALTH_PATH}" 2>/dev/null || true)"
if [ -n "$CUR" ] && [ "$BODY" = "$CUR" ]; then
  say OK "health.txt: 返回 $BODY"
else
  say FAIL "health.txt: 期望 $CUR，实际 ${BODY:-<空>}"
fi

COUNT="$(release_list | wc -l)"
if [ "$COUNT" -le "$KEEP" ]; then
  say OK "releases: 成功 ${COUNT} 个（KEEP=${KEEP}）"
else
  say WARN "releases: 成功 ${COUNT} 个，超过 KEEP=${KEEP}，仅告警不清理"
fi
FAILED="$(release_list_failed)"
if [ -n "$FAILED" ]; then
  printf '[WARN] 失败版本 %s 个（保留现场）: %s\n' \
    "$(printf '%s\n' "$FAILED" | wc -l)" "$(printf '%s\n' "$FAILED" | paste -sd, -)"
fi

LINES="$(wc -l < "$APP_ROOT/shared/audit.log" 2>/dev/null || echo 0)"
say OK "审计行数: ${LINES}"
exit "$RC"
