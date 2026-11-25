# deploy-kit

## 1. 定位与边界

单机 Web 服务的可重复交付包：一条命令发布静态站点，失败自动回滚，版本可查、可卸载、重跑无副作用。
边界：单机、只发静态站点；不做多机编排、灰度分流、镜像构建，也不接管 `/etc/nginx`。

## 2. 目录结构

| 路径 | 作用 |
| --- | --- |
| [deploy.sh](deploy.sh) | 发布入口：`deploy <版本>` / `status` / `uninstall` |
| [rollback.sh](rollback.sh) | 版本回退：默认上一版，`--to` 指定版本 |
| [scripts/lib/common.sh](scripts/lib/common.sh) | 环境加载、flock、模板渲染、原子切链、审计 |
| [scripts/health-gate.sh](scripts/health-gate.sh) | 健康闸门：3 次 × 3 秒，响应体须含版本号 |
| [conf/deploy.env.example](conf/deploy.env.example) | `APP_ROOT` / `PORT` / `KEEP` / `HEALTH_PATH` 模板 |
| [conf/nginx.conf.template](conf/nginx.conf.template) | 自有 nginx 配置模板（单 server，不 include /etc/nginx） |
| [conf/index.html.template](conf/index.html.template) | 站点首页模板，含 `${VERSION}` `${BUILD_TIME}` |
| [systemd/deploy-kit-site.service](systemd/deploy-kit-site.service) | systemd 托管单元 |
| [checks/verify.sh](checks/verify.sh) | 只读自检 6 行 |
| [docs/01-deploy.md](docs/01-deploy.md) | 环境准备 / 首装 / 升级 / 状态查询 |
| [docs/02-rollback.md](docs/02-rollback.md) | 回滚 / 闸门失败 / 卸载 / 保留策略 |
| [windows/preflight.ps1](windows/preflight.ps1) | Windows 发布前检查（PowerShell 7） |
| [README.md](README.md) | 本文件 |
| [CHANGELOG.md](CHANGELOG.md) | 变更记录 |

## 3. 环境要求

- Ubuntu 22.04 LTS + systemd，root 执行发布。
- nginx ≥ 1.18（`apt install nginx`，本包只用自有 `-c` 配置，系统默认实例需停用）。
- bash 5、coreutils/util-linux（`flock`/`tar`/`find`）、curl、awk/sed/grep。
- 固定部署根 `/opt/deploy-kit/site`；端口固定 8090，不占用 80/443/8080/8081/22。

## 4. 快速开始

首装：
```bash
sudo bash deploy.sh deploy 20261125
curl --max-time 3 -fsS http://127.0.0.1:8090/health.txt
```

升级：把版本号换成新日期，例如 `sudo bash deploy.sh deploy 20261126`，旧版保留在 `releases/`。

回滚：`sudo bash rollback.sh`（默认上一版）或 `sudo bash rollback.sh --to 20261125`。

状态：`bash deploy.sh status`；自检：`bash checks/verify.sh`。

## 5. 目录约定与保留策略

```
/opt/deploy-kit/site/
├ releases/<版本>/conf/nginx.conf      # 该版本渲染后的配置
├ releases/<版本>/public/              # index.html + health.txt
├ current -> releases/<版本>          # 原子切换的软链
├ shared/logs/                          # access/error/deploy 日志
├ shared/audit.log                      # 每次发布/回滚/卸载留痕
└ deploy.env                            # 首次运行从模板复制
```
`KEEP=3` 只告警不自动清理；清理动作只在 `docs/02-rollback.md` §4 给一条绝对路径的 `find ... -delete`。

## 6. 幂等与并发

- 幂等：目标版本目录已存在且 `current` 已指向它时，输出 `already deployed, nothing changed` 并 `exit 0`，不重启 unit。
- 并发：`/opt/deploy-kit/site/.deploy.lock` 上 `flock` 阻塞串行，两个 deploy 不会交叉切链。

## 7. 失败与回滚

发布顺序：渲染 → `nginx -t` → 原子切 `current` → `systemctl start|reload` → 健康闸门。
闸门连续 3 次未通过则自动切回上一版并 `exit 2`，原因写入 `shared/logs/deploy.log`。

| 退出码 | 含义 |
| --- | --- |
| 0 | 成功（含幂等跳过） |
| 1 | 仅 verify.sh 用于「有 WARN」 |
| 2 | 健康闸门失败 / 配置校验失败 |
| 64 | 参数错误或非 root |
| 65 | 回滚目标不存在 / 无上一版 |

## 8. 验收对照表

| 项 | 场景 | 状态 |
| --- | --- | --- |
| A1 | 首装 20261125，health 返回版本 | Day1 已通过 |
| A2 | 同版本三连跑幂等，NRestarts 不变 | Day1 已通过 |
| A3-A6 | 升级 / 坏包回滚 / 指定回滚 / 并发与非 root | 待 Day2 |
| A7-A9 | 卸载 / KEEP 告警 / 文档与链接 | 待 Day3 |

## 9. 已知限制

- 单机，无多机编排与灰度；只发静态文件，不做镜像构建。
- `KEEP` 超限只告警，不自动删除版本。
- 依赖 systemd 与 root；非 root 直接 `exit 64`。
- 系统自带 nginx 的 `/etc/nginx` 不参与本包，安装后需停用默认实例（见 docs/01 §0）。

## 10. 变更记录

版本与修复项见 [CHANGELOG.md](CHANGELOG.md)；当前为 Day1 骨架 + 首装链路。
