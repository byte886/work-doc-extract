#!/usr/bin/env bash
# caj_extract.sh — 知网 CAJ/KDH/HN/C8 文件 → 可搜索 Markdown
#
# 链路：caj2pdf-rust（CLI，原生支持 CAJ/KDH/HN/C8，无需 jbig2dec/poppler）
#   → caj2pdf convert 转 PDF → PyMuPDF 渲染 200DPI PNG → macOS Vision OCR → 汇总 Markdown
#
# 用法：
#   bash caj_extract.sh <input.caj> [-o out.md] [--keep-png]
#   输出默认 <input 同名>_extracted.md，PDF 落 /tmp 或输出目录同级
#
# 前置：
#   caj2pdf（$HOME/.cargo/bin/caj2pdf，rustc 1.88+ 环境可 cargo install --locked caj2pdf-cli）
#   python3 + pymupdf；macOS Vision（swift 运行 scripts/ocr_vision.swift）
#
# 平台：macOS 实测可用（Darwin）。非 Darwin 停止并提示。

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OCR_VISION="$SKILL_DIR/scripts/ocr_vision.swift"

INPUT=""
OUT_MD=""
KEEP_PNG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) OUT_MD="$2"; shift 2 ;;
    --keep-png) KEEP_PNG=1; shift ;;
    *) INPUT="$1"; shift ;;
  esac
done

[[ -z "$INPUT" ]] && { echo "用法: bash caj_extract.sh <input.caj> [-o out.md] [--keep-png]"; exit 2; }
[[ ! -f "$INPUT" ]] && { echo "文件不存在: $INPUT"; exit 2; }

# 平台守卫
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "本技能当前仅在 macOS(Darwin) 实测可用；Windows/Linux 未适配，请另行适配后再跑。" >&2
  exit 3
fi

# 工具检查
CAJ2PDF="${CAJ2PDF:-$HOME/.cargo/bin/caj2pdf}"
if [[ ! -x "$CAJ2PDF" ]]; then
  echo "未找到 caj2pdf。安装（需 rustc 1.88+，本机实测 1.95 正常）：" >&2
  echo "  cargo install --locked caj2pdf-cli" >&2
  exit 3
fi
command -v python3 >/dev/null || { echo "缺 python3"; exit 3; }
python3 -c "import pymupdf" 2>/dev/null || { echo "缺 pymupdf：pip install pymupdf"; exit 3; }

BASE="$(basename "$INPUT")"
STEM="${BASE%.*}"
DIR="$(dirname "$INPUT")"
OUT_MD="${OUT_MD:-$DIR/${STEM}_extracted.md}"
TMP="$(mktemp -d /tmp/caj_extract.XXXXXX)"
trap '[[ $KEEP_PNG -eq 0 ]] && rm -rf "$TMP"' EXIT

echo "[1/4] inspect: $INPUT"
"$CAJ2PDF" inspect "$INPUT" --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print('  format:', d.get('format'), '| pages:', d.get('pages', 'unknown'))" || echo "  (inspect 不可用，继续)"

echo "[2/4] convert CAJ → PDF"
"$CAJ2PDF" "$INPUT" -o "$TMP/${STEM}.pdf" --force 2>&1 | grep -v "bookmarks are not verified" || true
PAGES="$(python3 -c "import pymupdf; print(len(pymupdf.open('$TMP/${STEM}.pdf')))")"
echo "  页数: $PAGES"

echo "[3/4] 渲染 200DPI + Vision OCR"
mkdir -p "$TMP/png"
python3 - "$TMP/${STEM}.pdf" "$TMP/png" <<'PYEOF'
import sys, pymupdf, os
pdf, outdir = sys.argv[1], sys.argv[2]
doc = pymupdf.open(pdf)
for i, page in enumerate(doc):
    pix = page.get_pixmap(dpi=200)
    pix.save(os.path.join(outdir, f"p{i+1}.png"))
PYEOF

OCR_TEXT="$TMP/ocr.txt"
for f in "$TMP/png"/p*.png; do
  swift "$OCR_VISION" "$f" 2>/dev/null || echo "(OCR 失败: $f)"
  echo ""
done > "$OCR_TEXT"

OCR_PAGES="$(grep -c '^$' "$OCR_TEXT" || true)"
[[ "$OCR_PAGES" -lt "$PAGES" ]] && echo "  警告: OCR 页数($OCR_PAGES) < PDF 页数($PAGES)，可能有缺页"

echo "[4/4] 汇总 Markdown"
python3 - "$INPUT" "$PAGES" "$OCR_TEXT" "$OUT_MD" <<'PYEOF'
import sys, datetime
src, pages, ocr_txt, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
raw = open(ocr_txt).read()
# 按空行切页（Vision 逐页输出以空行分隔）
import re
blocks = [b.strip() for b in re.split(r'\n\s*\n', raw) if b.strip()]
header = f"""# {src.split('/')[-1]} · CAJ 提取稿

> 来源：`{src}`（知网格式，{pages} 页）
> 提取链路：caj2pdf-rust CLI 转 PDF → PyMuPDF 渲染 200DPI → macOS Vision OCR（zh-Hans+en-US）
> 质量：OCR 全文，个别字误识未逐字校对，引用前请回看原 PDF
> 处理时间：{datetime.date.today()}

---
"""
out_parts = [header]
for i, b in enumerate(blocks[:int(pages)]):
    out_parts.append(f"## 第 {i+1} 页\n\n{b}\n\n---")
open(out, 'w').write('\n'.join(out_parts))
print(f"  输出: {out}（{len(blocks)} 页块）")
PYEOF

echo "完成 ✅"
