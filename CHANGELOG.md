# CHANGELOG

格式：Keep a Changelog 精简版；仓库无远端，日期为真实提交日期。

## [Unreleased]
### 待完成
- A3–A6（升级、坏包回滚、指定回滚、并发与非 root）待 Day2。
- A7–A9（卸载、KEEP 告警、文档与链接）待 Day3。

## [0.1.0] - 2026-11-25
### Added
- 14 文件骨架：`deploy.sh` / `rollback.sh` / `common.sh` / `health-gate.sh` / 三份 conf 模板 /
  systemd unit / `verify.sh` / 两份 docs / `preflight.ps1` / README / 本文件。
- 首装链路：flock 串行、幂等判断、模板渲染、`ln -s` + `mv -T` 原子切链、systemd start/reload、
  健康闸门 3×3 秒、失败自动回滚、`shared/audit.log` 留痕。
### Verified
- A1 首装 20261125：unit active、health 返回 20261125、rc=0。
- A2 同版本三连跑：均输出 `already deployed, nothing changed`、rc=0、releases=1、NRestarts 不变。
