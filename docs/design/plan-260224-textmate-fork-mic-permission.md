# TextMate Fork 薄魔改方案：麦克风权限声明与可维护构建链路

## Problem
官方 TextMate 发行版在当前环境下未进入系统麦克风授权列表，导致语音录制功能无法稳定触发权限弹窗，进而出现静音录音。插件侧无法绕过 macOS TCC 授权边界，需在 App 层补齐权限声明并采用自维护构建链路。

## Decision
采用“薄魔改 fork”策略：
- Fork `textmate/textmate` 到独立仓库（建议：`textmate-whisper-app`）。
- 首个补丁仅修改 `Applications/TextMate/Info.plist`，增加 `NSMicrophoneUsageDescription`。
- 保持 patchset 极小，定期从上游 rebase，同步冲突最小化。

核心理由：
- 能从根因层面解决权限弹窗缺失问题。
- 维护成本显著低于长期大规模魔改。
- 可与现有 `textmate-whisper` 插件仓库解耦。

## Alternatives
1. 继续仅改插件脚本，不 fork App  
- 优点：短期改动少。  
- 缺点：无法突破 TCC 授权边界，问题不可根治。

2. 新建独立 Recorder Helper.app（不改 TextMate）  
- 优点：权限归属清晰、可控。  
- 缺点：多一个 app 生命周期与分发维护面。

## Plan
- [ ] 创建 `textmate-whisper-app` fork，并配置 `upstream` 远端。
- [ ] 应用补丁：`docs/fork/patches/0001-add-nsmicrophoneusagedescription.patch`。
- [ ] 运行构建脚本骨架：`docs/fork/scripts/build_textmate_whisper_app.sh`。
- [ ] 产出测试包并验证首次录音时是否弹出麦克风授权。
- [ ] 记录验证结果（包含 macOS、Xcode、依赖版本）。

涉及文件/接口：
- `Applications/TextMate/Info.plist`（fork 仓库）
- `docs/fork/patches/0001-add-nsmicrophoneusagedescription.patch`
- `docs/fork/scripts/build_textmate_whisper_app.sh`

## Risks
1. 上游变更导致补丁冲突  
- 缓解：保持单一补丁，使用 `git am --3way`；冲突后只在 Info.plist 级别修复。  
- 回滚：`git reset --hard upstream/master` 后重新应用补丁。

2. Xcode 新版本行为变化（用户环境：Xcode 26.2）  
- 缓解：脚本加入 Xcode 版本软告警与依赖检查，不做硬阻断。  
- 回滚：切换到已验证 toolchain 或在 CI 固定 runner。

3. 构建依赖缺失导致失败  
- 缓解：脚本前置检查 `boost/capnp/google-sparsehash/multimarkdown/ninja/ragel`。  
- 回滚：不替换当前生产 TextMate，先补齐依赖后再构建。

## Migration / Rollout
- 开发机先手工验证构建产物。
- 验证通过后再考虑发布内部二进制（附源码与补丁，遵守 GPL 要求）。
- 不直接覆盖系统现有 TextMate，先并行安装测试。

## Test Plan
- 构建测试：
  - `./configure`
  - `ninja TextMate`
- 运行测试：
  - 启动 fork 产物，执行语音录制命令，确认出现系统麦克风弹窗。
- 功能测试：
  - 录制 3~5 秒语音，确认非静音并可转写。

## Observability
- 记录构建日志：`build_textmate_whisper_app.sh` 输出。
- 记录运行日志：`~/.cache/textmate-whisper/logs/record_session-YYYYMMDD.log`。

（章节级）评审意见：[留空,用户将给出反馈]
