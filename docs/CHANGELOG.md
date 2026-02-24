# Changelog

- 2026-02-24
  - whisper-voice: 重构脚本公共层与命令入口，减少重复并增强 dry-run 验证与错误处理一致性 (Issue: 0001, Plan: docs/design/plan-260224-opus-refactor-runtime-hardening.md) [risk: medium] [rollback: 回退本次提交并重新执行 scripts/install.sh]
  - fork-build: 新增 TextMate 薄魔改方案资产（mic 权限补丁、构建脚本骨架、研究与计划文档），并在 Xcode 26.2 环境完成真实编译验证 (Issue: 0003, Plan: docs/design/plan-260224-textmate-fork-mic-permission.md) [risk: medium] [rollback: 删除 docs/fork 资产并回退 issue/plan 文档改动]
  - release: 新增 GitHub Release 发布脚本并上线可下载编译产物（zip + sha256），用于分发 fork 构建版 TextMate.app (Issue: 0004, Plan: docs/design/plan-260224-github-release-artifact.md) [risk: medium] [rollback: 删除 release 资产与 tag，保留源码仓库]
  - release-fix: fork 构建版改为独立 Bundle ID（`com.textmatewhisper.TextMate`），规避与官方 TextMate 的权限记录冲突；新增 v0.2.1 产物说明与发布记录 (Issue: 0004, Plan: docs/design/plan-260224-github-release-artifact.md) [risk: low] [rollback: 回退 bundle-id patch 并重新发布资产]
