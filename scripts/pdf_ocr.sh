#!/bin/bash
# pdf_ocr.sh — 图片型 PDF 批量 OCR（默认 RapidOCR PP-OCRv6，macOS Vision 兜底）
#
# 用法:
#   bash scripts/pdf_ocr.sh <PDF路径> [输出目录]
#
# 引擎选择（按优先级）：
#   1. RapidOCR（默认，跨平台，pip install rapidocr onnxruntime pymupdf）
#   2. macOS Vision（零安装备选，仅 macOS，需 swiftc 编译）
#
# 环境变量:
#   OCR_ENGINE=rapid|vision   强制指定引擎（默认 rapid）
#   OCR_DPI=200
#   OCR_CORRECT_FILE=xxx      错字替换表（sed 格式，"旧|新"每行一条）

set -uo pipefail
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 1 ]; then
  echo "用法: bash scripts/pdf_ocr.sh <PDF路径> [输出目录]" >&2
  exit 2
fi
PDF_PATH="$1"
OUTPUT_DIR="${2:-$(dirname "$PDF_PATH")}"
[ -f "$PDF_PATH" ] || { echo "[错误] PDF 不存在: $PDF_PATH" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR"

PDF_BASENAME=$(basename "$PDF_PATH" .pdf)
OUTPUT_MD="$OUTPUT_DIR/${PDF_BASENAME}_OCR.md"
DPI="${OCR_DPI:-200}"
CORRECT_FILE="${OCR_CORRECT_FILE:-}"

# ── 探测 Python（优先技能本地 venv，其次系统 python3）──
PYTHON=""
for cand in "$SCRIPT_DIR/../.venv/bin/python" "$(which python3)"; do
  [ -x "$cand" ] || continue
  if "$cand" -c "import pymupdf" >/dev/null 2>&1; then
    PYTHON="$cand"; break
  fi
done
[ -z "$PYTHON" ] && { echo "[错误] 找不到带 pymupdf 的 Python: pip install pymupdf" >&2; exit 1; }

ENGINE="${OCR_ENGINE:-rapid}"

# ── 引擎1: RapidOCR ──
if [ "$ENGINE" = "rapid" ]; then
  if "$PYTHON" -c "import rapidocr, onnxruntime" >/dev/null 2>&1; then
    echo "[引擎] RapidOCR PP-OCRv6  ->  $OUTPUT_MD"
    exec "$PYTHON" "$SCRIPT_DIR/ocr_rapid.py" "$PDF_PATH" -o "$OUTPUT_MD" --dpi "$DPI"
  else
    echo "[提示] RapidOCR 未装（pip install rapidocr onnxruntime），回退 macOS Vision" >&2
    ENGINE="vision"
  fi
fi

# ── 引擎2: macOS Vision（兜底）──
if [ "$ENGINE" = "vision" ]; then
  TMP_DIR="${OCR_TMP_DIR:-/tmp/work_doc_extract_pages}"
  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/work-doc-extract"
  OCR_BIN="$CACHE_DIR/ocr_vision"
  mkdir -p "$TMP_DIR" "$CACHE_DIR"

  if [ ! -x "$OCR_BIN" ]; then
    echo "[编译] Vision OCR -> $OCR_BIN"
    if ! swiftc -framework Vision -framework AppKit -framework CoreGraphics \
         "$SCRIPT_DIR/ocr_vision.swift" -o "$OCR_BIN" 2>/dev/null; then
      echo "[错误] swiftc 编译失败（需 macOS + Xcode CLI）。请装 RapidOCR: pip install rapidocr onnxruntime" >&2
      exit 1
    fi
  fi

  TOTAL_PAGES=$("$PYTHON" -c "import pymupdf; print(len(pymupdf.open('$PDF_PATH')))" 2>/dev/null)
  echo "[引擎] macOS Vision | $TOTAL_PAGES 页 | DPI $DPI -> $OUTPUT_MD"

  {
    echo "# ${PDF_BASENAME}（OCR 文字稿）"
    echo ""
    echo "> 自动 OCR | 共 ${TOTAL_PAGES} 页 | 引擎: macOS Vision | DPI: ${DPI}"
    echo ""
  } > "$OUTPUT_MD"

  for ((page=1; page<=TOTAL_PAGES; page++)); do
    IMG="$TMP_DIR/page_$(printf '%03d' $page).png"
    TXT="$TMP_DIR/page_$(printf '%03d' $page).txt"
    if [ ! -s "$TXT" ]; then
      "$PYTHON" -c "
import pymupdf
d=pymupdf.open('$PDF_PATH'); p=d[$page-1]
p.get_pixmap(matrix=pymupdf.Matrix($DPI/72,$DPI/72)).save('$IMG')
d.close()" 2>/dev/null
      R=$("$OCR_BIN" "$IMG" 2>/dev/null)
      echo "${R:-（本页无文字）}" > "$TXT"
      rm -f "$IMG"
    fi
    { echo "---"; echo "## 第${page}页"; echo ""; cat "$TXT"; echo ""; } >> "$OUTPUT_MD"
  done
  echo "[Vision] 完成 -> $OUTPUT_MD"
fi

# 错字后处理
if [ -n "$CORRECT_FILE" ] && [ -f "$CORRECT_FILE" ]; then
  while IFS='|' read -r old new; do
    [ -z "$old" ] || [[ "$old" =~ ^# ]] && continue
    sed -i '' "s/$old/$new/g" "$OUTPUT_MD"
  done < "$CORRECT_FILE"
fi
