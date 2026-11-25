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
预期输出（当前版本，首装）：
```
[OK] 已生成环境文件 /opt/deploy-kit/site/deploy.env
[OK] 已取得部署锁 /opt/deploy-kit/site/.deploy.lock
[OK] precheck: index.html 与 health.txt(20261125) 齐备，未切链
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
本轮实测输出（2026-11-25）：
```
[OK] 已取得部署锁 /opt/deploy-kit/site/.deploy.lock
[OK] precheck: index.html 与 health.txt(20261126) 齐备，未切链
[OK] 20261126 上线成功，current -> releases/20261126
```
升级走 `systemctl reload`，连接不断；`releases/20261125` 保留，`curl http://127.0.0.1:8090/health.txt` 返回 `20261126`。

连接采样（与升级同一轮）：单进程顺序 `curl --max-time 2 -fsS` 100 次，每次间隔 `0.05s`（约 5 秒），不并发；升级在采样开始 0.5 秒后触发，结果 `100 OK / 0 FAIL`。

真实发布包用 `--pkg <目录|tar.gz>`：包内 `public/` 被复制进新版本；切链前预检 `index.html`、`health.txt` 齐备且 `health.txt` 内容等于版本号，不满足则 `precheck failed`、不切链、`exit 2`。

## §3 状态查询

```bash
bash deploy.sh status
```
本轮实测输出（A5 复测与恢复后）：
```
current: 20261128
releases: 4 个
unit: active
health: 20261128
audit: 7 行
```
只读，不触发发布。
