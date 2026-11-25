# 01 部署

## §0 环境准备

```bash
apt-get update -qq
apt-get install -y nginx
nginx -v
```

本轮实跑（2026-11-25）：`apt-get update rc=0`；`apt-get install` 为 `0 upgraded, 0 newly installed, 0 to remove`，rc=0；`nginx -v` 输出
`nginx version: nginx/1.18.0 (Ubuntu)`。

系统默认实例会占用 80，本包不使用它，装完停用：
```bash
systemctl stop nginx
systemctl disable nginx
ss -lntp | grep -E ':(80|443) '
```
本轮实跑：`systemctl is-active nginx` 为 `inactive`，`systemctl is-enabled nginx` 为 `disabled`；
最后一条无输出，表示 80/443 无监听。（现场 Docker 的 8080 与本包无关。）

部署根由 `deploy.sh` 首次运行自动创建（`/opt/deploy-kit/site`），无需手工 mkdir。

## §1 首装

repo 放在 `/root/deploy-kit`，执行：
```bash
sudo bash deploy.sh deploy 20261125
```
首装当时输出（Day1 真机）：
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
首装时 `verify.sh` 六行全 `[OK]`，退出码 0：
```
[OK] unit deploy-kit-site: active
[OK] 端口 8090: 已监听
[OK] current: releases/20261125
[OK] health.txt: 返回 20261125
[OK] releases: 成功 1 个（KEEP=3）
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

连接采样（与升级同一轮）：单进程顺序 `curl --max-time 2 -fsS` 100 次，每次间隔 `0.05s`（约 5 秒），不并发；升级在采样开始 0.5 秒后触发，结果 `100 OK / 0 FAIL`。该采样只能证明没有硬中断，不能证明零丢包，未做并发压测。

真实发布包用 `--pkg <目录|tar.gz>`：包内 `public/` 被复制进新版本；切链前预检 `index.html`、`health.txt` 齐备且 `health.txt` 内容等于版本号，不满足则 `precheck failed`、不切链、`exit 2`。tar.gz 先解到 `mktemp -d` 临时目录，只复制其中 `public/`；**归档根必须直接含 `public/`，不做剥层**。

## §3 状态查询

```bash
bash deploy.sh status
```
本轮最终实测输出（A9 收尾）：
```
current: 20261128
releases: 成功 5 个（KEEP=3）
failed: 2 个（保留现场）: 20261127,20261129
unit: active
health: 20261128
audit: 16 行
```
只读，不触发发布。
