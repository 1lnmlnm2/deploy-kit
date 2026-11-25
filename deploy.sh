#!/usr/bin/env bash
# deploy.sh —— deploy <版本> [--pkg <目录|tar.gz>] / status / uninstall
# 流程：加锁 → 幂等 → 建 release → 包复制或模板渲染 → 预检 → 切链 → 启停 → 三项闸门 → 失败回滚。
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/scripts/lib/common.sh"

usage() {
  cat >&2 <<'EOF'
用法: deploy.sh deploy <8位版本> [--pkg <目录|tar.gz>] | status | uninstall
  --pkg 可选：包内 public/ 复制进新版本；缺省则用模板渲染（演练模式）
EOF
}

cmd="${1:-}"
case "$cmd" in
  deploy)
    [ $# -ge 2 ] || { usage; exit 64; }
    V="$2"; shift 2
    PKG=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --pkg)
          [ $# -ge 2 ] || { usage; exit 64; }
          PKG="$2"; shift 2 ;;
        *) echo "[FAIL] 未知参数: $1" >&2; exit 64 ;;
      esac
    done
    require_root
    load_env
    case "$V" in
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
      *) echo "[FAIL] 版本号必须是 8 位数字，收到: $V" >&2; exit 64 ;;
    esac
    lock_deploy
    PREV="$(current_version)"
    if [ -d "$APP_ROOT/releases/$V" ] && [ "$PREV" = "$V" ]; then
      echo "already deployed, nothing changed"
      exit 0
    fi
    REL="$APP_ROOT/releases/$V"
    mkdir -p "$REL/conf" "$REL/public"
    render_file "$KIT_ROOT/conf/nginx.conf.template" "$REL/conf/nginx.conf" "$V"
    if [ -n "$PKG" ]; then
      if [ -d "$PKG" ] && [ -d "$PKG/public" ]; then
        cp -a "$PKG/public/." "$REL/public/"
      elif [ -f "$PKG" ]; then
        tar -xzf "$PKG" -C "$REL"
      else
        echo "[FAIL] 包不存在或缺 public/: $PKG" >&2
        exit 2
      fi
    else
      render_file "$KIT_ROOT/conf/index.html.template" "$REL/public/index.html" "$V"
      printf '%s\n' "$V" > "$REL/public/health.txt"
    fi
    if ! precheck_release "$V"; then
      exit 2
    fi
    if ! nginx -t -c "$REL/conf/nginx.conf" >/dev/null 2>&1; then
      echo "[FAIL] nginx 配置校验失败: $REL/conf/nginx.conf" >&2
      exit 2
    fi
    install -m 0644 "$KIT_ROOT/systemd/deploy-kit-site.service" \
      /etc/systemd/system/deploy-kit-site.service
    systemctl daemon-reload
    switch_current "$V"
    SVC_RC=0
    apply_service >> "$APP_ROOT/shared/logs/deploy.log" 2>&1 || SVC_RC=$?
    if [ "$SVC_RC" -ne 0 ]; then
      echo "[FAIL] 服务 reload/start 失败（rc=$SVC_RC），进入回滚" >&2
      rollback_prev "$PREV" "$V"
      exit 2
    fi
    GATE_RC=0
    bash "$SCRIPT_DIR/scripts/health-gate.sh" "$V" \
      >> "$APP_ROOT/shared/logs/deploy.log" 2>&1 || GATE_RC=$?
    if [ "$GATE_RC" -ne 0 ]; then
      rollback_prev "$PREV" "$V"
      exit 2
    fi
    audit deploy "$V" success
    warn_keep
    echo "[OK] $V 上线成功，current -> releases/$V"
    exit 0
    ;;
  uninstall)
    require_root
    load_env
    lock_deploy
    systemctl disable --now deploy-kit-site >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/deploy-kit-site.service
    systemctl daemon-reload
    rm -f "$APP_ROOT/current"
    audit uninstall - success
    echo "[OK] 已停用并禁用 unit，8090 应无监听；releases 与 shared 保留"
    exit 0
    ;;
  status)
    load_env
    echo "current: $(current_version)"
    echo "releases: $(release_list | wc -l) 个"
    echo "unit: $(systemctl is-active deploy-kit-site 2>/dev/null || true)"
    BODY="$(curl --max-time 3 -fsS "http://127.0.0.1:${PORT}${HEALTH_PATH}" 2>/dev/null || true)"
    echo "health: ${BODY:-<不可达>}"
    echo "audit: $(wc -l < "$APP_ROOT/shared/audit.log" 2>/dev/null || echo 0) 行"
    exit 0
    ;;
  *)
    usage
    exit 64
    ;;
esac
