# textmate-whisper 二审

## 一审问题跟踪

| 一审项 | 状态 | 备注 |
|---|---|---|
| P0 提取 [_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh) | ✅ 已修 | 246 行，干净完整 |
| P1 提取 [bootstrap.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/bootstrap.sh) | ✅ 已修 | tmCommand 从 ~50 行内联 → 3 行 |
| P1 统一 [show_tip_and_exit](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#30-51) | ✅ 已修 | 第二参数 `non_tm_exit_code`，默认 `1` |
| P2 [trim_text_file](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/voice_input.sh#38-46) 去 python3 | ✅ 已修 | 纯 bash [tr](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#133-145) + parameter expansion |
| P2 smoke.sh 加 dry-run | ✅ 已修 | 条件执行 `--dry-run` |
| P3 [.gitignore](file:///Users/admin/GitProjects/textmate-whisper/.gitignore) | 🟡 部分 | 加了 `*.bak-*`，但没加 `*.wav` / `*.log` |

## 额外改进（一审没提，你自己加的）

做得好：

1. **输入设备 fallback**：指定设备失败时自动回退 `auto`，韧性更强
2. **[wait_for_file_stable()](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh#144-167)**：等文件写入稳定再读大小，解决 ffmpeg 异步写入的竞态
3. **kill 三步升级**：`SIGINT` → `SIGTERM` → `SIGKILL`，比原来的两步更健壮
4. **[audio_duration_seconds()](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/record_session.sh#117-143) ffprobe fallback**：ffprobe 不可用时用 WAV 文件大小估算时长，附带精确的采样率公式
5. **[safe_source_tm_bash_init()](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#5-14)**：`set +e` 后加载 `bash_init.sh`，解决了 TextMate 内部脚本与 `set -e` 不兼容的实际问题
6. **[load_config_env](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#98-132) 参数化白名单**：从硬编码 `case` 变成调用方传参，[_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh) 不再耦合业务 key

---

## 二审发现

### 1. [settings_panel.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/settings_panel.sh) 没用 [_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh)

[settings_panel.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/settings_panel.sh) 仍然自己手写 [bash_init](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#5-14) 加载（L4-10），也没有用 [show_tip_and_exit](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#30-51)——虽然它只做"打开文件 + 显示提示"这一件事，但既然 [_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh) 已经有了 [safe_source_tm_bash_init](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#5-14)，不 source 它反而显得不一致。

不过它的逻辑足够简单，是否并入不影响大局。放不放看你偏好。

### 2. [list_input_devices.sh](file:///Users/admin/GitProjects/textmate-whisper/scripts/list_input_devices.sh) 的 auto-pick 逻辑又写了一份

[list_input_devices.sh L27-35](file:///Users/admin/GitProjects/textmate-whisper/scripts/list_input_devices.sh#L27-L35) 的 auto-pick 链（headset → built-in → iphone → first）是 [_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh) 里 [validate_and_resolve_input_device()](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh#197-246) 的子集复制。

这个可以提一个小函数 `auto_pick_device()` 到 [_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh)，让两处都调它。不急，但目前改其中一处的优先级列表时，另一处容易忘改。

### 3. `AI Prompt` tmCommand 里的 `exit_discard` 保护

[AI Prompt tmCommand L24-33](file:///Users/admin/GitProjects/textmate-whisper/templates/Commands/Voice%20Dictation%20-%20Insert%20+%20AI%20Prompt....tmCommand#L24-L33) 里手动加载 `bash_init.sh` 只是为了拿 `exit_discard` 函数。这段代码写在 tmCommand 内联 bash 里，是唯一一个比 3 行长的 tmCommand。

有两个思路简化（都不紧急）：
- **A**：把 `exit_discard` 的调用逻辑移进 [bootstrap.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/bootstrap.sh)，给它一个 `--cancel-if-empty-stdin` 之类的 flag
- **B**：直接 `exit 200` 让 TextMate 忽略空输出（如果 outputLocation=atCaret 对空字符串无副作用的话）

当前的写法也能工作，只是视觉上是"8 个 tmCommand 很统一……但有 1 个特殊"。

### 4. [bootstrap.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/bootstrap.sh) 里的 [resolve_support_dir()](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/bootstrap.sh#10-21) 可以更短

```bash
resolve_support_dir() {
  printf '%s\n' "${TM_BUNDLE_SUPPORT:-${TM_BUNDLE_PATH:+$TM_BUNDLE_PATH/Support}}"
}
```

用 `${var:+expr}` 合并前两个 if 分支。末尾 fallback 不一定需要——如果 `TM_BUNDLE_SUPPORT` 和 `TM_BUNDLE_PATH` 都没设，说明不在 TextMate 内运行，这时 tmCommand 内联 bash 已经提供了 hardcoded 路径传给 [bootstrap.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/bootstrap.sh)。所以 [resolve_support_dir](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/bootstrap.sh#10-21) 根本不需要 fallback 分支。

但这个属于"1 行级"优化，不影响正确性。

### 5. 一个微妙的正确性问题

[_common.sh](file:///Users/admin/GitProjects/textmate-whisper/templates/Support/bin/_common.sh) L116：

```bash
if ((${#allowed_keys[@]} > 0)); then
```

如果调用方传了零个 allowed key：`load_config_env "path"`（不带后续参数），`allowed_keys` 会是空数组。在 `set -u` 下，`${#allowed_keys[@]}` 访问空数组在 bash 4.3 以下会触发 "unbound variable" 错误。macOS 自带 bash 是 3.2。

你实际使用中不存在这种调用（每次都传了 key），所以当前不会触发。但如果将来有人意外省略 key 参数，`set -u` 会炸。

防护方式：

```bash
local allowed_keys=()
if [[ $# -gt 0 ]]; then
  allowed_keys=("$@")
fi
```
或者在检查时用 `${allowed_keys[@]+"${allowed_keys[@]}"}` 来兼容旧版 bash。

---

## 结论

重构干得漂亮。核心结构性问题全部解决，额外加的几个防御性改进（设备 fallback、文件稳定等待、kill 升级）都体现了生产意识。

**剩余的都是 P3 级别的打磨**，不做也完全不影响功能和可维护性。值得做的话，按优先级就是：#5（bash 3.2 兼容）> #2（auto-pick 微提取）> 其余。
