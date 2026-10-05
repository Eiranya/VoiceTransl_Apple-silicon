#!/bin/bash
# macOS 打包脚本：三段式冻结 -> 组装 VoiceTransl.app ->（可选）生成 dmg
#
# 为什么需要这个脚本，而不是直接 `pyinstaller app-macos.spec`：
#   app-macos.spec 的 datas 引用了仓库根的 `translate/` 与 `separate/`，而这两个目录
#   是 PyInstaller 的输出目标（.gitignore 只放行其中的 *.md）。干净 clone 里它们只含
#   占位文件；若忘记先跑 translate.spec / separate.spec 并把产物拷回仓库根，
#   **PyInstaller 不会报错**，只会静默打出一个缺少 `translate/translate` 与
#   `separate/separate` 的 .app —— 而 app.py 在冻结态正是靠这两个路径启动子进程，
#   于是翻译与人声分离功能整体失效（v1.30 曾因此发布出去）。
#
# 用法：
#   ./build-macos.sh          # 组装 .app
#   ./build-macos.sh dmg      # 组装 .app 并额外生成 dmg 到 dist/
#
# 环境变量：
#   PYI        PyInstaller 路径，默认 .venv/bin/pyinstaller
#   DMG_NAME   dmg 文件名（不含扩展名），默认 VoiceTransl-1.30-arm64
#
# 前置条件：`.venv` 内已按 requirements-macos.txt 装齐依赖（含 numpy / onnxruntime /
# scipy / librosa 等，否则 separate 子进程会在运行时报 ImportError）。
set -euo pipefail
cd "$(dirname "$0")"

PYI="${PYI:-.venv/bin/pyinstaller}"
DMG_NAME="${DMG_NAME:-VoiceTransl-1.30-arm64}"
APP="dist/VoiceTransl.app"
STAGES="translate separate"

# 本机（WorkBuddy 沙箱）已知的三个环境变量陷阱，与项目本身无关：
#   _           路径含非 ASCII 字符时 shell 写入的 `_` 不是合法 UTF-8，会让 Rust/C 的
#               build.rs 在 env::vars().unwrap() 处 panic
#   BASH_ENV    注入的 shim 会在每个非交互 bash 前置一套残缺的 grep/sed
#   PYTHONPATH  注入的 sitecustomize.py 会 hook os.mkdir 并在 exist_ok=True 时误抛 EEXIST
CLEAN_ENV=(env -u _ -u BASH_ENV -u PYTHONPATH)

run_pyi() { "${CLEAN_ENV[@]}" "$PYI" --noconfirm --log-level=WARN "$@"; }

# ---- 1. 冻结两个子可执行，并把产物替换进仓库根 ----------------------------------
# 仓库根的同名目录既是 datas 来源又是输出目标，因此先把其中的 *.md 占位/说明文件
# 暂存出来，替换后再放回去，保证重复构建是幂等的。
STASH="$(mktemp -d)"
trap 'rm -rf "$STASH"' EXIT

for stage in $STAGES; do
  echo "=== [freeze] $stage.spec ==="
  run_pyi "$stage.spec"
  mkdir -p "$STASH/$stage"
  if [ -d "$stage" ]; then
    cp "$stage"/*.md "$STASH/$stage/" 2>/dev/null || true
    rm -rf "$stage"
  fi
  cp -R "dist/$stage" "./$stage"
  cp "$STASH/$stage"/*.md "./$stage/" 2>/dev/null || true
  echo "    -> ./$stage ($(du -sh "./$stage" | cut -f1))"
done

# ---- 2. 组装 .app ---------------------------------------------------------------
echo "=== [freeze] app-macos.spec ==="
run_pyi app-macos.spec
du -sh "$APP"

# ---- 3. 自检：两个子可执行必须真的在包里，且能跑起来 ----------------------------
RES="$APP/Contents/Resources"
echo "=== [self-check] ==="
missing=0
for rel in "translate/translate" "separate/separate" "crispasr/crispasr" \
           "llama/llama-server" "ffmpeg/ffmpeg" "ffmpeg/ffprobe"; do
  if [ -e "$RES/$rel" ]; then
    echo "  OK   $rel"
  else
    echo "  MISS $rel"
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "自检失败：打包产物缺少运行时子程序，请检查上面的 freeze 步骤是否成功。" >&2
  exit 1
fi
"${CLEAN_ENV[@]}" "$RES/translate/translate" --help >/dev/null 2>&1 \
  && echo "  OK   translate 子进程可启动" \
  || { echo "  FAIL translate 子进程无法启动" >&2; exit 1; }
"${CLEAN_ENV[@]}" "$RES/separate/separate" --help >/dev/null 2>&1 \
  && echo "  OK   separate 子进程可启动" \
  || { echo "  FAIL separate 子进程无法启动" >&2; exit 1; }

# ---- 4. 可选：生成 dmg ----------------------------------------------------------
if [ "${1:-}" = "dmg" ]; then
  echo "=== [dmg] $DMG_NAME.dmg ==="
  STAGE_DIR="$(mktemp -d)"
  trap 'rm -rf "$STASH" "$STAGE_DIR"' EXIT
  cp -R "$APP" "$STAGE_DIR/"
  ln -s /Applications "$STAGE_DIR/Applications"
  hdiutil create -volname "VoiceTransl" -srcfolder "$STAGE_DIR" \
    -ov -format UDZO "dist/$DMG_NAME.dmg"
  du -sh "dist/$DMG_NAME.dmg"
fi

echo "=== done ==="
