#!/bin/bash
# pdf_ocr.sh — 图片型 PDF 批量 OCR（macOS Vision）
# 泛化自高顿课程项目 batch_ocr.sh，去除项目硬编码。
#
# 流程：PyMuPDF 200DPI 逐页转 PNG → Vision OCR → 合并 Markdown（## 第N页 + ---）
# 特性：断点续跑（/tmp 分页 txt 缓存）、ETA、UTF-8 locale 兜底、可配置错字替换表、汇总报告
#
# 用法:
#   bash scripts/pdf_ocr.sh <PDF路径> [输出目录]
#   示例: bash scripts/pdf_ocr.sh ~/Documents/讲义.pdf ~/Documents/out
#
# 环境变量（可选）:
#   OCR_DPI=200          转图 DPI
#   OCR_BIN=/path/to/bin 已编译的 Vision OCR 二进制（不设则自动编译到缓存）
#   OCR_CORRECT_FILE=xxx  错字替换表（sed 格式，每行 "旧|新"，可选）
#   OCR_TMP_DIR=/tmp/...  临时分页缓存目录

set -uo pipefail
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 参数 ──
if [ $# -lt 1 ]; then
  echo "用法: bash scripts/pdf_ocr.sh <PDF路径> [输出目录]" >&2
  exit 2
fi
PDF_PATH="$1"
OUTPUT_DIR="${2:-$(dirname "$PDF_PATH")}"

if [ ! -f "$PDF_PATH" ]; then
  echo "[错误] PDF 文件不存在: $PDF_PATH" >&2
  exit 1
fi

DPI="${OCR_DPI:-200}"
TMP_DIR="${OCR_TMP_DIR:-/tmp/work_doc_extract_pages}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/work-doc-extract"
OCR_BIN="${OCR_BIN:-$CACHE_DIR/ocr_vision}"
CORRECT_FILE="${OCR_CORRECT_FILE:-}"

mkdir -p "$OUTPUT_DIR" "$TMP_DIR" "$CACHE_DIR"

PDF_BASENAME=$(basename "$PDF_PATH" .pdf)
OUTPUT_MD="$OUTPUT_DIR/${PDF_BASENAME}_OCR.md"

# ── Python 探测（优先 venv，其次系统 python3）──
PYTHON=""
for cand in "$SCRIPT_DIR/../.venv/bin/python" "$(dirname "$SCRIPT_DIR")/.venv/bin/python" python3; do
  if command -v "$cand" >/dev/null 2>&1; then
    if "$cand" -c "import pymupdf" >/dev/null 2>&1; then
      PYTHON="$cand"; break
    fi
  fi
done
if [ -z "$PYTHON" ]; then
  echo "[错误] 找不到带 pymupdf 的 Python。请先: pip install pymupdf" >&2
  echo "  或运行 bash scripts/bootstrap.sh 检查环境。" >&2
  exit 1
fi

# ── Vision OCR 二进制（编译一次，缓存复用）──
if [ ! -x "$OCR_BIN" ]; then
  echo "[编译] Vision OCR 二进制 -> $OCR_BIN"
  if ! swiftc -framework Vision -framework AppKit -framework CoreGraphics \
       "$SCRIPT_DIR/ocr_vision.swift" -o "$OCR_BIN" 2>/dev/null; then
    echo "[错误] swiftc 编译失败，确认在 macOS 且安装了 Xcode Command Line Tools" >&2
    exit 1
  fi
fi

# ── 页数 ──
TOTAL_PAGES=$("$PYTHON" -c "
import pymupdf
doc = pymupdf.open('$PDF_PATH')
print(len(doc))
doc.close()
" 2>/dev/null)
if [ -z "$TOTAL_PAGES" ] || [ "$TOTAL_PAGES" -eq 0 ] 2>/dev/null; then
  echo "[错误] 无法获取 PDF 页数（pymupdf 读取失败或文件损坏）" >&2
  exit 1
fi

echo "============================================"
echo "  PDF OCR（macOS Vision）"
echo "  PDF:    $(basename "$PDF_PATH")"
echo "  页数:   $TOTAL_PAGES"
echo "  DPI:    $DPI"
echo "  输出:   $OUTPUT_MD"
echo "  Python: $PYTHON"
echo "  开始:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

START_TIME=$(date +%s)
SUCCESS=0; SKIPPED=0; FAILED=0

# 初始化输出
{
  echo "# ${PDF_BASENAME}（OCR 文字稿）"
  echo ""
  echo "> 自动 OCR 识别 | 共 ${TOTAL_PAGES} 页 | 引擎: macOS Vision | DPI: ${DPI} | 源文件: ${PDF_PATH}"
  echo ""
} > "$OUTPUT_MD"

for ((page=1; page<=TOTAL_PAGES; page++)); do
  IMG_PATH="$TMP_DIR/page_$(printf '%03d' $page).png"
  TXT_PATH="$TMP_DIR/page_$(printf '%03d' $page).txt"

  echo "[$page/$TOTAL_PAGES] 第${page}页..."

  # 断点续跑
  if [ -f "$TXT_PATH" ] && [ -s "$TXT_PATH" ]; then
    echo "  [跳过] 已有 OCR 结果"
    SKIPPED=$((SKIPPED+1))
  else
    # PDF 转图片
    if [ ! -f "$IMG_PATH" ]; then
      "$PYTHON" -c "
import pymupdf
doc = pymupdf.open('$PDF_PATH')
page = doc[$page-1]
mat = pymupdf.Matrix($DPI/72, $DPI/72)
pix = page.get_pixmap(matrix=mat)
pix.save('$IMG_PATH')
doc.close()
" 2>/dev/null
    fi
    if [ ! -f "$IMG_PATH" ]; then
      echo "  [失败] PDF 转图片失败"
      FAILED=$((FAILED+1))
      echo "（本页转换失败）" > "$TXT_PATH"
    else
      OCR_RESULT=$("$OCR_BIN" "$IMG_PATH" 2>/dev/null)
      if [ -z "$OCR_RESULT" ] || [ "$OCR_RESULT" = "未识别到文字" ]; then
        echo "  [警告] 未识别到文字"
        echo "（本页无文字或为纯图片）" > "$TXT_PATH"
      else
        echo "$OCR_RESULT" > "$TXT_PATH"
      fi
      SUCCESS=$((SUCCESS+1))
    fi
  fi

  # 写入输出
  {
    echo "---"
    echo "## 第${page}页"
    echo ""
    cat "$TXT_PATH"
    echo ""
  } >> "$OUTPUT_MD"

  # 进度
  ELAPSED=$(( $(date +%s) - START_TIME ))
  PROCESSED=$((SUCCESS + SKIPPED + FAILED))
  if [ $PROCESSED -gt 0 ]; then
    AVG=$((ELAPSED / PROCESSED))
    REMAIN=$(( (TOTAL_PAGES - PROCESSED) * AVG ))
    echo "  [进度] ${PROCESSED}/${TOTAL_PAGES}，已用 $((ELAPSED/60))分$((ELAPSED%60))秒，预计剩余 $((REMAIN/60))分$((REMAIN%60))秒"
  fi
done

# ── 错字后处理（可选替换表）──
if [ -n "$CORRECT_FILE" ] && [ -f "$CORRECT_FILE" ]; then
  echo ""
  echo "[后处理] 应用错字替换表: $CORRECT_FILE"
  TMP_MD="$OUTPUT_MD.tmp"
  cp "$OUTPUT_MD" "$TMP_MD"
  while IFS='|' read -r old new; do
    [ -z "$old" ] && continue
    [[ "$old" =~ ^# ]] && continue
    sed -i '' "s/$old/$new/g" "$TMP_MD"
  done < "$CORRECT_FILE"
  mv "$TMP_MD" "$OUTPUT_MD"
fi

# ── 清理临时图片（保留 txt 供断点续跑）──
echo "[清理] 删除临时图片..."
rm -f "$TMP_DIR"/*.png

# ── 汇总 ──
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo ""
echo "============================================"
echo "  OCR 完成"
echo "  完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  总耗时:   $((DURATION/60))分$((DURATION%60))秒"
echo "  ----------------------------------------"
echo "  成功: $SUCCESS | 跳过: $SKIPPED | 失败: $FAILED | 总计: $TOTAL_PAGES"
echo "  输出: $OUTPUT_MD"
echo "  字数: $(wc -m < "$OUTPUT_MD" | tr -d ' ')"
echo "============================================"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
