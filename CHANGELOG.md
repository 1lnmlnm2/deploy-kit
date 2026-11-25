# CHANGELOG

格式：Keep a Changelog 精简版；仓库无远端，日期为真实提交日期。

## [Unreleased]
（无）

## [0.3.0] - 2026-11-25
### Changed
- tar.gz 包改为先解到 `mktemp -d` 临时目录，只 `cp -a` 其中的 `public/` 进 release；临时目录在 `/tmp` 下由 `mktemp` 产生并清理，禁止直解进 release。
- 发布结果增加标记：成功写 `releases/<版本>/.deployed`（含时间），失败写 `.deploy-failed`（一行原因）；失败目录保留现场。
- `release_list` 拆为成功版本与失败版本；`KEEP`、`verify.sh`、`status` 只统计成功版本；失败版本另行列示且不改变 verify 退出码。
- `KEEP` 超限告警按成功版本计数；失败版本不占保留名额。
- `uninstall` 保留 unit 文件并保持 `disabled`，不再删除 unit 文件，便于 `systemctl is-enabled` 验证。

### Verified
- A7 卸载：`rc=0`，`is-active=inactive`、`is-enabled=disabled`、8090 无监听，releases/shared 保留；随即重新部署 20261128，`verify rc=0`。
- A8：成功版本 20261130 为第 4 个时告警 `20261125`，20261201 为第 5 个时告警 `20261125,20261126`；均未删除，A8 时点成功 5 + 失败 1。
- 改 C：20261129 目录包缺 `public/health.txt`，输出 `precheck failed`、未切链、`current` 保持 20261128、`rc=2`，留下 `.deploy-failed`。
- A9：docs 命令实跑并回填；PORT 在 `deploy.env.example`、nginx 模板、验收命令三处一致为 8090；README 14 条相对链接全部命中。

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
