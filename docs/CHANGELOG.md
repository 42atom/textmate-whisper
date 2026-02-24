# Changelog

- 2026-02-24
  - whisper-voice: 重构脚本公共层与命令入口，减少重复并增强 dry-run 验证与错误处理一致性 (Issue: 0001, Plan: docs/design/plan-260224-opus-refactor-runtime-hardening.md) [risk: medium] [rollback: 回退本次提交并重新执行 scripts/install.sh]
