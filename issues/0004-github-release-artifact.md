---
id: 0004
title: 发布可下载编译产物到 GitHub Release
status: done
owner: agent
labels: [chore, docs, release]
risk: medium
scope: 仓库远端初始化、release 打包脚本、GitHub Release 资产上传
plan_doc: docs/design/plan-260224-github-release-artifact.md
links: [https://github.com/42atom/textmate-whisper/releases/tag/v0.2.0, https://github.com/42atom/textmate-whisper/releases/tag/v0.2.1]
---

## Context
- 用户要求将编译产物推送到 GitHub，方便下载。
- 当前本地仓库无任何 git remote，需要先建立 GitHub 仓库与发布流程。

## Goal / Non-Goals
- Goal
  - 提供可重复执行的一键发布脚本。
  - 创建 GitHub 仓库并推送代码。
  - 上传已编译 `TextMate.app` 压缩包与校验文件到 release。
- Non-Goals
  - 不在 git 仓库中直接提交二进制 app。
  - 不实现 CI 自动发布（本次先手动脚本发布）。

## Plan
- [x] 新增 `scripts/release.sh` 实现打包 + 发布逻辑。
- [x] 更新中英文 README 发布说明。
- [x] 创建 GitHub 远端并推送主分支。
- [x] 创建 release 标签并上传构建产物。
- [x] 回填 issue 证据并标记 done。

## Acceptance Criteria
- `scripts/release.sh` 可执行并通过语法检查。
- GitHub 仓库存在且可访问。
- Release 页面可下载 zip 和 sha256。

## Notes
- Evidence
  - Tests：`./scripts/smoke.sh` -> `[OK] Static checks passed.` + `[OK] Runtime dry-run passed.`
  - Logs：
    - `gh repo create 42atom/textmate-whisper --public --source=. --remote=origin --push` 成功
    - `TAG=v0.2.0 REPO=42atom/textmate-whisper NOTES_FILE=docs/release-notes/v0.2.0.md ./scripts/release.sh` 成功
  - Links：
    - Release: `https://github.com/42atom/textmate-whisper/releases/tag/v0.2.0`
    - Release: `https://github.com/42atom/textmate-whisper/releases/tag/v0.2.1`

## Links
- `scripts/release.sh`
- `docs/design/plan-260224-github-release-artifact.md`
