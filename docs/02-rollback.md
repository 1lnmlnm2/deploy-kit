# 02 回滚与卸载

## §1 手动回滚

默认回上一版：
```bash
sudo bash rollback.sh
```
指定版本：
```bash
sudo bash rollback.sh --to 20261125
```
本轮实测（2026-11-25）：
```
[OK] 已取得部署锁 /opt/deploy-kit/site/.deploy.lock
[OK] 已回滚到 20261125，current -> releases/20261125
```
退出码 0；`curl http://127.0.0.1:8090/health.txt` 返回 `20261125`。
重跑同一目标实测：
```
[OK] 已取得部署锁 /opt/deploy-kit/site/.deploy.lock
already on version 20261125, nothing changed
```
退出码 0。

目标不存在：`[FAIL] 目标版本不存在: ...`，退出码 65。

## §2 闸门失败处置

切链前先做预检：`public/index.html`、`public/health.txt` 必须存在，且 `health.txt` 内容等于版本号；不满足则打印 `precheck failed`、**不切链**、`exit 2`，这是预检拦截，不是回滚。

切链后三项闸门：① 8090 在监听；② `/health.txt` 返回版本号；③ `GET /` 返回 200 且响应体含版本号。连查 3 次、间隔 2 秒，任一不符即自动切回上一版并 `exit 2`。切链后的 `systemctl reload/start` 失败也进入同一回滚分支，不会因 `set -e` 直接退出。
`rollback.sh` 切链后的启停失败同样会打印 `[FAIL]`、记审计并 `exit 2`，不会静默退出。

首版闸门失败且没有上一版：`systemctl disable --now deploy-kit-site`、移除 `current` 软链、`exit 2`；`releases/` 与 `shared/` 保留供排查。

排查顺序：
```bash
tail -n 20 /opt/deploy-kit/site/shared/logs/deploy.log
tail -n 20 /opt/deploy-kit/site/shared/logs/error.log
curl --max-time 3 -i http://127.0.0.1:8090/health.txt
bash checks/verify.sh
```
日志里应有 `[FAIL] 健康闸门失败` 与期望/实际版本号；修复后重新 `deploy.sh deploy <版本>`。

## §3 卸载

```bash
sudo bash deploy.sh uninstall
```
预期：unit 停止并禁用；`ss -lntp | grep :8090` 无输出；`releases/` 与 `shared/` 原样保留；退出码 0。
重新安装直接再跑 `deploy.sh deploy <版本>`，会重建 unit 与 `current`。

## §4 保留策略

`deploy.env` 的 `KEEP=3` 只用于告警：`checks/verify.sh` 在版本数超限时给 `[WARN]`，不自动删除。
确需清理时，只使用下面这一条（绝对路径、保留当前版本、只删 14 天前的目录）：
```bash
find /opt/deploy-kit/site/releases -mindepth 1 -maxdepth 1 -type d ! -name "$(basename "$(readlink -f /opt/deploy-kit/site/current)")" -mtime +14 -delete
```
除这条命令外，本仓库任何脚本都不做递归删除。
