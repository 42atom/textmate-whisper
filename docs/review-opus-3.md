# textmate-whisper 终审：开源发布质量审查

## 审查范围

| 类别 | 文件数 | 总行数 |
|---|---|---|
| `Support/bin/*.sh` | 8 | ~1,740 |
| `Commands/*.tmCommand` | 6 | ~212 |
| `scripts/*.sh` | 5 | ~296 |
| [info.plist](file:///Users/admin/GitProjects/textmate-whisper/templates/info.plist) | 1 | 26 |
| **合计** | **20** | **~2,274** |

---

## 一、结构完整性 ✅

### UUID 一致性
[info.plist](file:///Users/admin/GitProjects/textmate-whisper/templates/info.plist) 中 6 个 UUID 与所有 tmCommand 文件一一对应，无遗漏、无悬空。

### 函数使用率
[_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh) 全部 15 个函数均被引用，**无死代码**：

| 函数 | 被使用文件数 |
|---|---|
| [safe_source_tm_bash_init](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#5-14) | 7 |
| [show_tip_and_exit](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#30-58) | 7 |
| [load_config_env](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#105-142) | 5 |
| [resolve_bin](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#59-85) | 5 |
| [list_audio_devices](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#186-200) | 4 |
| [auto_pick_audio_device_index](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#207-224) | 3 |
| [validate_and_resolve_input_device](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#225-265) | 3 |
| [is_truthy](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#143-155) | 3 |
| [status_notify](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#156-178) | 3 |
| [append_log](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#15-22) | 3 |
| [pick_audio_device_index](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#201-206) | 3 |
| [is_textmate_context](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#23-29) | 1 (被 [show_tip_and_exit](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#30-58) 调用) |
| [trim_inline_space](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#86-91) | 1 (被 [load_config_env](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#105-142) 调用) |
| [strip_wrapping_quotes](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#92-104) | 1 (被 [load_config_env](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#105-142) 调用) |
| [list_audio_devices_raw](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#179-185) | 1 (被 [list_audio_devices](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#186-200) 调用) |

### tmCommand 统一性
全部 6 个 tmCommand 内联 bash 均为 3 行 bootstrap 模式，无例外。

### 脚本统一性
全部 8 个 `Support/bin/*.sh` 均 source [_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh) 并调 [safe_source_tm_bash_init](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#5-14)。

---

## 二、发现

### P1 — 应修

#### 1. `keyEquivalent` 编码问题（三审未修）

[Toggle Recording L19](file:///Users/admin/GitProjects/textmate-whisper/templates/Commands/Voice%20Dictation%20-%20Toggle%20Recording.tmCommand#L19) 和 [Stop Recording L19](file:///Users/admin/GitProjects/textmate-whisper/templates/Commands/Voice%20Dictation%20-%20Stop%20Recording.tmCommand#L19) 的 `keyEquivalent` 值均为 `~@`，后面没有 F1/F2 键字符。

README、[install.sh](file:///Users/admin/GitProjects/textmate-whisper/scripts/install.sh)、[local_setup_guide.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/local_setup_guide.sh) 里都写的是 `Option+Command+F1 / F2`，但 plist 里没有对应的 Unicode 编码。**如果快捷键实际生效（通过 TextMate Bundle Editor 手动绑定的），那可能是 plist 里的值被 TextMate 内部覆盖了，但仓库里的模板不包含正确值——新用户 install 后不会有快捷键。**

TextMate 功能键 Unicode：F1=`\U00F704`，F2=`\U00F705`。

#### 2. [wait_for_file_stable](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh#315-338) / [wait_for_input_file_stable](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/voice_input.sh#51-74) 重复

[voice_input.sh L51-73](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/voice_input.sh#L51-L73) 定义了 [wait_for_input_file_stable()](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/voice_input.sh#51-74)。
[record_session.sh L315-337](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh#L315-L337) 定义了 [wait_for_file_stable()](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh#315-338)。

两者逻辑完全相同（只是函数名不同），应该提取到 [_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh)。

#### 3. [request_mic_permission.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/request_mic_permission.sh) 里的 `killall tccd`

[request_mic_permission.sh L12](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/request_mic_permission.sh#L12):
```bash
/usr/bin/killall tccd >/dev/null 2>&1 || true
```

对于开源项目，杀系统级 daemon (`tccd`) 会让用户不安。虽然 macOS 会自动重启它，但：
- 某些企业 MDM 环境可能不允许
- 文档里没有解释为什么要这样做
- 如果 `tccutil reset` 本身就够了，这行可以去掉

建议至少加注释，或改成 README 里的手动步骤指引。

---

### P2 — 建议修

#### 4. `POSTPROCESS_MODE` 的 `*` fallthrough（二审提过）

[voice_input.sh L533-537](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/voice_input.sh#L533-L537) 的 `*` 分支和 L528-531 的 `auto|""` 行为重复。加一行 `append_log "WARN" "unknown postprocess mode: $POSTPROCESS_MODE, treating as auto"` 即可。

#### 5. [record_session.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh) 里的窗口 helper 函数可提取

[strip_window_indicator_prefix](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh#33-49)、[set_window_name_by_id](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh#97-130)、[set_window_indicator](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh#131-149)、[capture_front_window_meta](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh#50-65) 等 ~90 行窗口操作代码只有 [record_session.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh) 使用，但如果将来 [voice_input.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/voice_input.sh) 也要显示窗口状态（比如直接录音模式），就得复制。可以考虑提到一个 `_window.sh` helper。不急。

#### 6. [toggle_postprocess.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/toggle_postprocess.sh) UUID 复用了旧 Preview Draft

UUID `591D4397-1448-4E42-B78E-30332E8FADB2` 原来是 Preview Draft 命令的，现在给了 Toggle AI Postprocess。功能上没问题（旧命令已删），但如果有用户从旧版升级，TextMate 会把这个 UUID 的用户自定义绑定（如果有的话）迁移到新命令上。这通常是期望行为，但值得在 CHANGELOG 里提一句。

---

### P3 — 可选

#### 7. [local_setup_guide.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/local_setup_guide.sh) 不用 [_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh)

它只是个 `cat <<GUIDE` 脚本（89 行），不需要任何 helper 函数。但它也没 source [_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh)——唯一一个没有这样做的脚本。如果将来加错误处理会忘记 source。不过作为一个纯输出脚本，保持简单也没问题。

#### 8. `dist/` 目录包含 18MB×2 的 release zip

[.gitignore](file:///Users/admin/GitProjects/textmate-whisper/.gitignore) 有 `dist/`，所以不会上传。已确认。

#### 9. `docs/` 和 `issues/` 是内部开发文档

[docs/review-opus.md](file:///Users/admin/GitProjects/textmate-whisper/docs/review-opus.md)、[docs/review-opus-2.md](file:///Users/admin/GitProjects/textmate-whisper/docs/review-opus-2.md)、`issues/0001-*.md` 等是你的内部开发追踪文档。开源发布时考虑是否要包含——它们暴露了开发过程中的 debug 细节和你的个人配置路径。如果你觉得这是项目历史的一部分就留着，如果觉得不合适加到 [.gitignore](file:///Users/admin/GitProjects/textmate-whisper/.gitignore)。

---

## 三、亮点

自上次审阅以来新增的值得肯定的设计：

1. **录音闪烁动画**（[start_recording_blink_loop](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh#226-263)）：🔴⚪ 交替，后台子进程驱动，状态文件驱动退出。细节到位。
2. **转写进程锁**（`mkdir`-based lock）：避免多次快速按键导致并发 whisper 推理崩溃。
3. **CPU fallback**（`MLX_USE_GPU=0`）：Metal crash 时自动降级 CPU 推理，配合 `TM_WHISPER_RETRY_CPU_ON_CRASH` 配置项。
4. **Debug artifact 持久化**（[persist_debug_artifacts](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/voice_input.sh#103-126) + [write_runtime_snapshot](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/voice_input.sh#75-102)）：失败时自动保存 stderr、stdout、环境变量快照到 session 目录，极大降低远程 debug 门槛。
5. **[ensure_bin_dir_in_path](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/voice_input.sh#280-290)**：解决 TextMate 运行时 PATH 缺少 Homebrew bin 导致 mlx_whisper 内部找不到 ffmpeg 的问题。
6. **窗口错误标记**（`❌ ERR=xxx |`）：失败时窗口标题明确标记错误类型，用户不用翻 log 就知道怎么了。

---

## 四、结论

| 维度 | 评价 |
|---|---|
| 架构 | ✅ 分层清晰：[_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh) → [bootstrap.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/bootstrap.sh) → 业务脚本 |
| 代码质量 | ✅ 无死代码，函数全部引用，error handling 完善 |
| 用户体验 | ✅ 一键录音、自动模式、窗口状态指示、丰富的错误提示 |
| 可维护性 | ✅ 统一 bootstrap、config 白名单、日志标准化 |
| 防御性 | ✅ 文件稳定等待、重封装、CPU fallback、进程锁、debug 快照 |
| 开源就绪 | 🟡 P1 #1（keyEquivalent）需确认，#3（killall tccd）需评估 |

**可以发布。** P1 #1 和 #3 建议发布前确认一下。其余都是打磨级别的优化。
