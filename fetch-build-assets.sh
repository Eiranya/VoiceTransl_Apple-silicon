#!/bin/bash
# 补齐「构建所需的外部二进制资产」——这些文件不在 Git 仓库中，干净 clone 后必须先跑本脚本。
# 清单与逐项说明见 README.md 的「构建所需的外部二进制资产（不在 Git 仓库中）」一节。
#
# 用法：
#   ./fetch-build-assets.sh                      # 下载 crispasr / 对齐器 / ffmpeg，跳过 llama
#   LLAMA_ZIP_URL=<llama.cpp 的 macos-arm64 zip 直链> ./fetch-build-assets.sh
#   CRISPASR_VERSION=0.8.41 ./fetch-build-assets.sh     # 换 CrispASR 版本（sha256 校验会失败，属预期）
#
# 说明：llama.cpp 的 release 资产名随构建号变化，无法硬编码，因此需通过 LLAMA_ZIP_URL 指定，
#       或手动从 https://github.com/ggml-org/llama.cpp/releases 下载后放入 llama/。
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT" || exit 1

CRISPASR_VERSION="${CRISPASR_VERSION:-0.8.30}"
LLAMA_ZIP_URL="${LLAMA_ZIP_URL:-}"

TMP="${TMPDIR:-/tmp}/vt_fetch_assets.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP" >/dev/null 2>&1' EXIT

mkdir -p crispasr ffmpeg llama

say() { printf '%s\n' "$1"; }
die() { printf 'ERROR: %s\n' "$1"; exit 1; }

dl() {
    # dl <url> <outfile>
    say "  下载：$1"
    curl -fL --retry 3 --retry-delay 2 --progress-bar -o "$2" "$1" || die "下载失败：$1"
}

expect_sha() {
    # expect_sha <file> <sha256>  —— 返回 0 一致，1 缺失，2 不一致
    local f="$1" want="$2" got
    if [ ! -f "$f" ]; then
        say "  缺失   ${f}"
        return 1
    fi
    got="$(shasum -a 256 "$f" | awk '{print $1}')"
    if [ "$got" = "$want" ]; then
        say "  OK     ${f}（sha256 一致）"
        return 0
    fi
    say "  不一致 ${f}"
    say "         期望 ${want}"
    say "         实际 ${got}"
    return 2
}

# ---------------------------------------------------------------- CrispASR
if [ -x crispasr/crispasr ] && [ -f crispasr/libc2pa_c.dylib ]; then
    say "== CrispASR：已存在，跳过 =="
else
    say "== CrispASR ${CRISPASR_VERSION} =="
    dl "https://github.com/CrispStrobe/CrispASR/releases/download/v${CRISPASR_VERSION}/crispasr-macos.tar.gz" "$TMP/crispasr.tgz"
    mkdir -p "$TMP/crispasr_x"
    tar -xzf "$TMP/crispasr.tgz" -C "$TMP/crispasr_x" || die "解压 crispasr 失败"
    for name in crispasr crispasr-quantize libc2pa_c.dylib; do
        found="$(find "$TMP/crispasr_x" -type f -name "$name" | head -1)"
        [ -n "$found" ] || die "压缩包里找不到 ${name}（v${CRISPASR_VERSION} 的资产布局可能不同，请手动下载）"
        cp "$found" "crispasr/${name}" || die "复制 ${name} 失败"
        chmod +x "crispasr/${name}"
    done
fi

# ------------------------------------------------------- Canary CTC 对齐器
if [ -f crispasr/canary-ctc-aligner-q4_k.gguf ]; then
    say "== Canary CTC 对齐器：已存在，跳过 =="
else
    say "== Canary CTC 对齐器（约 392 MB）=="
    dl "https://huggingface.co/cstr/canary-ctc-aligner-GGUF/resolve/main/canary-ctc-aligner-q4_k.gguf" \
       "crispasr/canary-ctc-aligner-q4_k.gguf"
fi

# ------------------------------------------------------------------ FFmpeg
for n in ffmpeg ffprobe; do
    if [ -x "ffmpeg/${n}" ]; then
        say "== FFmpeg ${n}：已存在，跳过 =="
    else
        say "== FFmpeg ${n} =="
        dl "https://evermeet.cx/ffmpeg/getrelease/${n}/zip" "$TMP/${n}.zip"
        mkdir -p "$TMP/${n}_x"
        unzip -o -q "$TMP/${n}.zip" -d "$TMP/${n}_x" || die "解压 ${n} 失败（需要 unzip）"
        found="$(find "$TMP/${n}_x" -type f -name "$n" | head -1)"
        [ -n "$found" ] || die "压缩包里找不到 ${n}"
        cp "$found" "ffmpeg/${n}" || die "复制 ${n} 失败"
        chmod +x "ffmpeg/${n}"
    fi
done

# -------------------------------------------------------------- llama.cpp
say "== llama.cpp =="
if [ -f llama/llama-server ] && [ -n "$(find llama -maxdepth 1 -name 'libggml*.dylib' -print -quit 2>/dev/null)" ]; then
    say "  已存在，跳过"
elif [ -n "${LLAMA_ZIP_URL}" ]; then
    dl "${LLAMA_ZIP_URL}" "$TMP/llama.zip"
    mkdir -p "$TMP/llama_x"
    unzip -o -q "$TMP/llama.zip" -d "$TMP/llama_x" || die "解压 llama.cpp 失败"
    found="$(find "$TMP/llama_x" -type f -name 'llama-server' | head -1)"
    [ -n "$found" ] || die "压缩包里找不到 llama-server"
    cp "$found" llama/llama-server || die "复制 llama-server 失败"
    chmod +x llama/llama-server
    find "$TMP/llama_x" -type f -name 'libggml*.dylib' -exec cp {} llama/ \; || die "复制 libggml dylib 失败"
else
    say "  跳过：llama.cpp 的 release 资产名随构建号变化，脚本无法硬编码。"
    say "  方式一：LLAMA_ZIP_URL=<直链> ./fetch-build-assets.sh"
    say "  方式二：从 https://github.com/ggml-org/llama.cpp/releases 下载 macOS arm64 包，"
    say "          把 llama-server 与全部 libggml*.dylib 放进 llama/ 目录。"
    say "  ⚠️ 缺它 ./build-macos.sh 的自检会失败。"
fi

# ------------------------------------------------------------------ 校验
say ""
say "== sha256 校验 =="
fail=0
expect_sha crispasr/crispasr                       01d137cb8086acb8c201fd1ec0ca8c1417e47130f6260966d9389ced08751fd7 || fail=1
expect_sha crispasr/crispasr-quantize              9ed20af7e868f0904c4d5ab839e3dd8f05cff560e23f1dba5669c05973e63970 || fail=1
expect_sha crispasr/libc2pa_c.dylib                d16dbf18f9a66f59c0ceb61b204caca5dda21742d6e9dc304c9d0518c81ee38c || fail=1
expect_sha crispasr/canary-ctc-aligner-q4_k.gguf   43da551fd7d45c29334153bb43adcc409ad4adbf7b04c8e3bcb89200eda03790 || fail=1
expect_sha ffmpeg/ffmpeg                           0ae5e615a1454cba950d74c53d7d03a8618b79e66c442bf0a2cdad3c8a4e3427 || fail=1
expect_sha ffmpeg/ffprobe                          3a41018d224a3741e7fb177a5923847d396040f10cabb006b8c6451e2c6088da || fail=1
expect_sha llama/llama-server                      7d0829d4569b9cc765aa436585aa3626c3d79cbf46aa65b8fc820810b13068bd || fail=1

say ""
if [ "$fail" -eq 0 ]; then
    say "全部就绪。接下来：./build-macos.sh dmg"
else
    say "有文件缺失或校验不一致，请先按 README 的清单补齐后再构建。"
    exit 1
fi
