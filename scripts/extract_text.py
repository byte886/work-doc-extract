#!/usr/bin/env python3
"""
extract_text.py — 工作文档统一提取入口
判型（PDF 文本层 / Office / 图片）→ 抽取或 OCR → 统一 Markdown 输出。

用法:
  python3 scripts/extract_text.py <输入文件或目录> [-o 输出文件或目录] [--force-ocr]
  示例:
    python3 scripts/extract_text.py 讲义.pdf
    python3 scripts/extract_text.py 报告.docx -o report.md
    python3 scripts/extract_text.py ./docs_dir -o ./out_dir
    python3 scripts/extract_text.py 扫描件.pdf --force-ocr   # 跳过文本层探测，直接 OCR

设计原则:
  - 有文本层不 OCR；图片型才走 Vision
  - 可选依赖（python-docx/pptx/openpyxl）缺失时给出明确安装提示，不崩溃
  - 输出 Markdown 带来源头 + 分页标记
"""
import argparse
import csv
import os
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

# ── 依赖探测（可选库，缺失时延迟报错）──
def _try_import(name):
    try:
        return __import__(name)
    except ImportError:
        return None

pymupdf = _try_import("pymupdf")
docx_mod = _try_import("docx")
pptx_mod = _try_import("pptx")
openpyxl_mod = _try_import("openpyxl")


def header(source: Path, engine: str, extra: str = "") -> str:
    return (
        f"# {source.stem}（提取文本）\n\n"
        f"> 源文件: {source} | 引擎: {engine} | 时间: {time.strftime('%Y-%m-%d %H:%M:%S')}"
        + (f" | {extra}" if extra else "")
        + "\n\n"
    )


# ── PDF ──
def extract_pdf(path: Path, out: Path, force_ocr: bool = False) -> str:
    if pymupdf is None:
        return "[错误] 需要 pymupdf: pip install pymupdf"
    doc = pymupdf.open(str(path))
    n_pages = len(doc)

    # 文本层探测：平均每页字符数
    total_chars = 0
    for page in doc:
        total_chars += len(page.get_text("text").strip())
    avg_chars = total_chars / max(n_pages, 1)
    doc.close()

    if not force_ocr and avg_chars >= 20:
        # 文本层足够，直接抽取
        doc = pymupdf.open(str(path))
        lines = [header(path, "PyMuPDF 文本层", f"共 {n_pages} 页")]
        for i, page in enumerate(doc, 1):
            text = page.get_text("text", sort=True).strip()
            lines.append(f"---\n## 第{i}页\n\n{text if text else '（本页无文本）'}\n")
        doc.close()
        out.write_text("\n".join(lines), encoding="utf-8")
        return f"文本层抽取完成: {n_pages} 页（平均 {avg_chars:.0f} 字/页）-> {out}"

    # 图片型 PDF：调 pdf_ocr.sh
    if force_ocr:
        print(f"[判定] --force-ocr 已指定，跳过文本层探测，直接走 Vision OCR")
    else:
        print(f"[判定] 图片型 PDF（平均 {avg_chars:.0f} 字/页 < 20），走 Vision OCR")
    script = SCRIPT_DIR / "pdf_ocr.sh"
    cmd = ["bash", str(script), str(path), str(out.parent)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    # pdf_ocr.sh 输出名为 <stem>_OCR.md
    expected = out.parent / f"{path.stem}_OCR.md"
    if expected.exists() and expected != out:
        expected.rename(out)
    if result.returncode != 0 and not out.exists():
        return f"[错误] OCR 失败:\n{result.stderr[-2000:]}"
    return f"Vision OCR 完成: {n_pages} 页 -> {out}"


# ── DOCX ──
def extract_docx(path: Path, out: Path) -> str:
    if docx_mod is None:
        return "[错误] 需要 python-docx: pip install python-docx"
    doc = docx_mod.Document(str(path))
    lines = [header(path, "python-docx", f"共 {len(doc.paragraphs)} 段落")]
    for para in doc.paragraphs:
        text = para.text.strip()
        if text:
            style = para.style.name if para.style else ""
            if style.startswith("Heading"):
                level = style.replace("Heading ", "").strip() or "2"
                lines.append(f"{'#' * int(level) if level.isdigit() else '##'} {text}\n")
            else:
                lines.append(f"{text}\n")
    # 表格
    for ti, table in enumerate(doc.tables, 1):
        lines.append(f"\n### 表格 {ti}\n")
        for row in table.rows:
            cells = [c.text.strip().replace("\n", " ") for c in row.cells]
            lines.append("| " + " | ".join(cells) + " |")
        if len(table.rows) > 0:
            lines.insert(-len(table.rows), "| " + " | ".join(["---"] * len(table.rows[0].cells)) + " |")
    out.write_text("\n".join(lines), encoding="utf-8")
    return f"DOCX 抽取完成 -> {out}"


# ── PPTX ──
def extract_pptx(path: Path, out: Path) -> str:
    if pptx_mod is None:
        return "[错误] 需要 python-pptx: pip install python-pptx"
    prs = pptx_mod.Presentation(str(path))
    lines = [header(path, "python-pptx", f"共 {len(prs.slides)} 张幻灯片")]
    for i, slide in enumerate(prs.slides, 1):
        lines.append(f"---\n## 幻灯片 {i}\n")
        for shape in slide.shapes:
            if shape.has_text_frame:
                for para in shape.text_frame.paragraphs:
                    text = "".join(r.text for r in para.runs).strip()
                    if text:
                        lines.append(f"{text}\n")
            if shape.has_table:
                lines.append("\n[表格]\n")
                for row in shape.table.rows:
                    cells = [c.text.strip().replace("\n", " ") for c in row.cells]
                    lines.append("| " + " | ".join(cells) + " |")
                lines.append("")
    out.write_text("\n".join(lines), encoding="utf-8")
    return f"PPTX 抽取完成 -> {out}"


# ── XLSX ──
def extract_xlsx(path: Path, out: Path) -> str:
    if openpyxl_mod is None:
        return "[错误] 需要 openpyxl: pip install openpyxl"
    wb = openpyxl_mod.load_workbook(str(path), data_only=True, read_only=True)
    lines = [header(path, "openpyxl", f"共 {len(wb.sheetnames)} 个工作表")]
    for sheet_name in wb.sheetnames:
        ws = wb[sheet_name]
        lines.append(f"---\n## 工作表: {sheet_name}\n")
        rows = list(ws.iter_rows(values_only=True))
        if not rows:
            lines.append("（空表）\n")
            continue
        # 找最大列数
        max_cols = max(len(r) for r in rows)
        for ri, row in enumerate(rows):
            cells = ["" if v is None else str(v) for v in row]
            cells += [""] * (max_cols - len(cells))
            lines.append("| " + " | ".join(cells) + " |")
            if ri == 0:
                lines.append("| " + " | ".join(["---"] * max_cols) + " |")
        lines.append("")
    wb.close()
    out.write_text("\n".join(lines), encoding="utf-8")
    return f"XLSX 抽取完成 -> {out}"


# ── CSV ──
def extract_csv(path: Path, out: Path) -> str:
    lines = [header(path, "csv", "")]
    with open(path, newline="", encoding="utf-8-sig", errors="replace") as f:
        reader = csv.reader(f)
        for ri, row in enumerate(reader):
            lines.append("| " + " | ".join(c.strip() for c in row) + " |")
            if ri == 0:
                lines.append("| " + " | ".join(["---"] * len(row)) + " |")
    out.write_text("\n".join(lines), encoding="utf-8")
    return f"CSV 抽取完成 -> {out}"


# ── 图片（Vision OCR）──
def extract_image(path: Path, out: Path) -> str:
    if sys.platform != "darwin":
        return "[错误] 图片 OCR 当前仅支持 macOS Vision。非 mac 请安装 PP-OCRv6（见 references/engine-paddleocr.md）"
    swift_file = SCRIPT_DIR / "ocr_vision.swift"
    result = subprocess.run(
        ["swift", str(swift_file), str(path)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return f"[错误] Vision OCR 失败:\n{result.stderr[-2000:]}"
    text = result.stdout.strip() or "（未识别到文字）"
    out.write_text(header(path, "macOS Vision") + text + "\n", encoding="utf-8")
    return f"图片 OCR 完成 -> {out}"


DISPATCH = {
    ".pdf": extract_pdf,
    ".docx": extract_docx,
    ".pptx": extract_pptx,
    ".xlsx": extract_xlsx,
    ".xls": extract_xlsx,
    ".csv": extract_csv,
    ".png": extract_image,
    ".jpg": extract_image,
    ".jpeg": extract_image,
    ".tiff": extract_image,
    ".bmp": extract_image,
}


def process_one(path: Path, out_path: Path, force_ocr: bool = False) -> str:
    ext = path.suffix.lower()
    handler = DISPATCH.get(ext)
    if handler is None:
        return f"[跳过] 不支持的格式: {path}（支持: {', '.join(sorted(DISPATCH.keys()))}）"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if ext == ".pdf":
        return handler(path, out_path, force_ocr=force_ocr)
    return handler(path, out_path)


def main():
    ap = argparse.ArgumentParser(description="工作文档统一提取入口")
    ap.add_argument("input", help="输入文件或目录")
    ap.add_argument("-o", "--output", help="输出文件（单文件）或目录（批量）", default=None)
    ap.add_argument("--force-ocr", action="store_true", help="PDF 跳过文本层探测，直接 OCR")
    args = ap.parse_args()

    inp = Path(args.input).resolve()
    if not inp.exists():
        print(f"[错误] 输入不存在: {inp}", file=sys.stderr)
        sys.exit(1)

    if inp.is_file():
        out = Path(args.output).resolve() if args.output else inp.parent / f"{inp.stem}_extracted.md"
        print(process_one(inp, out, args.force_ocr))
    else:
        out_dir = Path(args.output).resolve() if args.output else inp.parent / f"{inp.name}_extracted"
        out_dir.mkdir(parents=True, exist_ok=True)
        files = sorted(f for f in inp.rglob("*") if f.is_file() and f.suffix.lower() in DISPATCH)
        if not files:
            print(f"[提示] 目录中没有可处理的文件: {inp}")
            return
        print(f"[批量] 找到 {len(files)} 个文件，输出到 {out_dir}")
        for f in files:
            rel = f.relative_to(inp)
            out = out_dir / rel.with_suffix(".md")
            print(f"  - {rel}: {process_one(f, out, args.force_ocr)}")


if __name__ == "__main__":
    main()
