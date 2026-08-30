
<p align="center">
	<img src="avatar.png" alt="Logo" width="160" />
</p>

<h1><p align='center' >VoiceTransl 聆译</p></h1>
<div align=center><img src="https://img.shields.io/github/v/release/Eiranya/VoiceTransl_Apple-silicon"/>   <img src="https://img.shields.io/github/license/shinnpuru/VoiceTransl"/>   <img src="https://img.shields.io/github/stars/shinnpuru/VoiceTransl"/></div>

VoiceTransl 聆译是一站式离线 AI 视频字幕生成和翻译软件，支持 **macOS（Apple Silicon）**。从视频下载，音频提取，听写打轴，字幕翻译，视频合成，字幕总结各个环节为翻译者提供便利。本项目基于 [GalTransl](https://github.com/xd2333/GalTransl)，采用 GPLv3 许可，是 [shinnpuru/VoiceTransl](https://github.com/shinnpuru/VoiceTransl) 的 macOS 移植版本。

## 特色

* 支持多种翻译模型，包括在线模型（任意 OpenAI 兼容接口）和本地模型（Sakura、GalTransl 及 Ollama、Llama.cpp）。
* 支持多种输入格式，包括音频、视频、SRT 字幕。
* 支持多种输出格式，包括 SRT 字幕、LRC 字幕。
* 支持多种语言，包括日语，英语，韩语，俄语，法语。
* 使用 CrispASR 的 Qwen3-ASR 与强制对齐工作流生成带时间轴字幕。
* 支持 VAD（语音活动检测），自动识别音频中的语音段落。
* 支持字典功能，可以自定义翻译字典，替换输入输出。
* 支持世界书/台本输入，可以自定义翻译参考资料。
* 支持从 YouTube/Bilibili 及媒体链接直接下载视频。
* 支持文件和链接批量处理，自动识别文件类型。
* 支持音频切分，字幕合并和视频合成。
* 支持视频总结，将视频内容总结为带时间轴简短的文本。
* 支持人声分离，将人声和伴奏分离，支持多种模型。

<div align=center><img src="title.jpg" alt="macOS 主界面截图" style="width:512px;"/></div>

## 在线镜像

打开即用的 AI 翻译，与配置环境说拜拜，推荐大家使用优云智算算力租赁平台。万卡 4090 超多好玩免费的镜像给大家免费体验，高性价比算力租赁平台，上市公司 ucloud 旗下，专业有保障。点击链接直达[镜像地址](https://www.compshare.cn/images/compshareImage-16qc028dgfoh?referral_code=1RFfR2FQ2FyEVRJMyrOn5d&ytag=GPU_YY-GH_simple)，使用说明请看
[视频教程](https://b23.tv/qN9bDHi)。使用昕蒲邀请链接注册可得实名 20 增金+链接注册 20+高校企业认证再得 10，还可享 95 折，4090 一小时只要 1.98 ：[邀请链接](https://passport.compshare.cn/register?referral_code=1RFfR2FQ2FyEVRJMyrOn5d&ytag=simple_bilibili)

## 下载地址

下载最新版本的 [VoiceTransl for macOS](https://github.com/Eiranya/VoiceTransl_Apple-silicon/releases/)，将 `VoiceTransl.app` 拖入「应用程序」即可使用。

## 使用说明

使用说明请见 [视频教程](https://www.bilibili.com/video/BV12FjN6iEmz)。

## 模型文件

本仓库仅包含源代码与运行时引擎，**不包含主 ASR 模型权重文件**。以下组件已随 dmg 捆绑，开箱即用：

- **CrispASR 推理引擎**（`crispasr/crispasr`）
- **llama.cpp 推理库**（`llama/`）
- **FFmpeg 多媒体工具**（`ffmpeg/ffmpeg`、`ffmpeg/ffprobe`）
- **Canary CTC 强制对齐器 GGUF**（`crispasr/canary-ctc-aligner-q4_k.gguf`）

首次运行前，只需将主语音识别模型（Qwen3-ASR-1.7B 等）下载并放入 `crispasr/` 目录。该目录位于应用包内 `VoiceTransl.app/Contents/Resources/crispasr/`（右键应用 →「显示包内容」即可访问；若应用安装在「应用程序」中，需先解除只读或将该目录改为可写）。

| 文件 | 放置路径（相对 `crispasr/`） | 大致体积 | 来源 / 状态 |
| --- | --- | --- | --- |
| CrispASR 推理引擎 | `crispasr/crispasr` | ~38 MB | [CrispStrobe/CrispASR](https://github.com/CrispStrobe/CrispASR)（下载 `crispasr-macos.tar.gz`，**仅 arm64**）— 已捆绑 |
| Qwen3-ASR-1.7B 语音识别模型（GGUF, q4_k） | `crispasr/qwen3-asr-1.7b-q4_k.gguf` | ~1.4 GB | [cstr/qwen3-asr-1.7b-GGUF](https://huggingface.co/cstr/qwen3-asr-1.7b-GGUF) — 需下载 |
| Qwen3-ASR-1.7B 日语动画微调（GGUF, q4_k，可选） | `crispasr/qwen3-asr-1.7b-ja-anime-q4_k.gguf` | ~1.4 GB | [cstr/qwen3-asr-1.7b-GGUF](https://huggingface.co/cstr/qwen3-asr-1.7b-GGUF) — 可选 |
| Canary CTC 强制对齐器（GGUF, q4_k） | `crispasr/canary-ctc-aligner-q4_k.gguf` | ~392 MB | [cstr/canary-ctc-aligner-GGUF](https://huggingface.co/cstr/canary-ctc-aligner-GGUF) — **已随 dmg 捆绑** |
| FFmpeg 多媒体工具 | `ffmpeg/ffmpeg`、`ffmpeg/ffprobe` | ~153 MB | 已随 dmg 捆绑 |
| llama.cpp 推理库 | `llama/`（含 `libggml*`、`llama-server`） | ~17 MB | 已随 dmg 捆绑 |

> 说明：CrispASR 上游仅提供 **arm64** 版本，因此本 macOS 构建仅支持 Apple Silicon（M 系列）芯片；Intel Mac 无法使用该 ASR 引擎。

**缺失文件时的现象：**
- 未放置 `crispasr/crispasr` 或主 ASR 模型（`qwen3-asr-1.7b-q4_k.gguf`）：开始听写/翻译时会报错提示找不到 ASR 引擎或模型，无法生成字幕；程序其余界面仍可正常打开。
- 未放置 `ffmpeg/ffmpeg`：提取音频、视频合成等依赖 ffmpeg 的步骤会失败，程序会提示「未找到 ffmpeg」。
- `llama/` 目录缺失：若使用 llama.cpp 后端做对齐会报错；使用 CrispASR 对齐流程时不受影响。
- Canary 对齐器已随 dmg 捆绑，无需单独下载；如误删 `crispasr/canary-ctc-aligner-q4_k.gguf`，CrispASR 断句对齐将无法工作（SRT 时间戳会被清零）。

主 ASR 模型等权重文件（`.gguf`）已在 `.gitignore` 中忽略，不会随仓库提交；请按上表自行下载补充。

## 对比原版 VoiceTransl 的修改

本仓库是 [shinnpuru/VoiceTransl](https://github.com/shinnpuru/VoiceTransl)（原 Windows 版）的 macOS 移植分支，主要修改如下：

| 项 | 原版 VoiceTransl（Windows） | 本 macOS 分支 |
| --- | --- | --- |
| 支持平台 | Windows（x64） | macOS（Apple Silicon / arm64） |
| 安装形式 | Windows 安装程序（NSIS），运行 `VoiceTransl.exe` | `.dmg` 磁盘镜像，拖入「应用程序」 |
| ASR 引擎 | 早期 whisper.cpp / faster-whisper；新版本亦采用 CrispASR | CrispASR（Qwen3-ASR + CTC 强制对齐），已捆绑 |
| 运行时引擎 | 需自行配置 | CrispASR / llama.cpp / FFmpeg 随 dmg 捆绑 |
| 强制对齐器 | 视版本而定 | Canary CTC 对齐器 GGUF 已随 dmg 捆绑（开箱即用） |
| 界面框架 | PyQt5 + PyQt-Fluent-Widgets | 同，但适配 macOS HIG：系统原生红绿灯标题栏、Finder 风格导航面板 |
| 模型目录 | 多为 `qwen3-asr-1.7b/` 等 | 本分支将 ASR 模型与对齐器统一放在 `crispasr/` 目录 |
| 系统关机 / 路径 | Windows 专用逻辑 | 改用 `osascript` 等 macOS 原生调用 |
| 代码签名 | 作者签名 / 公证 | ad-hoc 签名，未公证（暂无 Developer ID 证书） |

> 说明：本分支基于 upstream v1.30（已含 CrispASR），其余翻译 / 对齐能力与原版一致。

## 声明

本软件仅供学习交流使用，不得用于商业用途。本软件不对任何使用者的行为负责，不保证翻译结果的准确性。使用本软件即代表您同意自行承担使用本软件的风险，包括但不限于版权风险、法律风险等。请遵守当地法律法规，不要使用本软件进行任何违法行为。

## 贡献者

@[shinnpuru](https://github.com/shinnpuru) @[MurthiNext](https://github.com/MurthiNext)

## 如果对你有帮助的话请给一个Star!

![Star History Chart](https://star-history.dera.page/svg?repos=shinnpuru/VoiceTransl&type=Date)
