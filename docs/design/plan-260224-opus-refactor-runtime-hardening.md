# Opus建议落地：Whisper Voice 去重重构与运行时稳态修复

## Problem
当前 Bundle 存在明显结构重复（脚本层与 tmCommand 层），导致一处 bug 需要多处同步修复，且退出码/提示语义不一致，增加回归概率。最近短录音问题虽已修复，但整体架构仍需收口，保证后续迭代成本可控。

## Alternatives
1. 维持现状，仅补丁式修 bug
- 优点：改动小、见效快
- 缺点：重复持续累积，后续每次修复都可能漏改

2. 提取共享库 + 统一 bootstrap（推荐）
- 优点：降低重复代码，统一错误处理与环境初始化，便于测试
- 缺点：一次性修改面较大，需要回归验证

## Decision
选择方案 2：
- 抽取 `templates/Support/bin/_common.sh` 作为共享能力层。
- 抽取 `templates/Support/bin/bootstrap.sh` 作为 tmCommand 统一入口。
- 为 `voice_input.sh` 增加 `--dry-run`，将 smoke 从“语法校验”提升到“逻辑路径校验”。

关键权衡：
- 以可维护性和一致性优先，接受一次性中等规模改动；通过可回滚安装包与 smoke 验证控制风险。

## Plan
1. 脚本去重与行为统一
- 文件：`templates/Support/bin/voice_input.sh`
- 文件：`templates/Support/bin/record_session.sh`
- 文件：`templates/Support/bin/_common.sh`
- 目标：统一配置加载、设备解析、提示/退出策略。

2. 命令入口统一
- 文件：`templates/Support/bin/bootstrap.sh`
- 文件：`templates/Commands/*.tmCommand`
- 目标：将 8 个命令模板替换为薄包装调用。

3. 工具脚本复用
- 文件：`scripts/list_input_devices.sh`
- 目标：复用 `_common.sh` 的设备解析逻辑，避免第三份实现。

4. 验证链路增强
- 文件：`scripts/smoke.sh`
- 目标：新增 dry-run 逻辑测试（依赖存在时执行）。

5. 文档与发布记录
- 文件：`README.md`
- 文件：`README.zh-CN.md`
- 文件：`docs/CHANGELOG.md`
- 目标：记录重构后行为与命令结构。

## Risks
- 风险1：tmCommand 环境变量差异导致 bootstrap 定位失败。
  - 缓解：bootstrap 内保留 `TM_BUNDLE_SUPPORT/TM_BUNDLE_PATH/默认路径` 三段回退。
- 风险2：退出码统一后影响 TextMate tooltip 展示语义。
  - 缓解：将成功提示显式传 `non_tm_exit_code=0`；错误保持非零。
- 风险3：dry-run 误触硬件依赖。
  - 缓解：dry-run 路径不打开麦克风；smoke 在依赖缺失时跳过逻辑校验并给出提示。

回滚策略：
- 通过 `git checkout` 回退本次改动；运行 `scripts/install.sh` 重装上一个可用 bundle。

## Migration / Rollout
- 直接替换用户 bundle 文件（已有 `scripts/install.sh` 备份旧版本）。
- 用户侧执行：Reload Bundles 或重启 TextMate。

## Test Plan
- 本地命令：
  - `./scripts/smoke.sh`
  - `./scripts/install.sh`
- TextMate 手测：
  - Start Recording / Stop Recording + Insert
  - Insert + AI Prompt
  - Settings / Local Model Setup Guide

## Observability
- 关键日志：
  - `~/.cache/textmate-whisper/logs/voice_input-YYYYMMDD.log`
  - `~/.cache/textmate-whisper/logs/record_session-YYYYMMDD.log`

## 评审意见
[留空,用户将给出反馈]
