# UVR（人声分离）模型目录

本目录用于放置 UVR 系列的 `.onnx` 权重（例如 `UVR-MDX-NET-Inst_HQ_3.onnx`）。

- 放入权重后点「🔄 刷新人声分离模型列表」（或重启应用），即可在「🎤 人声分离模型」下拉框中选择并使用。
- 不放置任何权重时，该下拉框为空，其余功能不受影响。
- 打包后本目录会被放进 `VoiceTransl.app/Contents/Resources/separate/`，应用同时也会扫描
  `Contents/Frameworks/separate/`；两个位置都可以放权重。最省事的做法是点设置页的
  「📁 打开UVR模型目录」按钮直接打开目标目录。

本目录同时存放打包版的人声分离子程序（`separate` 与 `_internal/`），请勿删除其中的文件。
