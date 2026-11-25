# 01 部署

## §0 环境准备

```bash
apt-get update -qq
apt-get install -y nginx
nginx -v
```
预期：`nginx version: nginx/1.18.0 (Ubuntu)` 或更高。

系统默认实例会占用 80，本包不使用它，装完停用：
```bash
systemctl stop nginx
systemctl disable nginx
ss -lntp | grep ':80'
```
预期：`systemctl is-active nginx` 为 `inactive`；最后一条无输出（80 无监听）。

部署根由 `deploy.sh` 首次运行自动创建（`/opt/deploy-kit/site`），无需手工 mkdir。

## §1 首装

repo 放在 `/root/deploy-kit`，执行：
```bash
sudo bash deploy.sh deploy 20261125
```
预期输出（2026-11-25 真机）：
```
[OK] 已生成环境文件 /opt/deploy-kit/site/deploy.env
[OK] 已取得部署锁 /opt/deploy-kit/site/.deploy.lock
Created symlink /etc/systemd/system/multi-user.target.wants/deploy-kit-site.service → /etc/systemd/system/deploy-kit-site.service.
[OK] 20261125 上线成功，current -> releases/20261125
```
验证：
```bash
systemctl is-active deploy-kit-site        # active
readlink -f /opt/deploy-kit/site/current   # .../releases/20261125
curl --max-time 3 -fsS http://127.0.0.1:8090/health.txt   # 20261125
bash checks/verify.sh
```
`verify.sh` 预期六行全 `[OK]`，退出码 0：
```
[OK] unit deploy-kit-site: active
[OK] 端口 8090: 已监听
[OK] current: releases/20261125
[OK] health.txt: 返回 20261125
[OK] releases: 1 个（KEEP=3）
[OK] 审计行数: 1
```

## §2 升级

```bash
sudo bash deploy.sh deploy 20261126
```
预期：输出 `[OK] 20261126 上线成功`；`current` 指向新版本，`releases/20261125` 保留；
`curl http://127.0.0.1:8090/health.txt` 返回 `20261126`。
升级走 `systemctl reload`，不断连接；回滚见 `docs/02-rollback.md`。

## §3 状态查询

```bash
bash deploy.sh status
```
预期输出形如：
```
current: 20261126
releases: 2 个
unit: active
health: 20261126
audit: 3 行
```
只读，不触发发布。
