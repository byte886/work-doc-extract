#!/usr/bin/env python3
"""ocr_rapid.py — RapidOCR (PP-OCRv6) PDF → Markdown

跨平台、CPU 即可、pip 一条命令装。作为 work-doc-extract 技能 L1 默认引擎，
替代 macOS Vision（保留为零安装备选）。

用法:
  python3 ocr_rapid.py <pdf> [-o out.md] [--dpi 200] [--max-pages N]

输出格式与本技能其他引擎一致：
  # <书名>（OCR文字稿）
  > 源文件: <abs> | 引擎: RapidOCR PP-OCRv6 | 时间: ... | 共N页
  ---
  ## 第1页
  ...

断点续跑：<pdf名>.pages/<N>.txt 存在且非空则跳过。
"""
import argparse, sys, time
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("-o", "--out", help="输出md路径，默认 <pdf名>_OCR.md")
    ap.add_argument("--dpi", type=int, default=200)
    ap.add_argument("--max-pages", type=int, default=0)
    args = ap.parse_args()

    try:
        import pymupdf
        from rapidocr import RapidOCR
    except ImportError as e:
        sys.exit(f"[错误] 缺依赖: {e}\n请执行: pip install rapidocr onnxruntime pymupdf")

    pdf_path = Path(args.pdf).resolve()
    if not pdf_path.exists():
        sys.exit(f"PDF不存在: {pdf_path}")

    out_md = Path(args.out).resolve() if args.out else pdf_path.with_name(pdf_path.stem + "_OCR.md")
    cache_dir = pdf_path.parent / (pdf_path.stem + ".pages")
    cache_dir.mkdir(exist_ok=True)

    doc = pymupdf.open(str(pdf_path))
    total = doc.page_count
    if args.max_pages > 0:
        total = min(total, args.max_pages)

    print(f"[rapidocr] {pdf_path.name} | {total}页 -> {out_md}", flush=True)
    t0 = time.time()
    ocr = RapidOCR()
    print(f"[rapidocr] 模型加载 {time.time()-t0:.1f}s", flush=True)

    with open(out_md, "w", encoding="utf-8") as f:
        f.write(f"# {pdf_path.stem}（OCR文字稿）\n\n")
        f.write(f"> 源文件: {pdf_path} | 引擎: RapidOCR PP-OCRv6 | "
                f"时间: {time.strftime('%Y-%m-%d %H:%M:%S')} | 共{total}页 | DPI {args.dpi}\n\n")

        success = skipped = 0
        t_start = time.time()
        for i in range(total):
            page_no = i + 1
            cache = cache_dir / f"{page_no:04d}.txt"
            if cache.exists() and cache.stat().st_size > 0:
                text = cache.read_text(encoding="utf-8")
                skipped += 1
            else:
                page = doc[i]
                mat = pymupdf.Matrix(args.dpi / 72, args.dpi / 72)
                pix = page.get_pixmap(matrix=mat)
                result = ocr(pix.tobytes("png"))
                lines = list(result.txts) if result.txts else []
                text = "\n".join(lines) if lines else "（本页无文字或为纯图片）"
                cache.write_text(text, encoding="utf-8")
                success += 1
                if page_no % 10 == 0 or page_no == total:
                    el = time.time() - t_start
                    print(f"  [{page_no}/{total}] 成功{success} 跳过{skipped} {el:.0f}s", flush=True)
            f.write("---\n## 第%d页\n\n%s\n\n" % (page_no, text))

    doc.close()
    print(f"[rapidocr] 完成 成功{success} 跳过{skipped} 耗时{time.time()-t_start:.0f}s "
          f"输出{out_md.stat().st_size//1024}KB", flush=True)


if __name__ == "__main__":
    main()
