---
id: 0001
title: Opus建议落地：去重重构与运行时稳态修复
status: done
owner: agent
labels: [refactor, bug, docs]
risk: medium
scope: Whisper Voice Bundle命令入口、共享脚本库、录音/转写脚本、安装与验证流程
plan_doc: docs/design/plan-260224-opus-refactor-runtime-hardening.md
links: [docs/review-opus.md]
---

## Context
- `docs/review-opus.md` 指出三类核心问题：
  - `voice_input.sh` 与 `record_session.sh` 存在大量重复逻辑。
  - 8个 `.tmCommand` 内联重复 bootstrap 逻辑，维护成本高。
  - 错误提示/退出码行为在不同脚本不一致，存在误报与静默失败风险。
- 近期已修复“短录音误判 0s”，但重构未完全收口，仍有残留重复与潜在回归点。

## Goal / Non-Goals
- Goal
  - 抽取共享库并让主脚本/工具脚本复用。
  - 抽取 tmCommand 公共入口，减少模板重复。
  - 修复配置加载、退出码、dry-run 验证链路等稳定性问题。
- Non-Goals
  - 不改 TextMate 核心行为。
  - 不引入 GUI 常驻面板等超出当前 bundle 边界的能力。

## Plan
- [x] 新增共享库 `_common.sh` 并接入 `voice_input.sh`。
- [x] 完成 `record_session.sh` 对共享库的迁移收尾，移除残留重复逻辑。
- [x] `scripts/list_input_devices.sh` 改为复用共享设备解析逻辑。
- [x] 新增/启用 `bootstrap.sh`，将 8 个 `.tmCommand` 改为薄包装。
- [x] 加入 `voice_input.sh --dry-run` 并在 `scripts/smoke.sh` 执行逻辑路径验证。
- [x] 更新 README/CHANGELOG，补充行为变更说明。
- [x] 运行 `scripts/smoke.sh` + `scripts/install.sh` 完成安装验证。

## Acceptance Criteria
- `voice_input.sh`/`record_session.sh`/`list_input_devices.sh` 不再重复维护设备解析与配置读取实现。
- 所有 `.tmCommand` 使用统一入口 `Support/bin/bootstrap.sh`，且命令可正常执行。
- `scripts/smoke.sh` 在依赖存在时可跑 dry-run 并通过；依赖缺失时给出可读跳过提示。
- 安装后命令工作正常，不出现“命令成功但提示失败”的回归。

## Notes
- 2026-02-24：创建 issue，开始执行 Opus 建议的 P0/P1 改造。
- 2026-02-24：完成以下改动：
  - 抽取并复用 `templates/Support/bin/_common.sh`。
  - 抽取 `templates/Support/bin/bootstrap.sh` 并将 8 个命令模板切换为薄包装。
  - `voice_input.sh` 增加 `--dry-run` 并去除 `trim_text_file` 的 python3 依赖。
  - `record_session.sh` 修复 `load_config_env` 调用并统一成功提示退出码语义。
  - `scripts/list_input_devices.sh` 复用共享设备逻辑。
- 验证证据：
  - `./scripts/smoke.sh` -> `[OK] Static checks passed.` + `[OK] Runtime dry-run passed.`
  - `./scripts/install.sh` -> `[OK] Installed TextMate bundle ...`
  - `./scripts/list_input_devices.sh` -> 正常列出设备并给出 auto 推荐索引。

## Links
- 审阅意见：`docs/review-opus.md`
