---
id: 0003
title: TextMate 薄魔改 Fork：补齐麦克风权限声明并建立可维护构建链路
status: done
owner: agent
labels: [feature, docs, chore]
risk: medium
scope: TextMate 上游 fork 流程、Info.plist 麦克风权限补丁、构建脚本骨架
plan_doc: docs/design/plan-260224-textmate-fork-mic-permission.md
links: [docs/notes/research-260224-textmate-upstream-mic-permission.md]
---

## Context
- 用户确认采用方案 B：通过 TextMate fork 解决麦克风授权弹窗问题，而不是继续依赖当前官方发行版行为。
- 当前系统现象是 TextMate 未进入系统麦克风授权列表，导致录音命令容易落到静音链路。

## Goal / Non-Goals
- Goal
  - 提供可执行的 fork 最佳实践文档。
  - 提供 `NSMicrophoneUsageDescription` 补丁模板。
  - 提供可复用的构建脚本骨架，支持后续自动化。
- Non-Goals
  - 本次不直接编译并替换用户当前 TextMate.app。
  - 本次不改 TextMate 内核业务逻辑（仅先补权限声明能力）。

## Plan
- [x] 研究上游 TextMate 构建方式与目标路径。
- [x] 形成薄魔改 fork 的决策文档（含回滚策略）。
- [x] 产出 `Info.plist` 麦克风权限补丁模板。
- [x] 产出 build 脚本骨架（支持 clone/apply/build/export）。

## Acceptance Criteria
- 仓库内存在可审查的 Plan 文档，明确方案与权衡。
- 仓库内存在可直接 `git apply` 的补丁模板文件。
- 仓库内存在可执行脚本骨架，且 `bash -n` 语法校验通过。

## Notes
- Evidence
  - Docs：`/tmp/textmate-upstream-inspect/README.md`（`./configure && ninja TextMate/run`，`ninja TextMate`）。
  - Code：`/tmp/textmate-upstream-inspect/Applications/TextMate/Info.plist`（确认当前缺少 `NSMicrophoneUsageDescription`）。
  - Tests：`git -C /tmp/textmate-upstream-inspect apply --check docs/fork/patches/0001-add-nsmicrophoneusagedescription.patch` -> `PATCH_OK`。
  - Logs：
    - `xcodebuild -version` -> `Xcode 26.2 (17C52)`。
    - `./configure` -> `*** dependency missing: ‘capnp’.`（当前首要阻塞是依赖，不是已证实的 Xcode 过高报错）。
    - `ninja TextMate` -> 构建成功，产物路径：`~/build/textmate-whisper-app/release/Applications/TextMate/TextMate.app`。
    - `plutil -extract NSMicrophoneUsageDescription raw ~/Desktop/textmate-whisper-build/TextMate.app/Contents/Info.plist` -> 返回预期文案。
    - `codesign --verify --deep --strict ~/Desktop/textmate-whisper-build/TextMate.app` -> `CODESIGN_OK`。

## Links
- `docs/design/plan-260224-textmate-fork-mic-permission.md`
- `docs/notes/research-260224-textmate-upstream-mic-permission.md`
- `docs/fork/patches/0001-add-nsmicrophoneusagedescription.patch`
- `docs/fork/scripts/build_textmate_whisper_app.sh`
