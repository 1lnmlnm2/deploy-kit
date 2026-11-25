# CHANGELOG

格式：Keep a Changelog 精简版；仓库无远端，日期为真实提交日期。

## [Unreleased]
### 待完成
- A7–A9（卸载、KEEP 告警、文档与链接）待 Day3。

## [0.2.0] - 2026-11-25
### Changed
- nginx `pid` 改用 `${APP_ROOT}/shared/nginx.pid`；unit `ExecReload` 显式带 `-c current/conf/nginx.conf`，不再依赖 `/etc/nginx`。
- 切链后的 `systemctl reload/start` 失败捕获并进入回滚分支；首版失败无上一版则 `disable --now`、移除 `current`、`exit 2`。
- `deploy.sh` 新增可选 `--pkg <目录|tar.gz>`；切链前预检 `index.html` / `health.txt` 齐备且版本一致。
- 切链后闸门扩为三项：8090 监听、`/health.txt` 含版本、`GET /` 200 且含版本；3 次、间隔 2 秒。
- 发布成功后 releases 超 `KEEP` 只打印 `[WARN]` 与超期版本，不自动删除。
### Verified
- A3 升级 20261126：`rc=0`，旧版保留；同轮 100 次顺序 curl（间隔 0.05s、不并发）`100 OK / 0 FAIL`。
- A4 旧首页包 20261127：预检通过、闸门第③项失败、自动回滚 20261126、`rc=2`，日志写明原因。
- A5 `rollback.sh --to 20261125`：`rc=0`；重跑输出 `already on version 20261125, nothing changed`、`rc=0`。
- A6 非 root `rc=64`；两进程并发同一版本，后到者阻塞等锁，最终只产生 1 个版本目录、两者均 `rc=0`。

## [0.1.0] - 2026-11-25
### Added
- 14 文件骨架：`deploy.sh` / `rollback.sh` / `common.sh` / `health-gate.sh` / 三份 conf 模板 /
  systemd unit / `verify.sh` / 两份 docs / `preflight.ps1` / README / 本文件。
- 首装链路：flock 串行、幂等判断、模板渲染、`ln -s` + `mv -T` 原子切链、systemd start/reload、
  健康闸门 3×3 秒、失败自动回滚、`shared/audit.log` 留痕。
### Verified
- A1 首装 20261125：unit active、health 返回 20261125、rc=0。
- A2 同版本三连跑：均输出 `already deployed, nothing changed`、rc=0、releases=1、NRestarts 不变。
