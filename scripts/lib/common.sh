#!/usr/bin/env bash
# common.sh —— deploy.sh / rollback.sh / verify.sh 共用：环境加载、目录初始化、加锁、渲染、切链、审计。
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

render_file() { # $1 模板绝对路径 $2 目标文件 $3 版本号
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

switch_current() { # $1 版本号：临时链 + mv -T 原子替换，不裸 ln -sf
  ln -s "$APP_ROOT/releases/$1" "$APP_ROOT/.current.tmp.$$"
  mv -Tf "$APP_ROOT/.current.tmp.$$" "$APP_ROOT/current"
}

audit() { # $1 动作 $2 版本 $3 结果
  printf '%s %s %s %s\n' "$(date '+%F %T')" "$1" "$2" "$3" >> "$APP_ROOT/shared/audit.log"
}

release_list() {
  find "$APP_ROOT/releases" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V
}
