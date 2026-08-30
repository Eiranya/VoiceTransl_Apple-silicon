# VoiceTransl（聆译）macOS 版构建报告

**日期**：2026-08-30 ｜ **平台**：macOS 26（Apple Silicon，Apple M5）｜ **基线**：v1.20 源码 + ASR 引擎重构 + ggml/canary 清除
**本轮目标**：① 弃用 openai-whisper；② Qwen3-ASR-1.7B 默认引擎 + faster-whisper 可选引擎；③ 模型目录核对；④ 日语优化；⑤ 三语实测（准确率/RTF/内存）；⑥ 产出 .app 与 .dmg；⑦ **删除 ggml/canary 模型并对照截图修改 UI**

---

## 0. 结论摘要

| 项目 | 状态 |
|---|---|
| Qwen3-ASR-1.7B（Metal GPU，唯一引擎） | ✅ 已实现并实测（约 4.2 倍实时，ja CER 0~1.8%） |
| faster-whisper | ❌ **第 3 轮已彻底删除**（macOS 官方轮子无 Metal/MPS，仅 CPU；详见 §12.1 调研结论） |
| openai-whisper | ✅ 全仓库 0 处引用，无需删除（详见 §2） |
| ggml (whisper.cpp) 完全清除 | ✅ 第 2 轮：模型文件 + 代码 8 处 + spec + bundle 验证（详见 §11） |
| faster-whisper 彻底删除 | ✅ 第 3 轮：模型 2.9GB + worker + 代码 9 处 + spec + requirements（详见 §12.2） |
| canary CTC 对齐器 | ✅ 第 3 轮**已恢复**：`-am` + `-sp` 重新启用，句子级时间戳精确；模型下拉框已过滤避免误选（详见 §12.3） |
| 日语优化 | ✅ prompt/断句/对齐/促音长音片假名实测通过 |
| PyInstaller 产物 | ✅ 第 3 轮仅产出 `.app`（3.7GB），**不产出 dmg**（用户要求）；见 §12.4 |

---

## 1. 问题修复清单（问题 → 根因 → 修复）

| # | 问题 | 根因 | 修复方式 | 状态 |
|---|---|---|---|---|
| 1 | v1.20 官方 .app 双击闪退 | Gatekeeper `com.apple.quarantine` 隔离 + ad-hoc 签名多可执行文件逐一拦截 | `xattr -r -d com.apple.quarantine` + `codesign --force --deep --sign -` | ✅（前轮） |
| 2 | whisper.cpp 转写时进程崩溃（`ggml_metal_library_init_from_source: error`） | 官方 .app 内置 whisper-cli 的 Metal 库与运行时环境不匹配 | 从源码重编 whisper.cpp v1.9.3（`-DWHISPER_COREML=OFF`，Metal 后端自动探测成功），实测 `use gpu = 1`、2.46 倍提速 | ✅（前轮；**第 2 轮已完全删除** ggml 模型/代码/文件，见 §11） |
| 3 | `whisper-faster/` 目录为空、param.txt 硬编码 Windows `.exe`（Purfview Faster-Whisper-XXL 无 macOS 版） | 上游仅有 Windows 预编译 | 本轮以 `asr_worker.py`（faster-whisper 1.2.1/ctranslate2）替代该闭源 exe，参数模板重写为 macOS 版 | ✅（本轮） |
| 4 | 用户提供的 GGUF 无法被 llama.cpp 加载 | 官方 llama.cpp master 尚无 `qwen3asr` 架构（只有 QWEN3/QWEN3VL/QWEN3TTS 等）；v0.3.0 亦无 macOS 产物 | 改用 **CrispASR v0.8.30**（VoiceTransl v1.30 上游同款引擎，cstr 量化仓库的官方运行时），`--backend qwen3` 直接加载 | ✅（本轮） |
| 5 | `-sp` 断句导致 SRT 时间戳全为 0 | qwen3 后端按标点重切文本时丢失时间信息 | 加 CTC 强制对齐器：`-am canary-ctc-aligner-q4_k.gguf`（392MB），词级对齐后 `-sp` 时间戳精确到句边界 | ✅（本轮） |
| 6 | `-bs 5` beam search 使 31.5s 音频耗时 48.5s | qwen3 LLM 解码 beam 5 代价过高且质量增益≈0 | 默认模板改回 greedy（2.6s/10.9s，质量差异仅 1 字符长音） | ✅（本轮） |
| 7 | `escape_sub_path` 给非 Windows 路径加 `\:` 转义导致 ffmpeg 字幕滤镜失败 | 该函数按 Windows 盘符冒号逻辑写死 | 按 `os.name == 'nt'` 分支处理 | ✅（前轮） |
| 8 | `_MEIPASS` 冻结环境下工作目录混乱 | PyInstaller 一次性目录语义未区分 | 冻结时 `os.chdir(sys._MEIPASS)`，用户数据走 `~/Library/Application Support` 语义；worker 复用主程序（`--asr-worker` 标志）避免第二个 EXE | ✅（前轮+本轮） |
| 9 | 界面字体 Segoe UI 在 macOS 缺失 | Windows 字体 | macOS 下设 `.Apple System Font` | ✅（前轮） |
| 10 | 语言下拉框无"自动检测" | 原版只有 ja/en/ko/ru/fr/zh | 追加 `auto`，默认仍是 `ja`（优先日语+保留自动检测） | ✅（本轮） |
| 11 | PyInstaller 构建报 `Qt plugin directory '.../????/.../plugins' does not exist` | 项目路径含中文，PyInstaller 的 Qt 钩子取插件目录时把非 ASCII 字符替换成 `????`（目录本身存在） | 在**纯 ASCII 路径**下构建（源码 rsync 到 `/tmp/vtbuild`，模型目录用软链接，重建 venv） | ✅（本轮） |
| 12 | 构建报找不到 `i18n.py` / `avatar.png` / `translate` 目录 / `separate` 目录 | v1.20 spec 引用了仓库中并不存在的资源 | 剔除不存在的 datas；补建 `separate/` 目录（启动时 `os.listdir('separate')` 需要它，否则 GUI 直接崩溃） | ✅（本轮） |
| 13 | 冻结态多进程（翻译 worker 池）会重新执行主程序入口 | 缺 `multiprocessing.freeze_support()` | `__main__` 首行加入 `freeze_support()`，并置于 `--asr-worker` 分支之前 | ✅（本轮） |
| 14 | 打包版 faster-whisper 报 `Applying the VAD filter requires the onnxruntime package` | spec 的 `excludes` 连 onnxruntime 一起排除了（原本只为 separate.py 瘦身） | `excludes` 仅保留 `torch/librosa/soundfile`；worker 内再做防御：缺 onnxruntime 时自动关闭 VAD 并告警 | ✅（本轮） |
| 15 | 打包版报 `Load model .../Frameworks/faster_whisper/assets/silero_vad_v6.onnx failed` | PyInstaller 把 Python 模块塞进 PYZ，包数据文件落在 `Contents/Resources/`，而 `get_assets_path()` 依据 `__file__` 解析到 `Contents/Frameworks/` | ①spec 用 `collect_data_files('faster_whisper')` 收集权重；②worker 内 `_ensure_vad_assets()` 找不到时回退搜索 `Resources/` 实际位置并热替换路径 | ✅（本轮） |
| 16 | 打包后 GUI 启动秒退：`No such file or directory: .../Frameworks/darkdetect` | 前轮引入的 `darkdetect.listener()` 在 macOS 下要 spawn 包内 `darkdetect` 辅助程序，冻结时未收集 | 用 try/except 降级：启动时主题检测保留，实时跟随不可用时告警跳过 | ✅（本轮） |

> 附：PyInstaller 的 `--clean` 会清空 `~/Library/Application Support/pyinstaller` 缓存（469 项），触发环境的批量删除保护而中断；构建时改用 `--noconfirm`（不带 `--clean`）复用缓存即可。

---

## 2. openai-whisper 全局扫描结论（任务 1）

对仓库全量扫描（`*.py/*.txt/*.md/*.json/*.yaml/*.spec`，排除 `.venv/.git`）：

- `openai-whisper` / `openai_whisper` / `import whisper` / `from whisper import` / `whisper.load_model`：**0 命中**
- `requirements.txt`（主清单，Windows）：无任何 whisper 类依赖
- `~/.cache/whisper`：不存在
- 唯一 whisper 类依赖：本轮有意新增的 `faster-whisper==1.2.1`（可选引擎）

**结论**：v1.20 从未依赖 openai-whisper（作者的 Whisper 路线一直是 whisper.cpp CLI 与 Purfview faster-whisper exe 两个外部可执行文件，前者为 C++ 二进制、后者为闭源 Windows exe，均非 openai-whisper Python 包），因此无需删除任何依赖/import/调用点/测试用例，也不存在 `~/.cache/whisper` 缓存。原 `whisper-faster/param.txt` 中的 Windows 模板已替换为 macOS 版（见 §4）。清理后验证：`py_compile` 通过、`import app` 通过、三引擎分发路径实测可运行。

## 3. Qwen3-ASR-1.7B 模型核对（任务 3）

**目录**：`VoiceTransl-macos/qwen3-asr-1.7b/`

| 文件 | 大小 | 说明 | 完整性 |
|---|---|---|---|
| `qwen3-asr-1.7b-q4_k.gguf` | 1,490,915,200 B（1.49GB） | 通用多语种版（对应 cstr/qwen3-asr-1.7b-GGUF 的 Q4_K 重建版） | ✅ GGUF v3，710 张量，metadata 完整（`general.architecture = qwen3asr`，audio encoder 24 层/1024d/128 mel@16kHz + Qwen3 LLM 28 层/2048d，audio_start/end/pad token 齐全） |
| `qwen3-asr-1.7b-ja-anime-q4_k.gguf` | 1,490,917,376 B（1.49GB） | 日语动漫特调版（社区微调，同格式） | ✅ 实测可加载转写 |
| `canary-ctc-aligner-q4_k.gguf` | 392,167,040 B（392MB） | CTC 强制对齐器（**本轮补充**，实现句级时间戳） | ✅ 断网验证通过 |
| `param.txt` | — | 默认命令行模板（日语优化） | ✅ |

**关于"缺哪些文件"**：两个权重文件本身**不缺**、可直接离线加载（audio encoder 与 LLM 权重同文件，无需单独 mmproj）。但需说明两点：
1. 官方 llama.cpp（master，2026-08-30）**不支持** `qwen3asr` 架构，不能用它加载；本项目通过 **CrispASR v0.8.30** 加载（这正是 VoiceTransl v1.30 上游采用的引擎，与该 GGUF 量化仓库 `cstr/qwen3-asr-1.7b-GGUF` 官方配套）。
2. 对齐器模型原不在目录内，`-am auto` 首次会联网下载；本轮已下载并固定到项目目录实现**完全离线**。

**加载方式**（即默认参数模板 `qwen3-asr-1.7b/param.txt`）：

```
crispasr/crispasr --backend qwen3 -m qwen3-asr-1.7b/$whisper_file \
  -am qwen3-asr-1.7b/canary-ctc-aligner-q4_k.gguf -osrt -of $input_file \
  -l $language -sp --prompt 以下は日本語の音声の文字起こしです。促音、長音、片仮名の外来語を正確に書き起こしてください。 \
  -np $input_file.16k.wav
```

变量 `$whisper_file / $language / $input_file` 由 app.py 在运行时替换（与 whisper.cpp 路线同一机制）。

## 4. 引擎架构与切换方式（任务 2）

```
┌─ whisper_file 下拉框 ──────────────────────────────────────────┐
│  ggml-*.bin          → whisper.cpp CLI（legacy，Metal 可用）    │
│  *.gguf（qwen3）     → CrispASR CLI --backend qwen3 【默认】    │
│  faster-whisper-*    → asr_worker.py（faster-whisper/ctranslate2│
│                        CPU int8，独立子进程）                    │
│  不进行听写          → 跳过 ASR                                  │
└────────────────────────────────────────────────────────────────┘
```

- **配置项切换**：主界面"语音识别模型"下拉框。qwen3 模型参数在"输入Qwen3-ASR命令行参数"文本框（持久化到 `qwen3-asr-1.7b/param.txt`，与 whisper/whisper-faster 模板同一读写机制）。
- **环境变量切换**（优先级高于界面选择，便于脚本/自动化）：

```bash
# 强制 Qwen3 引擎（即使界面选了其他模型；'不进行听写'时仍尊重用户）
export VOICETRANSL_ASR_ENGINE=qwen3

# 强制 faster-whisper（模型默认 large-v3，可另指定）
export VOICETRANSL_ASR_ENGINE=faster-whisper
export VOICETRANSL_FW_MODEL=large-v3     # 或 small / 本地目录名

# faster-whisper worker 单独调试（不经 GUI）：
.venv/bin/python asr_worker.py --model large-v3 --input audio.16k.wav \
    --language ja --output /path/audio --beam_size 5 --vad_filter 1
```

- worker 模型解析顺序：`whisper-faster/faster-whisper-<name>/` 本地目录（离线优先）→ 本地路径 → HuggingFace ID。**已预置 `whisper-faster/faster-whisper-large-v3/`（3.09GB）实现开箱离线**（small 版已按需求替换删除）。
- 打包态：faster-whisper 通过 `VoiceTransl --asr-worker …` 复用主可执行文件（`__main__` 中的 worker 分支），避免 PyInstaller 双 EXE 使依赖体积翻倍。

## 5. 日语优化（任务 4）

| 手段 | 实现 | 实测效果 |
|---|---|---|
| 默认日语 | 语言下拉框默认 `ja`，同时保留 `auto` 选项 | ja_short CER 0~1.8% |
| initial_prompt | 模板内置日文提示语（促音/长音/片假名指示），非日语语言时 app 自动剔除该 prompt | 长音「ー」正确保留（コンピューター） |
| 热词 | qwen3 后端经 `--prompt` 注入（`--hotwords` 仅对 granite 后端生效，已在 UI 占位符说明）；faster-whisper 走原生 `--hotwords` | — |
| 断句标点 | `-sp`（按句末标点断行）+ CTC 对齐器提供句级时间戳 | 31.5s 日语 → 6 条字幕全部对齐句号边界 |
| 长句/解码 | greedy + `-bo` 保持默认；VAD 类问题由 qwen3 内部窗口机制与 app 分段功能（可开 1 分钟分段）承担 | 促音（もっと）、片假名外来词全部正确 |
| 防中日英混淆 | `-l ja` 显式指定 + ja-anime 特调模型可选 | zh/en 均未被误判（auto 模式亦正确识别） |

## 6. 三语实测数据（任务 5）

测试音频由 macOS `say` 合成（Kyoko/Tingting/Samantha），16kHz 单声道。RTF = 处理耗时/音频时长（**含每次进程冷启动的模型加载**，与 app 逐文件子进程架构一致）；内存为子进程峰值 RSS（含 mmap 模型映射）。ja/zh 报 CER、en 报 WER；参照文本为 TTS 朗读原文（古都→こと、紅葉→モミジ 属 TTS 读音与表记差异，计入错误但在下文注明）。

### 准确率（CER：日语/中文；WER：英文）

| 用例 | Qwen3-ASR-1.7B q4_k（Metal，greedy+对齐） | Qwen3 ja-anime 特调 | faster-whisper-large-v3（CPU int8） |
|---|---|---|---|
| 日语短句 10.9s | 1.79%（beam=0%；差异仅 コンピュータ vs コンピューター） | **0.0%** | **0.0%** |
| 日语长句 31.5s | 7.33% | — | **0.67%** |
| 中文 9.9s | 2.38%（得→的 1 字） | — | **0.0%** |
| 英文 9.3s | **0.0%** | — | **0.0%** |

> - Qwen3 日语长句的 7.33% 中约 5 个百分点来自 TTS 读音/表记差异（こと/古都、モミジ/紅葉）与结尾一处音频歧义读音；剔除后真实错误 ≈ 2%。
> - large-v3 在日语长句上反超 Qwen3（古都/紅葉/趣 的汉字表记全部正确），中文亦正确输出简体与「发展**得**」。
> - 早期测过的 small 模型供对照：日语长句 12.67%、中文 26.19%（输出繁体 + 博物園 幻觉），已按需求替换为 large-v3 并删除。

### 速度（RTF）与内存

| 用例（时长） | Qwen3 q4_k（Metal，greedy） | RTF | fw-large-v3（CPU int8） | RTF |
|---|---|---|---|---|
| 日语短句 10.9s | **2.60s** | **0.24** | 14.08s | 1.29 |
| 日语长句 31.5s | **7.88s** | **0.25** | 31.00s | 0.98 |
| 中文 9.9s | **2.05s** | **0.21** | 19.28s | 1.95 |
| 英文 9.3s | **2.15s** | **0.23** | 20.58s | 2.22 |
| ja-anime 日语 10.9s | **2.64s** | 0.24 | — | — |
| **峰值内存** | **≈3.4–3.5 GB**（模型 1.49G + 对齐器 0.39G mmap + Metal 缓冲） | | **≈3.0–3.3 GB** | |

**怎么选**：追求 4 倍实时与低延迟 → 默认 **Qwen3-ASR**（Metal GPU）；追求极限准确率且不计较 1–2 倍 RTF → 切换到 **faster-whisper-large-v3**。两者均已离线预置。

GPU 调用验证方法（避免静默回退 CPU）：
```bash
crispasr --backend qwen3 -m <model>.gguf -v <audio.wav> 2>&1 | grep -E "metal|device"
# 预期出现 ggml_metal_library_compile_pipeline / Metal 后端字样；
# pipeline cache 写入 ~/Library/Caches/ggml-metal/Apple_M5.archive
# 加 -ng 可对比 CPU 模式耗时（已验证 GPU 显著更快）
```

## 7. 改动文件清单与依赖变更

**新增**
- `asr_worker.py` — faster-whisper 可选引擎工作进程（含日语默认 prompt/VAD 调优/模型本地解析/SRT 写出）
- `crispasr/` — CrispASR v0.8.30 arm64 二进制（crispasr、crispasr-quantize、libc2pa_c.dylib，ad-hoc 签名）
- `qwen3-asr-1.7b/param.txt` — 默认命令行模板（日语优化）
- `qwen3-asr-1.7b/canary-ctc-aligner-q4_k.gguf` — 对齐器（离线化）
- `whisper-faster/faster-whisper-large-v3/` — 可选引擎模型（3.09GB，离线开箱）
- `separate/README.md` — 补齐 v1.20 spec 依赖但仓库缺失的 `separate/` 目录（启动时 `os.listdir('separate')` 需要它存在，否则直接崩溃）

**修改**
- `app.py`（10 处最小化改动）：模型下拉框增加 `.gguf` 扫描；语言下拉框增加 `auto`；新增 `param_qwen` 参数框（读写 `qwen3-asr-1.7b/param.txt`）；`_process_single_audio` 与分段路径增加 qwen3 分发（含非日语自动剔除日文 prompt）与 faster-whisper worker 分发；`VOICETRANSL_ASR_ENGINE` 环境变量覆盖；`__main__` 增加 `--asr-worker` 分支
- `whisper-faster/param.txt` — Windows Purfview 模板 → macOS worker 模板
- `requirements-macos.txt` — 增加 `faster-whisper==1.2.1`（传递依赖 ctranslate2/tokenizers/huggingface_hub 由 pip 解析）
- `app-macos.spec` — datas 增加 `qwen3-asr-1.7b/`、`crispasr/`；hiddenimports 增加 `asr_worker`、`faster_whisper`
- 前轮已改：`app.py` 深色模式（darkdetect 跟随系统 + `NSRequiresAquaSystemAppearance=False`）、macOS 字体、`_MEIPASS`、`escape_sub_path`；`whisper/` 重编 whisper.cpp v1.9.3（Metal）

**依赖变更说明（macOS vs Linux 差异）**

| 依赖 | macOS (arm64) | Linux | 说明 |
|---|---|---|---|
| CrispASR v0.8.30 | ✅ 预编译（Metal） | ✅ 预编译（CPU/Vulkan/CUDA 多种） | 平台二进制不同，接口一致 |
| faster-whisper 1.2.1 / ctranslate2 | ✅ CPU（**无 Metal 轮子**） | ✅ CPU/CUDA | GPU 提速仅在 Linux+NVIDIA |
| torch（仅 separate.py 人声分离用） | 前轮已装 MPS 版 | CUDA 版 | 主程序不依赖；打包排除 |
| whisper.cpp v1.9.3 | 源码编译（Metal） | 源码编译（CPU/Vulkan） | legacy 引擎 |
| ffmpeg | 项目自带 arm64 build | 需自备/自带 | — |

## 8. 构建与打包

```bash
# 可复现构建流程（Apple Silicon，macOS 12+；Python 3.13）
git clone --depth 1 --branch v1.20 https://github.com/shinnpuru/VoiceTransl.git VoiceTransl-macos
cd VoiceTransl-macos

# 1) 模型与运行时就位
#    - qwen3-asr-1.7b/: 两个 q4_k gguf + canary-ctc-aligner-q4_k.gguf + param.txt
#    - crispasr/:       下载 crispasr-macos.tar.gz (v0.8.30) 解压
#    - whisper-faster/faster-whisper-large-v3/: HF Systran/faster-whisper-large-v3
#    - whisper/:        whisper.cpp 自编 whisper-cli + ggml 模型；llama/: llama-server + Sakura

python3.13 -m venv .venv && .venv/bin/pip install -r requirements-macos.txt pyinstaller

# 2) 打包：⚠️ 项目路径必须全 ASCII（否则 PyInstaller Qt 钩子会把中文路径变成 ????）
#    若源码位于含中文的目录，先同步到 ASCII 路径再构建：
rsync -a --exclude='.venv' --exclude='whisper' --exclude='llama' \
      --exclude='qwen3-asr-1.7b' --exclude='whisper-faster' ./ /tmp/vtbuild/
cd /tmp/vtbuild
ln -s "$SRC/whisper" whisper; ln -s "$SRC/llama" llama
ln -s "$SRC/qwen3-asr-1.7b" qwen3-asr-1.7b; ln -s "$SRC/whisper-faster" whisper-faster
python3.13 -m venv .venv && .venv/bin/pip install -r requirements-macos.txt pyinstaller

.venv/bin/pyinstaller --clean --noconfirm app-macos.spec

# 3) 签名与镜像
codesign --force --deep --sign - dist/VoiceTransl.app          # ad-hoc 签名
hdiutil create -volname VoiceTransl -srcfolder dist/VoiceTransl.app \
    -ov -format UDZO dist/VoiceTransl-macos-arm64.dmg
```

**签名/公证说明**：无 Apple Developer ID 时采用 ad-hoc 签名；用户首次打开需右键→打开，或 `xattr -r -d com.apple.quarantine VoiceTransl.app`（Tahoe 并未新增拦截规则，这是 Catalina 起的既有 Gatekeeper 机制）。如需免提示分发，需 Developer ID 签名 + 公证（`notarytool`），属可选项。

**产物（已实测生成）**

| 产物 | 位置 | 大小 | 说明 |
|---|---|---|---|
| `VoiceTransl.app` | `/tmp/vtbuild/dist/VoiceTransl.app`（构建工作区） | **6.3 GB**（第 2 轮，删除 ggml/canary 后） | ad-hoc 签名（`Signature=adhoc`，`TeamIdentifier=not set`），bundle ID `com.voicetransl.app` |
| `VoiceTransl-macos-arm64.dmg` | `VoiceTransl-macos/dist/VoiceTransl-macos-arm64.dmg` | **5.7 GB**（UDZO，第 2 轮） | 内含模型：qwen3 2.8G + faster-whisper-large-v3 3.1G + Sakura 5.3G + ffmpeg 0.16G + crispasr 0.02G（已移除 whisper.cpp 3.0G + canary 0.39G） |

> 体积优化提示：若不需要 legacy whisper.cpp 路线，可删除 `whisper/ggml-large-v3.bin` 省 3.0G；不需要本地 Sakura 翻译 LLM 可删除 `llama/*.gguf` 省 5.3G（在线翻译模型仍可用）。

**首次打开方式（无 Developer ID 时）**

```bash
xattr -r -d com.apple.quarantine /Applications/VoiceTransl.app   # 或右键 → 打开
```

## 9. 自检清单

- [x] `py_compile app.py asr_worker.py` 通过
- [x] 离屏 `import app` 通过（QT_QPA_PLATFORM=offscreen）
- [x] qwen3 分发路径端到端（与 `_process_single_audio` 逐行一致的参数构造）：ja 直接命中 / auto+非日语正确剔除日文 prompt，SRT 落位 `base_path.srt`
- [x] ~~asr_worker 独立运行（small 模型，ja/zh/en）~~ — 第 3 轮随 fw 一并删除
- [x] Metal 生效验证（kernel 编译日志 + pipeline cache + `-v` 设备输出；`-ng` 对比提速）
- [x] 断网离线：移除 `~/.cache/crispasr` 后显式对齐器路径正常
- [x] 日/中/英 三语准确率、RTF、内存实测（§6）
- [x] PyInstaller 构建成功（第 1 轮 9.5GB .app → 第 2 轮 6.3GB .app）
- [x] 冻结态 Qwen3 引擎：bundle 内 crispasr 转写成功，逐句时间戳精确
- [x] ~~冻结态 faster-whisper 引擎~~ — 第 3 轮已删除；改为验证「冻结态 Qwen3 + canary」转写成功（句子级时间戳精确，见 §12.5）
- [x] GUI 启动：直接运行二进制后进程存活、无 stderr 报错
- [x] DMG 生成（第 1 轮 8.7GB → 第 2 轮 5.7GB）
- [x] **第 2 轮**：ggml/canary 完全清除（代码 + 文件 + bundle 验证通过）
- [x] **第 2 轮**：UI 截图对照完成（10 张原版 Windows 截图逐页比对）

## 10. 已知限制与后续待办

1. **~~UI 参考截图无法读取~~（已解决）**：第 2 轮成功读取全部 10 张截图并完成逐页对照，语音模型页的 ggml 差异已通过删除操作消除。
2. **~~faster-whisper 无 GPU~~（已删除）**：第 3 轮已彻底移除 faster-whisper（官方轮子无 Metal，且自编译未合并的社区 PR 风险过高）。当前**仅 Qwen3-ASR 单一引擎**，Metal GPU 生效，实测约 4.2 倍实时。若日后仍需 fw，可从 `/tmp/fw-removal-backup/` 恢复，或自行编译 OpenNMT/CTranslate2#2077 的 MPS 分支。
3. **人声分离（UVR）**：`separate.py` 依赖 torch/onnxruntime（打包时排除）且仓库未附带 UVR onnx 权重。本轮已补齐 `separate/` 目录（含 README 说明）以满足启动时 `os.listdir('separate')` 的前置要求（否则 GUI 启动即崩）；权重放入后可被下拉框识别，但打包版仍不提供实际分离能力（源码运行可 pip install torch/onnxruntime 后使用）。
4. **~~长音频断句粒度~~（已变更）**：canary CTC 对齐器已按用户要求删除，`-sp` 一并移除（无对齐器时 `-sp` 会导致时间戳归零）。当前输出为**单条 SRT 覆盖全音频**，时间戳准确。如需句子级时间戳，可重新放入 `canary-ctc-aligner-q4_k.gguf` 并在 param.txt 恢复 `-am` 和 `-sp`。长视频仍建议开启「分段处理」。
5. **每次转写冷启动**：当前架构每文件启动一次 CrispASR（模型加载 ≈1.5–2s，M5 实测）。待办：常驻 llama-server/CrispASR 服务模式避免重复加载（app 现有 start/stop_named_proc 机制可扩展）。
6. **`--hotwords` 对 qwen3 无效**：CrispASR 该参数仅 granite 后端实现；qwen3 热词需走 `--prompt` 上下文注入（默认模板已演示）。
7. **openai-whisper 缓存目录**：`~/.cache/whisper` 在本机不存在，无需清理；若其他环境存在可 `rm -rf ~/.cache/whisper`（属用户自查项，本会话不代删个人目录）。

---

## 11. 第 2 轮变更：删除 ggml（whisper.cpp）与 canary（CTC 对齐器）

**日期**：2026-08-30 15:00 ｜ **触发**：用户上传 10 张原版 Windows 界面截图对照 + 明确要求删除 ggml 和 canary 模型

### 11.1 删除清单

| 删除项 | 大小 | 原因 |
|---|---|---|
| `whisper/ggml-large-v3.bin` | 3.0 GB | whisper.cpp legacy 引擎，macOS 已用 Qwen3/CrispASR 替代 |
| `whisper/ggml-silero-v5.1.2.bin` | 885 KB | whisper.cpp VAD 模型，随 whisper-cli 一并移除 |
| `whisper/whisper-cli` + `libggml*.dylib` | ~4 MB | whisper.cpp 可执行文件及 Metal 库 |
| `qwen3-asr-1.7b/canary-ctc-aligner-q4_k.gguf` | 392 MB | CTC 强制对齐器，用户明确要求删除 |

**总计释放磁盘空间：约 3.4 GB**

### 11.2 代码变更（app.py）

| 变更点 | 说明 |
|---|---|
| `refresh_speech_model_lists()` | 移除 `whisper/` 目录下 `ggml*.bin` 扫描，仅保留 `qwen3-asr-1.7b/*.gguf` + `whisper-faster/faster-whisper-*` |
| `initSettingsTab()` | 移除「输入Whisper命令行参数」QTextEdit + 标签；移除「打开Whisper目录」按钮 |
| 配置加载 | 移除 `whisper/param.txt` 读取 |
| 配置保存（2 处） | 移除 `whisper/param.txt` 写入 |
| `_process_single_audio()` | 移除 `elif whisper_file.startswith('ggml'):` 分支及其 `stop_named_proc` |
| 分段循环 | 同上，移除 ggml 分支和 stop |
| 函数签名 | `_process_single_audio()` 移除 `param_whisper` 参数 |
| 调用点 | `run()` 中移除 `param_whisper = self.master.param_whisper.toPlainText()` 及传参 |

### 11.3 spec 变更（app-macos.spec）

- `datas` 列表移除 `('whisper', 'whisper')`

### 11.4 param.txt 变更（qwen3-asr-1.7b/param.txt）

```
# 删除前
crispasr/crispasr ... -am qwen3-asr-1.7b/canary-ctc-aligner-q4_k.gguf ... -sp ...

# 删除后
crispasr/crispasr ... （无 -am，无 -sp）
```

**`-sp` 行为说明**：删除 canary 对齐器后，若保留 `-sp` 会导致所有 SRT 时间戳归零为 `00:00:00,000`（qwen3 后端在无对齐器时按标点切分文本但丢失时间信息）。因此 `-sp` 一并移除。输出变为**单条 SRT 条目覆盖整个音频**，时间戳为 `[0 → 音频总时长]`，数值准确。

### 11.5 UI 截图对照结果

10 张原版 Windows 截图全部成功读取，逐页比对：

| 截图 | 页面 | 差异 |
|---|---|---|
| 1 | 欢迎/关于页 | ✅ 布局一致 |
| 2 | 侧边栏导航 | ✅ 菜单项一致 |
| 3 | 输入输出页 | ✅ 一致 |
| 4 | 分离工具页 | ✅ 一致 |
| 5 | 合成工具页 | ✅ 一致 |
| 6 | 总结工具页 | ✅ 一致 |
| 7 | **语音模型页** | ✅ **已修正**：原版显示 `ggml-large-v3.bin` + whisper-cli 参数模板；删除后模型下拉框仅显示 Qwen3 GGUF + faster-whisper，符合 macOS 移植目标 |
| 8 | 语言模型页 | ✅ 一致 |
| 9 | 字典设置页 | ✅ 一致 |
| 10 | 日志页 | ✅ 一致 |

### 11.6 验证结果

- [x] Qwen3 无 canary 模式转写测试通过（ja 10.9s 音频，时间戳正确，Metal GPU 生效）
- [x] app.py 语法检查通过
- [x] 5 项残留检查全通过（ggml 模型引用 / param_whisper 调用 / whisper/param.txt 路径 / 打开Whisper目录按钮 / whisper-cli 引用）

---

## 12. 第 3 轮变更：彻底删除 faster-whisper，恢复 canary，仅产出 .app

**日期**：2026-08-30 15:35 ｜ **触发**：用户询问 faster-whisper 能否调用 M5 GPU，要求「不行则彻底删除 fw，只保留 Qwen3」+ 恢复 canary + 仅构建 .app

### 12.1 faster-whisper M5 GPU 可行性调研结论

**结论：官方路径不可行 → 按用户条件执行彻底删除**

| 路径 | 可行性 | 依据 |
|---|---|---|
| **官方 PyPI 轮子** | ❌ 不可行 | 实测 ctranslate2 4.8.1：`device=metal` / `mps` / `coreml` 均报 `unsupported device`，仅 `cpu` 可用。OpenNMT 官方文档明确写 "The macOS version only supports CPU execution" |
| **社区 PR（OpenNMT/CTranslate2#2077）** | ⚠️ 理论可行但需自编译 | 第三方 fork 实现了 MPS 后端，M4 实测 7 分钟音频：CPU int8 443s → Metal float16 80s（约 5.5 倍）。需安装 cmake + 完整 Xcode，编译整个 C++ 引擎（30–60 分钟），且代码**未经官方审核合并**，PR 作者本人声明无法保证深层 kernel 无 bug |

**决策依据**：
- 本项目 Qwen3 引擎实测 RTF 0.24（约 4.2 倍实时），**远快于** fw-large-v3 的 CPU 路径（RTF 0.98–2.22）
- 引入未合并的第三方 C++ 后端违背用户「改动范围尽量小、不引入新框架」的约束
- 用户已明确给出条件：「如果不行就彻底删除 fw」

**本地环境实测数据**（供后续参考，非本轮采用）：

```
ctranslate2 版本: 4.8.1
device=cpu     : ['float32', 'int8', 'int8_float32']
device=cuda    : 不支持 -> This CTranslate2 package was not compiled with CUDA support
device=metal   : 不支持 -> unsupported device metal
device=mps     : 不支持 -> unsupported device mps
device=coreml  : 不支持 -> unsupported device coreml
```

### 12.2 fw 删除清单

| 删除项 | 大小 | 说明 |
|---|---|---|
| `whisper-faster/` 目录 | 2.9 GB | 含 `faster-whisper-large-v3/` 模型 + `param.txt` + `README.md` |
| `asr_worker.py` | 6.4 KB | faster-whisper worker 进程脚本 |

> **备份位置**：`/tmp/fw-removal-backup/`（含上面两项，验证无误后可自行清理）

**app.py 代码清理（9 处）**：

| # | 位置 | 变更 |
|---|---|---|
| 1 | `initSettingsTab()` | 模型列表移除 fw 扫描；删除「Whisper-Faster 命令行参数」文本框 |
| 2 | `initSettingsTab()` | 「打开Faster Whisper目录」按钮 → 「打开Qwen3模型目录」按钮 |
| 3 | `refresh_speech_model_lists()` | 移除 fw 扫描 |
| 4 | 配置加载 | 移除 `whisper-faster/param.txt` 读取 |
| 5 | `_process_single_audio()` | 简化为 Qwen3 单一引擎（移除 fw 分支 + `stop_named_proc('whisper_faster')`） |
| 6 | `run()` | 移除环境变量引擎切换逻辑（`VOICETRANSL_ASR_ENGINE` / `VOICETRANSL_FW_MODEL`） |
| 7 | `run()` | 移除 `param_whisper_faster` 读取与 `whisper-faster/param.txt` 保存 |
| 8 | 分段处理循环 | 移除 fw 分支，简化为 Qwen3 单一路径 |
| 9 | `__main__` | 移除 `--asr-worker` 入口分支 |

**其他文件**：

| 文件 | 变更 |
|---|---|
| `app-macos.spec` | `datas` 移除 `whisper-faster`；`hiddenimports` 移除 `asr_worker` / `faster_whisper`；移除 `collect_data_files('faster_whisper')` 及其导入；更新头部说明 |
| `requirements-macos.txt` | 移除 `faster-whisper==1.2.1` |
| `app.py` 帮助文案 | 「选择Whisper或Faster Whisper模型」→「选择Qwen3-ASR模型」 |

### 12.3 canary 恢复

| 项 | 内容 |
|---|---|
| 文件 | `qwen3-asr-1.7b/canary-ctc-aligner-q4_k.gguf`（392 MB，从 `~/.cache/crispasr/` 恢复） |
| param.txt | 恢复 `-am qwen3-asr-1.7b/canary-ctc-aligner-q4_k.gguf` 与 `-sp` |
| **新增过滤** | 模型下拉框扫描时排除 `canary*` 前缀（它是对齐器而非 ASR 模型，否则会出现在模型选择列表里） |

**恢复后实测（含冻结态）**，句子级时间戳全部精确：

```
[00:00:00.000 --> 00:00:02.580]  今日はとても良い天気ですね。
[00:00:02.580 --> 00:00:05.540]  京都の有名なお寺を見学しました。
[00:00:05.540 --> 00:00:08.860]  コンピュータはとても便利な道具です。
[00:00:08.860 --> 00:00:10.900]  もっと勉強したいです。
```

### 12.4 构建产物（仅 .app，无 dmg）

| 轮次 | .app | DMG |
|---|---|---|
| 第 1 轮（含 ggml + canary + fw） | 9.5 GB | 8.7 GB |
| 第 2 轮（删 ggml + canary） | 6.3 GB | 5.7 GB |
| **第 3 轮（删 fw，恢复 canary）** | **3.7 GB** | **不产出（用户要求）** |

- 路径：`VoiceTransl-macos/dist/VoiceTransl.app`
- 签名：ad-hoc（`Signature=adhoc`，`TeamIdentifier=not set`），bundle ID `com.voicetransl.app`
- 架构：arm64

> ⚠️ `dist/VoiceTransl-macos-arm64.dmg` 是**第 2 轮的过时产物**（不含 canary、仍含 fw），请勿使用；可自行删除。

### 12.5 第 3 轮验证结果

- [x] app.py 语法检查通过
- [x] 5 项 fw 残留检查全通过（asr_worker / faster / whisper-faster / param_whisper_faster / 多引擎分支）
- [x] 模型下拉框正确过滤 canary：`['qwen3-asr-1.7b-ja-anime-q4_k.gguf', 'qwen3-asr-1.7b-q4_k.gguf', '不进行听写']`
- [x] 语言下拉框保留 7 项（ja/en/ko/ru/fr/zh/auto）
- [x] `MainWindow` 构造成功，事件循环正常退出（退出码 0）
- [x] 冻结态 Qwen3 + canary 转写成功，句子级时间戳精确
- [x] bundle 内无 faster 残留；canary 与 2 个 Qwen3 模型均正确打包

> **GUI 启动验证说明**：本环境的 Bash 工具无法保持长驻 GUI 进程（直接运行二进制会被 SIGKILL/沙箱限制终止），因此改用「构造 `MainWindow` + 运行事件循环」的方式验证 UI 完整性，结论可靠。用户在自己桌面双击 `.app` 不受此限制。

---

## 13. 第 4 轮变更：按 macOS HIG 改造标题栏

**日期**：2026-08-30 16:05 ｜ **目标**：满足 ① 红绿灯归位左上角 ② 移除返回按钮 ③ 三态主题切换 ④ 持久化/过渡/对比度/最小宽度，并处理标题居中、右上角排列、返回逻辑等连锁影响

### 13.1 窗口控制按钮（红绿灯）

**关键决策：不自绘，改用系统原生按钮。**

`MainWindow → FluentWindow → FluentWidget` 在 macOS 上继承自 `qframelesswindow.MacFramelessWindow`，该类提供
`setSystemTitleBarButtonVisible(True)` 直接显示 AppKit 的 `NSWindowCloseButton / NSMiniaturizeButton / NSZoomButton`。
因此按钮尺寸、间距、与左/上边缘的留白比例、hover 时显示的符号**全部由系统绘制**，天然符合 HIG，也不会像自绘按钮那样在深色模式下对比度失真。

同时移除 QFluentWidgets 自绘的 `minBtn / maxBtn / closeBtn` 与 `iconLabel`（macOS 标题栏不放窗口图标）。

**踩坑 1**：`FluentWindowBase.systemTitleBarRect()` 把红绿灯定位在**右上角**（它返回 `QRect(width-75, 8, 75, h)`，原意是避开左侧导航面板）。必须在 `MainWindow` 中重写为左上角：

```python
def systemTitleBarRect(self, size):
    return QRect(0, 0, TRAFFIC_LIGHT_ANCHOR, size.height())
```

**踩坑 2**：红绿灯回到左上角后会压住导航面板的菜单按钮。解决：`_reserveTrafficLightSpace()` 在导航面板 `topLayout` 顶部插入 28px 留白，把菜单按钮下移。

**实测坐标**（从 NSWindow 读取真实 frame）：

| 按钮 | x | y | 尺寸 |
|---|---|---|---|
| 关闭 | 19 | 7 | 14×16 |
| 最小化 | 39 | 7 | 14×16 |
| 全屏 | 59 | 7 | 14×16 |

间距 20、尺寸 14×16 均为系统原生值。关闭按钮 x=19 与 HIG 要求的 20pt 左留白差 1px（库的定位逻辑用整数除法 `width // 2` 所致，视觉无差别）。

### 13.2 移除返回按钮

返回控件位于 `navigationInterface.panel.topLayout`（不在标题栏内）。清理四项：

| 处理 | 方式 |
|---|---|
| 可见性 | `setReturnButtonVisible(False)` |
| 占位空间 | 从 `topLayout` 摘除 + `setFixedHeight(0)`，QVBoxLayout 不再预留位置 |
| 状态 | `setEnabled(False)` |
| 导航依赖 | `clicked.disconnect()`，断开「返回上一页」（`history.pop`）逻辑 |

保留按钮对象本身，避免 `NavigationPanel` 内部残留引用引发 AttributeError。

### 13.3 三态主题切换

右上角 `TransparentToolButton`，点击弹出 `RoundMenu`，三态循环可选：浅色 / 深色 / 跟随系统，**默认 auto**。

- 图标：浅色 `BRIGHTNESS`、深色 `QUIET_HOURS`、跟随系统 `CONSTRACT`
- 持久化：`project/theme.txt`（与既有 `config.txt` 解耦，避免改动其行格式）
- 平滑过渡：`QGraphicsOpacityEffect` 淡出 110ms → `setTheme()` → 淡入 140ms，动画结束后卸下特效
- **实时跟随系统**：改为监听 `QEvent.ApplicationPaletteChange` / `PaletteChange`，替代原先的 `darkdetect.listener()`

> 后者在 macOS 下需 spawn 包内 `darkdetect` 辅助程序，PyInstaller 冻结时未被收集，导致打包版只能启动时检测一次。改用 Qt 调色板事件后，打包环境同样能实时响应。

### 13.4 连锁影响处理

| 影响项 | 处理方式 |
|---|---|
| 标题居中 | 左侧红绿灯留白与右侧控件区**等宽**（`rightWidget.setMinimumWidth(TRAFFIC_LIGHT_RESERVE)`），标题随窗口缩放动态保持居中 |
| 右上角排列 | `rightLayout` 统一右对齐、间距 6px、右边距 12px，按加入顺序自左向右 |
| 窗口过窄 | `setMinimumWidth(560)`；标题按可用宽度 `ElideMiddle` 省略，不与两侧重叠 |
| 返回逻辑 | 见 §13.2，`clicked` 已断开；`qrouter` 历史仍记录但无 UI 入口，不影响功能 |

**踩坑 3（标题不居中，最关键）**：初版实现后标题中心始终偏右，且偏移量随窗口宽度增大（900px 时偏 174px）。逐层定位出两个叠加原因：

1. `FluentTitleBar.hBoxLayout` 中残留一个 `stretch=1` 的空白项，`removeWidget/removeItem` 清不掉 → 新增 `_clearLayout()` 递归摘除所有项再重建
2. 标题栏自身 geometry 为 `(46, 0, 854, 48)` 而非 `(0, 0, 900, 48)` —— FluentWindow 的布局让它横向偏移了约 46px，导致「居中」是相对标题栏而非窗口 → 在 `MainWindow.resizeEvent` 中强制 `titleBar.setGeometry(0, 0, width, height)`

修复后四个宽度实测偏移均为 **0.0**。

### 13.5 验证结果

| 项 | 结果 |
|---|---|
| 红绿灯位于左上角 | ✅ x=19/39/59，间距 20（系统原生） |
| 红绿灯与导航菜单按钮不重叠 | ✅ 菜单按钮 y=38 > 红绿灯底部 y=23 |
| 自绘 min/max/close、窗口图标已移除 | ✅ |
| 返回按钮：隐藏 / 移出布局 / 禁用 / 高度 0 | ✅ 全部通过 |
| 默认模式 = auto（跟随系统） | ✅ |
| 切深色 / 切浅色生效 | ✅ `isDarkTheme()` 对应变化 |
| 持久化写入 `project/theme.txt` | ✅ dark → 文件 dark，恢复 auto |
| 对比度：深色标题亮度 255、浅色标题亮度 0 | ✅ 双向达标 |
| 标题居中（560/700/900/1200px） | ✅ 偏移均为 0.0 |
| 最小宽度 560 下不重叠 | ✅ |
| 事件循环退出码 | ✅ 0 |

---

## §14 Round 5：红绿灯垂直居中 + Finder 风格导航面板切换

**日期**：2026-08-30 16:30–16:40 ｜ **触发**：用户截图反馈 + 功能需求

### 14.1 需求

1. **红绿灯垂直居中**：第 4 轮红绿灯位于 y=7（从窗口顶部），在 48px 标题栏内明显偏上。需垂直居中（目标 center_y ≈ 24）。
2. **Finder 风格导航面板切换**：点击导航面板最上方菜单按钮（≡）时展开并固定侧边栏（类似 Finder），再次点击收起。默认展开。**不得遮挡内容**（内联推内容，非浮层）。

### 14.2 红绿灯垂直居中实现

**根因分析**：
`_updateSystemButtonRect()` 中 `center = self.systemTitleBarRect(QSize(w, titlebarHeight)).center()`，其中 `titlebarHeight` 是 NSWindow 原生标题栏高度（28px）。之前 `systemTitleBarRect` 返回 `QRect(0, 0, 94, size.height())` → height=28 → center.y=14 → 按钮中心在标题栏上半部分。

**修复**：
- 新增常量 `TITLE_BAR_HEIGHT = 48`（与 `MacOSTitleBar.setFixedHeight(48)` 一致）
- `systemTitleBarRect()` 改为返回 `QRect(0, 0, TRAFFIC_LIGHT_ANCHOR, TITLE_BAR_HEIGHT)` → center.y=24
- 导航面板顶部留白从 28 调整为 36（TRAFFIC_LIGHT_CLEARANCE），为红绿灯底部（~y=32）与菜单按钮之间留出间隙
- 新增 `_ensureTrafficLightClipping()` 在窗口显示后设置按钮父视图链 `clipsToBounds=False`，防止红绿灯超出原生 28px 标题栏区域时被裁剪

**验证数据**（pyobjc 实测）：

| 按钮 | x | y_from_top | w×h | center_y |
|---|---|---|---|---|
| 关闭 | 19 | 15 | 14×16 | **23** |
| 最小化 | 39 | 15 | 14×16 | **23** |
| 全屏 | 59 | 15 | 14×16 | **23** |

三个按钮 center_y 均为 **23**（目标 24，±1px 为整数除法舍入误差）。✅ 垂直居中

**Quartz 截图确认**：红绿灯与标题文字、主题按钮在同一水平线上，视觉居中。

### 14.3 Finder 风格导航面板切换实现

**核心设计**：

```python
# 强制内联展开（永远不走 MENU 浮层模式）
panel.setMinimumExpandWidth(0)
# 接管菜单按钮点击事件
panel.menuButton.clicked.disconnect(panel.toggle)  # 断开库自带逻辑
panel.menuButton.clicked.connect(self._toggleNavigationPanel)  # 接管
```

**为什么 setMinimumExpandWidth(0) 能避免遮挡**：
`expand()` 内部判断 `window.width() >= (minimumExpandWidth + expandWidth - 322)` 时走 EXPAND（内联推内容），否则走 MENU（浮层遮挡）。设为 0 后阈值 = 0 + 322 - 322 = 0，任何窗口宽度都满足 → **永远 EXPAND**。

**状态持久化**：
- 文件：`project/nav_state.txt`
- 值：`expanded` / `collapsed`
- 缺省/文件不存在 → 展开（符合"默认展开"需求）

**验证数据**：

| 状态 | display_mode | width | is_expanded | tooltip |
|---|---|---|---|---|
| 初始（默认） | EXPAND | 322 | ✅ | Close Navigation |
| 点击后（收起） | COMPACT | 48 | ❌ | Open Navigation |
| 再点击（展开） | EXPAND | 322 | ✅ | Close Navigation |

✅ 展开→收起→展开完整周期通过，无浮层遮挡。

### 14.4 本轮变更文件清单

| 文件 | 变更 |
|---|---|
| `app.py` | +`TITLE_BAR_HEIGHT` 常量；`systemTitleBarRect` 返回高度改为 48；`TRAFFIC_LIGHT_CLEARANCE` 28→36；+`_initNavigationPanelToggle()`；+`_toggleNavigationPanel()`；+`_ensureTrafficLightClipping()`；+nav 状态持久化（`_loadNavState`/`_saveNavState`）；`__init__` 中调用 `_initNavigationPanelToggle()` |
| `dist/VoiceTransl.app` | 重建（3.7GB，ad-hoc 签名，arm64） |

### 14.5 已知限制

- UVR 人声分离不可用（torch 未打包）
- per-file ASR 冷启动 ~1.5–2s
- `--hotwords` 对 qwen3 后端无效
- 导航面板收起时宽度 48px（图标模式），与红绿灯水平区域有重叠风险（红绿灯 x 范围 [19,73]，导航面板宽 48px → 重叠 [19,48]）。当前通过 TRAFFIC_LIGHT_CLEARANCE=36 让菜单按钮下移缓解，但图标列顶部仍可能与红绿灯视觉接近。若用户反馈可进一步调整。

---

## 15. 导航面板宽度：收窄 / 可拖拽调宽 / 持久化（Round 7）

### 15.1 需求

> 左侧标题栏太宽了，收窄到比文字稍宽一点，然后做成可允许调节宽度的模式，每次调整后自动保存状态，下次打开软件时沿用。

### 15.2 实现方案

#### A. 默认宽度收窄（322px → 131px）

测量所有导航项文字最大宽度（`QFontMetrics.horizontalAdvance`），最长项为「输入输出」「分离工具」等四字中文 = **53px**。导航项内部布局：图标区 0~44，文字从 x=44 起绘制；`setExpandWidth(w)` 内部令 `NavigationWidget.EXPAND_WIDTH = w - 10`。

**公式**：
```
expandWidth = NAV_TEXT_START_X(44) + maxTextWidth(53) + NAV_TEXT_RIGHT_PAD(24) + NAV_WIDTH_MARGIN(10) = 131
```

#### B. 可拖拽调宽

新增 `NavResizeHandle(QWidget)` 组件：
- 5px 宽，`SplitHCursor` 光标，位于导航面板与内容区之间
- 拖拽中实时 emit `resized(int)` → 调用 `_applyNavWidth()` 刷新面板及子项
- 松手后 emit `resizeFinished(int)` → 持久化写入文件
- 范围钳制 `[NAV_MIN_WIDTH(110), NAV_MAX_WIDTH(420)]`
- 自动适配深浅色主题绘制细分隔线

#### C. 宽度持久化

- 文件：`user_data_path('nav_width.txt')`
- **打包后路径**：`~/Library/Application Support/VoiceTransl/nav_width.txt`（非只读的 app bundle 内部）
- **源码运行时路径**：`project/nav_width.txt`（工程目录下）
- 缺失或越界 → 回退到自适应宽度 131px

#### D. UI 偏好存储位置统一修复（本轮发现并修复）

**问题**：原实现三处偏好（主题/导航状态/导航宽度）均用 `os.path.join('project', 'xxx.txt')` 相对路径。
打包后 `os.chdir(sys._MEIPASS)` 将 CWD 设为 `.app/Contents/Resources`（只读），写入静默失败。

**修复**：
- 新增模块级函数 `user_data_dir()` / `user_data_path(filename)`
- 打包运行时 → `~/Library/Application Support/VoiceTransl/`
- 源码运行时 → 工程目录下 `project/`
- 三处路径方法（`_themeConfigPath` / `_navConfigPath` / `_navWidthPath`）全部改用 `user_data_path()`

#### E. 关键技术细节

**`panel.setFixedWidth()` 会锁死展开/收起动画**：

NavigationPanel 的 collapse/expand 动画通过 `QPropertyAnimation` 修改 panel 的 geometry（QRect）实现。若对 panel 调用了 `setFixedWidth(w)`，则 `minimumWidth == maximumWidth == w`，动画的 `setGeometry` 无法改变宽度 → 收起动画失效、面板卡在原地。

**修复**：改用 `panel.resize(w, panel.height())`。NavigationInterface.eventFilter 监听面板 Resize 事件，会自动将自身 fixedWidth 同步为面板新宽度，布局正确传播。

**`NavigationWidget.setCompacted()` 有 early-return**：

当 `isCompacted == self.isCompacted` 时直接 return，不刷新子项尺寸。拖拽过程中 displayMode 始终为 EXPAND、isCompacted 始终为 False → 子项宽度不会自动更新。

**修复**：在 `_applyNavWidth()` 中直接遍历 `findChildren(NavigationWidget)`，对非 compacted 子项调用 `child.setFixedSize(NavigationWidget.EXPAND_WIDTH, h)`（分隔线 +10）。

### 15.3 新增 / 修改的常量与方法

| 名称 | 类型 | 说明 |
|---|---|---|
| `APP_SUPPORT_DIR_NAME` | 常量 | 用户数据目录名 `VoiceTransl` |
| `user_data_dir()` | 函数 | 返回偏好存储目录 |
| `user_data_path(filename)` | 函数 | 返回偏好文件完整路径（自动创建目录） |
| `NAV_TEXT_START_X` | 常量 | 44 |
| `NAV_TEXT_RIGHT_PAD` | 常量 | 24 |
| `NAV_WIDTH_MARGIN` | 常量 | 10 |
| `NAV_MIN_WIDTH` | 常量 | 110 |
| `NAV_MAX_WIDTH` | 常量 | 420 |
| `NavResizeHandle` | 类 | 可拖拽分隔条组件 |
| `_autoNavWidth()` | 方法 | 按文字自适应计算展开宽度 |
| `_navWidthPath()` | 方法 | 导航宽度持久化文件路径 |
| `_loadNavWidth()` | 方法 | 读取持久化宽度 |
| `_saveNavWidth(width)` | 方法 | 写入持久化宽度 |
| `_applyNavWidth(width)` | 方法 | 应用宽度（含子项刷新） |
| `_initNavResizeHandle(visible)` | 方法 | 初始化拖拽分隔条 |
| `_onNavResizeFinished(width)` | 方法 | 拖拽结束回调（应用+持久化） |

### 15.4 验证数据

| 测试项 | 期望 | 实际 | 通过 |
|---|---|---|---|
| 默认宽度（无持久化文件） | 131px | 131px | ✅ |
| 拖拽到 200px | 面板 200, 子项 190 | 200, 190 | ✅ |
| 钳制下界 (50→110) | 110 | 110 | ✅ |
| 钳制上界 (999→420) | 420 | 420 | ✅ |
| 持久化写入 | 文件内容 "200" | "200" | ✅ |
| 收起 → 48px, 状态 collapsed | 48, collapsed | 48, collapsed | ✅ |
| 展开 → 恢复 260px, 状态 expanded | 260, expanded | 260, expanded | ✅ |
| 独立进程重启恢复 | 260 (≠auto 131) | 260 | ✅ |
| 路径解析（源码模式） | project/nav_width.txt | project/nav_width.txt | ✅ |
| 分隔条光标 | SplitHCursor (12) | 12 | ✅ |

### 15.5 本轮变更文件清单

| 文件 | 变更 |
|---|---|
| `app.py` | +`user_data_dir()`/`user_data_path()`; 三处路径方法改用 `user_data_path()`; +6 个宽度常量; +`NavResizeHandle` 类; +`_autoNavWidth`/`_navWidthPath`/`_loadNavWidth`/`_saveNavWidth`/`_applyNavWidth`/`_initNavResizeHandle`/`_onNavResizeFinished`; 重写 `_initNavigationPanelToggle`（接管 menuButton.clicked、加载/应用宽度、初始化 handle）; 重写 `_toggleNavigationPanel`（恢复用户宽度再展开、切换 handle 可见性）; `panel.setFixedWidth` → `panel.resize` |
| `dist/VoiceTransl.app` | 重建（3.4GB，ad-hoc 签名，arm64） |

> ⚠️ §15 的可拖拽调宽功能已在 §16（Round 8）中按用户要求**完整移除**，宽度回退为固定的文字自适应 131px。

---

## 16. 表单输入自动保存 + 移除「文言文」提示项（Round 9）

### 16.1 需求

1. 页面中所有输入框（input、textarea 等）在**失去焦点 / 切换页面 / 关闭退出**时自动保存；重新进入页面自动回填上次内容；给出轻微的「已保存」提示；避免重复或高频写入。
2. 删除「额外提示」配置项中的「翻译结果使用文言文」这一条，其余提示项保持原样。
3. 约束：不改动现有界面布局与其他功能逻辑。

### 16.2 实现：新增 `FormAutoSaver`

位于 `app.py`，`QtCore.QObject` 子类，完全**增量式**接入，不触碰任何既有逻辑。

**覆盖控件（共 35 个）**

| 类型 | 数量 | 字段 |
|---|---|---|
| combo | 9 | `whisper_file`/`translator_group`/`input_lang`/`sakura_file`/`uvr_file`/`output_format`/`subtitle_font_combo`/`subtitle_type_combo`/`change_prompt_mode` |
| line | 8 | `gpt_token`/`gpt_model`/`gpt_address`/`sakura_mode`/`proxy_address`/`output_dir_edit`/`clip_start_time`/`clip_end_time` |
| text | 14 | `before_dict`/`gpt_dict`/`after_dict`/`extra_prompt`/`param_qwen`/`param_llama`/`summarize_prompt`/`summarize_files_list`/`synth_video_files_list`/`synth_srt_files_list`/`synth_audio_files_list`/`clip_files_list`/`uvr_file_list`/`input_files_list` |
| spin | 2 | `max_concurrent_spin`/`segment_duration_spin` |
| check | 2 | `use_input_dir_checkbox`/`enable_segment_checkbox` |

**排除项**（避免把展示内容误当用户输入）：

- `isReadOnly()` 的展示框：`output_text_edit`、`mode_text`、`log_display`
- SpinBox 内部的 `QLineEdit` 子控件（沿父链上溯判定 `QAbstractSpinBox`）

**存储键**：由 `MainWindow.__dict__` 及各 `*_tab` 对象的属性名建立 `id(widget) -> 属性名` 反查表，键稳定且可读；无属性名者跳过。

**触发时机**

| 时机 | 机制 |
|---|---|
| 失去焦点 | 对 35 个控件 `installEventFilter`，捕获 `QEvent.FocusOut` |
| 切换页面 | `self.stackedWidget.currentChanged` |
| 关闭 / 退出 | `closeEvent` 中调用 `save_now()`（跳过去抖立即落盘） |

**避免重复 / 高频写入**

- **去重**：写入前与 `_last_snapshot` 全量比对，内容未变化则不落盘、不弹提示
- **去抖**：`QTimer` 单触发 900ms，`request_save()` 只重置计时器；实测连续 5 次失焦仅落盘 1 次
- **回填期抑制**：`restore()` 期间置 `_restoring=True`，避免把初值反复写回

**提示**：`InfoBar.info(content='已保存', position=BOTTOM_RIGHT, duration=1200)`。选右下角是为避开自绘标题栏右上角的主题切换按钮；InfoBar 为浮层，不改变任何布局。

**存储位置**：`user_data_path('form_autosave.json')` —— 打包后 `~/Library/Application Support/VoiceTransl/`，源码运行时 `project/`。与既有 `config.txt` / `config.yaml` 完全隔离，不影响原保存流程。

**回填时机**：`initUI()` 中 `load_config()` **之后**，保证用户最后一次编辑优先于 `config.txt` 的陈旧值。

### 16.3 关键技术细节

**① `qfluentwidgets.ComboBox` 继承自 `QPushButton`，不是 `QComboBox`**

```python
ComboBox -> ['ComboBox', 'QPushButton', 'QAbstractButton', 'QWidget', 'ComboBoxBase', 'QObject']
```

因此 `findChildren(PyQt5.QtWidgets.QComboBox)` 返回空。且本文件在导入时把 qfluentwidgets 的 ComboBox **别名成了 `QComboBox`**：

```python
from qfluentwidgets import ... ComboBox as QComboBox ...
```

所以判定必须写成 `isinstance(w, QComboBox)`（实为 qfluentwidgets ComboBox）并置于 `_kind_of` 最前，否则会被后续分支漏掉。

**② `FluentWindow` 与 `NavigationInterface` 都没有页面切换信号**

二者仅定义 `displayModeChanged = pyqtSignal(NavigationDisplayMode)`。页面切换须改用 `self.stackedWidget.currentChanged`（`StackedWidget` 继承自 `QStackedWidget`）。

**③ ComboBox 回填需做存在性校验**

模型文件可能被用户删除，直接 `setCurrentText()` 会静默失败。实现中先 `w.findText(value) >= 0` 再写入，缺失时保留原值。

### 16.4 移除「翻译结果使用文言文」

| 文件 | 行 | 变更 |
|---|---|---|
| `project/config.yaml` | 63 | `gpt.prompt_content: "翻译结果使用文言文"` → `gpt.prompt_content: ""` |
| `GalTransl/DefaultProjectConfig.py` | 65 | 同上 |

保留注释与其余全部提示项（`change_prompt` / `contextNum` / `translation_guideline` / `enhance_jailbreak` / `token_limit` 等均未改动）。

因 `gpt.change_prompt: "no"`，`prompt_content` 本就不参与提示词拼装，清空无副作用。

### 16.5 验证

**自动保存**

| 测试项 | 期望 | 实际 | 通过 |
|---|---|---|---|
| 字段收集 | 35 个（9/8/14/2/2） | 35 | ✅ |
| 只读框排除 | 3 个全排除 | 全排除 | ✅ |
| SpinBox 内部编辑器排除 | 不进入字段表 | 未进入 | ✅ |
| 失焦落盘 | 写入 json | 写入 | ✅ |
| 内容未变化不写盘 | mtime 不变 | 不变 | ✅ |
| 连续 5 次失焦 | 仅 1 次写盘 | 1 | ✅ |
| 切换页面保存 | 落盘当前值 | 落盘 | ✅ |
| 独立进程重启回填 | token/prompt/combo 恢复 | 全恢复 | ✅ |
| `close()` 立即保存 | 不等去抖即写盘 | 写盘 | ✅ |
| param.txt 未被污染 | `param_qwen` 仍 233 字符 | 233 | ✅ |
| 只读框未被回填写坏 | `log_display` 仍只读 | 只读 | ✅ |

**移除文言文**

| 测试项 | 实际 | 通过 |
|---|---|---|
| UI 额外提示框初始内容 | `""`（显示占位提示文字） | ✅ |
| `config.yaml` 中 `gpt.prompt_content` | `""` | ✅ |
| 全仓库 grep「文言文」 | 0 处 | ✅ |
| 额外提示模式 | 仍为「不修改」 | ✅ |

### 16.6 本轮变更文件清单

| 文件 | 变更 |
|---|---|
| `app.py` | +`from PyQt5 import QtWidgets`; +`from qfluentwidgets import InfoBar, InfoBarPosition`; +`FormAutoSaver` 类（约 210 行）; +`AUTOSAVE_FILENAME`/`AUTOSAVE_DEBOUNCE_MS`/`AUTOSAVE_TOAST_MS` 常量; +`_initFormAutoSave()`; `initUI` 末尾调用; `closeEvent` 开头调用 `save_now()` |
| `project/config.yaml` | `gpt.prompt_content` 清空为 `""` |
| `GalTransl/DefaultProjectConfig.py` | `gpt.prompt_content` 清空为 `""` |
| `dist/VoiceTransl.app` | 重建（3.7GB，ad-hoc 签名，arm64，PYZ 6164 模块校验通过） |
