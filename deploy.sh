#!/usr/bin/env bash
# deploy.sh —— 单机静态站点发布：deploy <版本> / uninstall / status
# 流程：加锁 → 幂等判断 → 建 release → 渲染 → 原子切 current → systemd 启停 → 健康闸门 → 失败自动回滚。
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/scripts/lib/common.sh"

usage() {
  cat >&2 <<'EOF'
用法: deploy.sh deploy <版本号(8位日期)> | status | uninstall
  deploy <版本>   发布或升级到指定版本（幂等）
  status          查看 current / releases / unit / 健康状态
  uninstall       停用 unit、删 current 链接，保留 releases 与 shared
EOF
}

cmd="${1:-}"
case "$cmd" in
  deploy)
    [ $# -eq 2 ] || { usage; exit 64; }
    require_root
    load_env
    V="$2"
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
    render_file "$KIT_ROOT/conf/index.html.template" "$REL/public/index.html" "$V"
    printf '%s\n' "$V" > "$REL/public/health.txt"
    if ! nginx -t -c "$REL/conf/nginx.conf" >/dev/null 2>&1; then
      echo "[FAIL] nginx 配置校验失败: $REL/conf/nginx.conf" >&2
      exit 2
    fi
    install -m 0644 "$KIT_ROOT/systemd/deploy-kit-site.service" \
      /etc/systemd/system/deploy-kit-site.service
    systemctl daemon-reload
    switch_current "$V"
    if systemctl is-active --quiet deploy-kit-site; then
      systemctl reload deploy-kit-site
    else
      systemctl enable --now deploy-kit-site >/dev/null
    fi
    GATE_RC=0
    bash "$SCRIPT_DIR/scripts/health-gate.sh" "$V" \
      >> "$APP_ROOT/shared/logs/deploy.log" 2>&1 || GATE_RC=$?
    if [ "$GATE_RC" -ne 0 ]; then
      audit deploy "$V" gate-failed
      if [ -n "$PREV" ]; then
        switch_current "$PREV"
        systemctl reload deploy-kit-site 2>/dev/null || systemctl restart deploy-kit-site
        bash "$SCRIPT_DIR/scripts/health-gate.sh" "$PREV" \
          >> "$APP_ROOT/shared/logs/deploy.log" 2>&1 || true
        echo "[FAIL] 健康闸门失败，已自动回滚到 $PREV（原因见 shared/logs/deploy.log）" >&2
      else
        echo "[FAIL] 健康闸门失败，无上一版可回滚（原因见 shared/logs/deploy.log）" >&2
      fi
      exit 2
    fi
    audit deploy "$V" success
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
    CUR="$(current_version)"
    echo "current: ${CUR:-<无>}"
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
