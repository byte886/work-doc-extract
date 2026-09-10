#!/bin/bash
# bootstrap.sh — work-doc-extract 依赖自检
# 检测本机可用的引擎与依赖，给出状态和安装命令；不自动安装重型后端。
#
# 用法: bash scripts/bootstrap.sh

set -uo pipefail

echo "============================================"
echo "  work-doc-extract 依赖自检"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

OK=0; MISSING=0

check() {
  # check <名称> <检测命令> <安装提示>
  local name="$1" cmd="$2" hint="$3"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "  ✅ $name"
    OK=$((OK+1))
  else
    echo "  ❌ $name"
    echo "     → $hint"
    MISSING=$((MISSING+1))
  fi
}

echo "【必需：默认引擎】"
check "Python 3.10+" "python3 -c 'import sys; assert sys.version_info >= (3,10)'" "安装 Python 3.10+（macOS: brew install python@3.12）"
check "pymupdf" "python3 -c 'import pymupdf'" "pip install pymupdf"
if [ "$(uname)" = "Darwin" ]; then
  check "swift / swiftc (macOS Vision)" "command -v swiftc" "安装 Xcode Command Line Tools: xcode-select --install"
else
  echo "  ⚠️  非 macOS：Vision OCR 不可用，请用 PP-OCRv6（见下方可选）"
fi

echo ""
echo "【可选：Office 格式】"
check "python-docx (DOCX)" "python3 -c 'import docx'" "pip install python-docx"
check "python-pptx (PPTX)" "python3 -c 'import pptx'" "pip install python-pptx"
check "openpyxl (XLSX)" "python3 -c 'import openpyxl'" "pip install openpyxl"

echo ""
echo "【可选重型：PaddleOCR（默认不装，用到再装）】"
PADDLE_OK=0
if python3 -c 'import paddleocr' >/dev/null 2>&1; then
  echo "  ✅ paddleocr 已安装"
  PADDLE_OK=1
else
  echo "  ❌ paddleocr 未安装"
  echo "     → 需独立 Python 3.12 venv（系统 Python 3.13+ 暂不支持 PaddlePaddle）:"
  echo "       python3.12 -m venv ~/.venvs/paddleocr"
  echo "       source ~/.venvs/paddleocr/bin/activate"
  echo "       pip install paddlepaddle -i https://www.paddlepaddle.org.cn/packages/stable/cpu/"
  echo "       pip install 'paddleocr[doc-parser]'"
  echo "     → 详见 references/engine-paddleocr.md"
fi

echo ""
echo "【可选重型：VLM OCR（默认不装）】"
if command -v llama-server >/dev/null 2>&1; then
  LLAMA_VER=$(llama-server --version 2>/dev/null | head -1)
  echo "  ✅ llama-server 已安装: $LLAMA_VER"
  echo "     （PaddleOCR-VL GGUF 需 llama.cpp ≥ b8110）"
else
  echo "  ❌ llama-server 未安装"
  echo "     → PaddleOCR-VL GGUF 路线: brew install llama.cpp（或源码编译 ≥ b8110）"
  echo "     → 详见 references/engine-vlm-ocr.md"
fi
if command -v unlocr >/dev/null 2>&1; then
  echo "  ✅ unlocr 已安装（Unlimited-OCR GGUF 封装）"
else
  echo "  ⚪  unlocr 未安装（仅超长跨页整本需要，通常不必装）"
  echo "     → brew install whit3rabbit/tap/unlocr && brew install poppler"
fi

echo ""
echo "============================================"
echo "  汇总: 可用 $OK 项 | 缺失 $MISSING 项"
if [ "$MISSING" -gt 0 ]; then
  echo "  提示: 缺失项中，'必需'必须装；'可选重型'按 references/ 指南按需安装"
fi
echo "============================================"
