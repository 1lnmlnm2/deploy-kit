#!/usr/bin/env bash
# common.sh —— deploy.sh / rollback.sh / verify.sh 共用：环境、加锁、渲染、切链、预检、标记、回滚。
set -euo pipefail
KIT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_ROOT="${APP_ROOT:-/opt/deploy-kit/site}"
ENV_FILE="$APP_ROOT/deploy.env"
init_dirs() {
  mkdir -p "$APP_ROOT/releases" "$APP_ROOT/shared/logs"
  if [ ! -f "$ENV_FILE" ]; then
    cp "$KIT_ROOT/conf/deploy.env.example" "$ENV_FILE"
    echo "[OK] 已生成环境文件 $ENV_FILE"
  fi
}
load_env() {
  init_dirs
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  : "${APP_ROOT:?APP_ROOT 未配置}" "${PORT:?PORT 未配置}" \
    "${KEEP:?KEEP 未配置}" "${HEALTH_PATH:?HEALTH_PATH 未配置}"
}
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "[FAIL] 需要 root 运行（当前 uid=$(id -u)）" >&2
    exit 64
  fi
}
lock_deploy() {
  exec 9>"$APP_ROOT/.deploy.lock"
  flock 9
  echo "[OK] 已取得部署锁 $APP_ROOT/.deploy.lock"
}
render_file() { # $1 模板 $2 目标 $3 版本
  [ -f "$1" ] || { echo "[FAIL] 模板缺失: $1" >&2; return 1; }
  sed -e "s|\${VERSION}|$3|g" \
      -e "s|\${BUILD_TIME}|$(date '+%F %T')|g" \
      -e "s|\${PORT}|$PORT|g" \
      -e "s|\${APP_ROOT}|$APP_ROOT|g" "$1" > "$2"
}
current_version() {
  if [ -L "$APP_ROOT/current" ]; then
    basename "$(readlink -f "$APP_ROOT/current")"
  fi
}
switch_current() { # 临时链 + mv -T 原子替换，不裸 ln -sf
  ln -s "$APP_ROOT/releases/$1" "$APP_ROOT/.current.tmp.$$"
  mv -Tf "$APP_ROOT/.current.tmp.$$" "$APP_ROOT/current"
}
audit() { # $1 动作 $2 版本 $3 结果
  printf '%s %s %s %s\n' "$(date '+%F %T')" "$1" "$2" "$3" >> "$APP_ROOT/shared/audit.log"
}
mark_deployed() { # $1 版本：成功标记
  printf '%s\n' "$(date '+%F %T')" > "$APP_ROOT/releases/$1/.deployed"
  rm -f "$APP_ROOT/releases/$1/.deploy-failed"
}
mark_failed() { # $1 版本 $2 一行原因：失败标记
  printf '%s %s\n' "$(date '+%F %T')" "${2:-deploy failed}" > "$APP_ROOT/releases/$1/.deploy-failed"
  rm -f "$APP_ROOT/releases/$1/.deployed"
}
list_marked() { # $1 标记文件名
  find "$APP_ROOT/releases" -mindepth 2 -maxdepth 2 -name "$1" -printf '%h\n' \
    | xargs -r -n1 basename | sort -V
}
release_list() { list_marked .deployed; }
release_list_failed() { list_marked .deploy-failed; }
precheck_release() { # $1 版本：切链前校验，缺件只拦截，不叫回滚
  local rel="$APP_ROOT/releases/$1" hv
  [ -f "$rel/public/index.html" ] || {
    echo "[FAIL] precheck failed: 缺 public/index.html" >&2; return 2; }
  [ -f "$rel/public/health.txt" ] || {
    echo "[FAIL] precheck failed: 缺 public/health.txt" >&2; return 2; }
  hv="$(cat "$rel/public/health.txt")"
  [ "$hv" = "$1" ] || {
    echo "[FAIL] precheck failed: health.txt=${hv:-<空>}，期望 $1" >&2; return 2; }
  echo "[OK] precheck: index.html 与 health.txt($1) 齐备，未切链"
}
apply_service() { # 已在跑则 reload，否则首启；失败返回非 0，由 deploy 统一回滚
  if systemctl is-active --quiet deploy-kit-site; then
    systemctl reload deploy-kit-site
  else
    systemctl enable --now deploy-kit-site >/dev/null
  fi
}
rollback_prev() { # $1 上一版（可空） $2 失败版本 $3 原因
  mark_failed "$2" "${3:-deploy failed}"
  if [ -n "$1" ]; then
    switch_current "$1"
    apply_service >> "$APP_ROOT/shared/logs/deploy.log" 2>&1 || true
    bash "$KIT_ROOT/scripts/health-gate.sh" "$1" \
      >> "$APP_ROOT/shared/logs/deploy.log" 2>&1 || true
    echo "[FAIL] 发布 $2 失败，已自动回滚到 $1（原因见 shared/logs/deploy.log）" >&2
  else
    systemctl disable --now deploy-kit-site >/dev/null 2>&1 || true
    rm -f "$APP_ROOT/current"
    echo "[FAIL] 发布 $2 失败且无上一版，已停用 unit 并移除 current" >&2
  fi
  audit deploy "$2" gate-failed
}
warn_keep() { # 发布成功后只告警，不删除；KEEP 只数成功版本
  local all count excess
  all="$(release_list)"
  count="$(printf '%s\n' "$all" | grep -c . || true)"
  [ "$count" -gt "$KEEP" ] || return 0
  excess="$(printf '%s\n' "$all" | head -n "$((count - KEEP))" | paste -sd, -)"
  echo "[WARN] 保留 ${count} 个，超过 KEEP=${KEEP}，超期版本: ${excess}（未删除，见 docs/02 §4）"
}
