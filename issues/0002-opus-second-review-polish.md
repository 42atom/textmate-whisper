---
id: 0002
title: 二审建议收尾：bash兼容与设备自动选择逻辑去重
status: done
owner: agent
labels: [refactor, chore]
risk: low
scope: 共享脚本库、设备检测脚本、设置面板脚本、git忽略规则
links: [docs/review-opus-2.md]
---

## Context
- 二审文档 `docs/review-opus-2.md` 提出剩余 P3 优化项。
- 重点是 bash 3.2 兼容性和设备 auto-pick 逻辑重复。

## Goal / Non-Goals
- Goal
  - 修复 `load_config_env` 在旧 bash + `set -u` 的潜在空数组风险。
  - 抽取统一 auto-pick 函数，避免维护两份优先级链。
  - `settings_panel.sh` 统一复用 `_common.sh` 能力。
  - 补 `.gitignore` 的录音/日志忽略规则。
- Non-Goals
  - 不改录音/转写主流程。
  - 不改快捷键与命令语义。

## Plan
- [x] `_common.sh` 修复 `load_config_env` 空 allowed_keys 兼容性。
- [x] `_common.sh` 新增 `auto_pick_audio_device_index()` 并让 `validate_and_resolve_input_device()` 复用。
- [x] `scripts/list_input_devices.sh` 改为调用 `auto_pick_audio_device_index()`。
- [x] `settings_panel.sh` 改为 source `_common.sh` + `safe_source_tm_bash_init` + `show_tip_and_exit`。
- [x] `.gitignore` 增加 `*.wav` 与 `*.log`。
- [x] 执行验证：`smoke`、`install`、`list_input_devices`。

## Acceptance Criteria
- `load_config_env` 支持只传配置文件路径时不触发 `set -u` 风险。
- auto-pick 优先级只维护一份实现。
- settings 面板命令行为正常，提示语由统一出口处理。
- 校验脚本通过并可正常安装 bundle。

## Notes
- 决策（针对 review-opus-2 的 #3 / #4）：
  - #3 `AI Prompt tmCommand` 维持现状：`exit_discard` 属于 TextMate 取消语义，保持在该特殊命令内，避免让 `bootstrap.sh` 耦合单命令 UI 交互逻辑。
  - #4 `resolve_support_dir` 维持 if 链：当前代码更直观，2 行压缩收益不足以抵消可读性损失。
- Tests:
  - `./scripts/smoke.sh` -> `[OK] Static checks passed.` + `[OK] Runtime dry-run passed.`
  - `./scripts/install.sh` -> `[OK] Installed TextMate bundle ...`
  - `./scripts/list_input_devices.sh` -> 设备列表与 auto 推荐索引输出正常。

## Links
- 评审：`docs/review-opus-2.md`
