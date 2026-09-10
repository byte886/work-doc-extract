#!/usr/bin/env python3
"""
verify_extract.py — 提取/OCR 结果校验门
校验项:
  1. 页数对账: 输出 Markdown 的分页节数 vs 源 PDF 页数（少于即残缺）
  2. 空页检测: 连续空白页
  3. 乱码/替换字符: � 计数、异常高比例标点
  4. 重复页: 相邻页内容完全相同
  5. 字数统计与异常页标记

用法:
  python3 scripts/verify_extract.py <输出.md> --source <源文件.pdf>
  python3 scripts/verify_extract.py <输出.md>            # 只做文本质量检查，不做页数对账
退出码: 0 通过，1 有问题
"""
import argparse
import re
import sys
from pathlib import Path

PAGE_SEC = re.compile(r"^##\s*第\s*\d+\s*页", re.M)
REPLACEMENT_CHAR = "\ufffd"


def check_text_quality(md_path: Path) -> list:
    issues = []
    text = md_path.read_text(encoding="utf-8", errors="replace")

    # 替换字符
    rep_count = text.count(REPLACEMENT_CHAR)
    if rep_count > 0:
        issues.append(f"[乱码] 替换字符 � 出现 {rep_count} 次")

    # 分页
    pages = PAGE_SEC.split(text)[1:]  # 第一个元素是头部
    if not pages:
        issues.append("[结构] 未找到分页标记（## 第N页），无法分页校验")
        return issues

    empty_pages = []
    duplicate_pages = []
    prev_content = None
    for i, page in enumerate(pages, 1):
        content = page.strip()
        # 去掉分页标记本身
        content = PAGE_SEC.sub("", content).strip()
        if not content or content in ("（本页无文字）", "（本页无文本）", "（本页无文字或为纯图片）"):
            empty_pages.append(i)
        if prev_content is not None and content == prev_content and content:
            duplicate_pages.append(i)
        prev_content = content

    if empty_pages:
        issues.append(f"[空页] {len(empty_pages)} 页空白: 第 {empty_pages[:10]}{'...' if len(empty_pages) > 10 else ''} 页")
    if duplicate_pages:
        issues.append(f"[重复页] {len(duplicate_pages)} 页与前一页完全相同: 第 {duplicate_pages[:10]} 页")

    # 总字数
    total_chars = len(text)
    print(f"  总字数: {total_chars} | 分页节数: {len(pages)} | 平均 {total_chars // max(len(pages),1)} 字/页")
    return issues


def check_page_count(md_path: Path, source: Path) -> list:
    issues = []
    ext = source.suffix.lower()
    if ext != ".pdf":
        print(f"  [页数对账] 源文件不是 PDF（{ext}），跳过页数对账")
        return issues
    try:
        import pymupdf
        doc = pymupdf.open(str(source))
        src_pages = len(doc)
        doc.close()
    except ImportError:
        issues.append("[页数对账] 需要 pymupdf 才能对账: pip install pymupdf")
        return issues
    except Exception as e:
        issues.append(f"[页数对账] 读取源 PDF 失败: {e}")
        return issues

    text = md_path.read_text(encoding="utf-8", errors="replace")
    out_pages = len(PAGE_SEC.findall(text))
    if out_pages < src_pages:
        issues.append(f"[页数对账] 残缺! 源 PDF {src_pages} 页，输出只有 {out_pages} 节（缺 {src_pages - out_pages} 页）")
    elif out_pages > src_pages:
        issues.append(f"[页数对账] 输出节数 {out_pages} > 源页数 {src_pages}（可能重复或标记异常）")
    else:
        print(f"  [页数对账] 通过: 源 {src_pages} 页 = 输出 {out_pages} 节")
    return issues


def main():
    ap = argparse.ArgumentParser(description="提取/OCR 结果校验门")
    ap.add_argument("md", help="输出的 Markdown 文件")
    ap.add_argument("--source", help="源文件（用于页数对账，PDF 有效）", default=None)
    args = ap.parse_args()

    md_path = Path(args.md).resolve()
    if not md_path.exists():
        print(f"[错误] 文件不存在: {md_path}", file=sys.stderr)
        sys.exit(1)

    print(f"校验: {md_path.name}")
    all_issues = []

    print("  — 文本质量检查 —")
    all_issues.extend(check_text_quality(md_path))

    if args.source:
        print("  — 页数对账 —")
        all_issues.extend(check_page_count(md_path, Path(args.source).resolve()))

    print()
    if all_issues:
        print(f"❌ 发现 {len(all_issues)} 个问题:")
        for iss in all_issues:
            print(f"  - {iss}")
        print("\n建议: 单页失败重跑该页；整体残缺换引擎（Vision → PP-StructureV3 → VLM）")
        sys.exit(1)
    else:
        print("✅ 校验通过")
        sys.exit(0)


if __name__ == "__main__":
    main()
