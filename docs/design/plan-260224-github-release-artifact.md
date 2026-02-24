# GitHub Release 产物发布方案

## Problem
用户需要可直接下载的编译产物（TextMate.app），但当前仓库未配置远端，也没有标准化 release 打包流程。

## Decision
采用“脚本化手动发布”：
- 新增 `scripts/release.sh` 负责 app 压缩、SHA256 生成、GitHub Release 创建/更新与资产上传。
- 产物不入库，只上传到 release assets。
- 先在本地完成首次发布，后续可演进到 GitHub Actions。

## Plan
1. 增加发布脚本
- 文件：`scripts/release.sh`
- 能力：`ditto` 压缩 app、`shasum`、`gh release create/upload`

2. 文档更新
- 文件：`README.md`, `README.zh-CN.md`
- 增加发布步骤、默认路径、覆盖参数说明

3. 仓库与发布
- 创建远端仓库并推送主分支
- 生成 tag（`v0.2.0`）并上传产物

4. 记录与收口
- 更新 issue 证据
- 更新 `docs/CHANGELOG.md`

## Risks
- 风险1：本地未登录 gh 或 token scope 不足
  - 缓解：发布脚本前置 `gh auth status` 检查
  - 回滚：改为手动网页上传
- 风险2：app 路径错误
  - 缓解：脚本默认路径 + `APP_PATH` 可覆盖
  - 回滚：修正路径后重复执行，不影响仓库历史

（章节级）评审意见：[留空,用户将给出反馈]
