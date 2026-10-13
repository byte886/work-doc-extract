#!/usr/bin/env python3
"""ebook_extract.py — mobi / epub 电子书 → 可搜索 Markdown

链路：
  .mobi → python-mobi 库解包（PalmDB + PalmDOC 解压 → HTML）→ HTML 抽正文 → Markdown
  .epub → zipfile 读取 OPF 清单 → XHTML 抽正文 → Markdown

用法：
  python3 ebook_extract.py <book.mobi|book.epub> [-o out.md]

依赖：
  mobi（pip install mobi，约 2MB，含 beautifulsoup4/lxml）；epub 走标准库

实测（2026-10-13）：金融炼金术-索罗斯.mobi → 555KB md / 196,569 字符，
  与既有 PDF 提取产物同源同译本（差异 0.18%，前言页+换行差异），互为备份。
"""
import sys, os, re, html as htmlmod, argparse, zipfile, datetime
from html.parser import HTMLParser

def extract_mobi(path):
    """mobi 库解包 → 返回 HTML 文本"""
    try:
        import mobi
    except ImportError:
        sys.exit("缺 mobi 库：pip install mobi")
    tempdir, filepath = mobi.extract(path)
    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

class TextExtractor(HTMLParser):
    """抽取 HTML 正文文本（跳过 script/style/注释），保留块级换行"""
    BLOCK = {"p", "div", "br", "h1", "h2", "h3", "h4", "li", "tr", "blockquote", "section"}
    SKIP = {"script", "style", "head", "title", "nav"}
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts, self.skip_depth, self.block_open = [], 0, False
    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip_depth += 1
        elif not self.skip_depth and tag in self.BLOCK:
            if self.block_open:
                self.parts.append("\n")
            self.block_open = False
    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skip_depth:
            self.skip_depth -= 1
        elif not self.skip_depth and tag in self.BLOCK:
            self.parts.append("\n")
            self.block_open = True
    def handle_data(self, data):
        if not self.skip_depth:
            self.parts.append(data)
    def text(self):
        raw = "".join(self.parts)
        return re.sub(r"\n{3,}", "\n\n", raw).strip()

def extract_epub(path):
    """epub：读取 OPF spine → 拼接 XHTML → 抽正文"""
    z = zipfile.ZipFile(path)
    names = z.namelist()
    # 找 OPF
    opf = next((n for n in names if n.endswith(".opf")), None)
    if not opf:
        sys.exit("epub 中未找到 OPF 清单")
    import xml.etree.ElementTree as ET
    root = ET.fromstring(z.read(opf))
    ns = {"x": "http://www.idpf.org/2007/opf"}
    hrefs = [i.attrib.get("href") for i in root.findall(".//x:itemref", ns)]
    base = os.path.dirname(opf)
    texts = []
    for h in hrefs:
        if not h:
            continue
        p = os.path.normpath(os.path.join(base, h))
        if p not in names:
            continue
        data = z.read(p)
        try:
            s = data.decode("utf-8")
        except UnicodeDecodeError:
            s = data.decode("utf-8", errors="replace")
        ex = TextExtractor(); ex.feed(s)
        texts.append(ex.text())
    return "\n\n".join(t for t in texts if t)

def main():
    ap = argparse.ArgumentParser(description="mobi/epub → Markdown")
    ap.add_argument("input")
    ap.add_argument("-o", "--output")
    a = ap.parse_args()
    if not os.path.isfile(a.input):
        sys.exit(f"文件不存在: {a.input}")
    ext = os.path.splitext(a.input)[1].lower()
    stem = os.path.splitext(os.path.basename(a.input))[0]
    out = a.output or os.path.join(os.path.dirname(a.input), f"{stem}_extracted.md")

    if ext == ".mobi":
        raw = extract_mobi(a.input)
        ex = TextExtractor(); ex.feed(raw)
        body = ex.text()
        chain = "python-mobi 解包(PalmDB+PalmDOC) → HTML 抽正文"
    elif ext == ".epub":
        body = extract_epub(a.input)
        chain = "zipfile 读 OPF spine → XHTML 抽正文"
    else:
        sys.exit(f"不支持格式 {ext}（支持 .mobi / .epub）")

    header = f"""# {stem} · 电子书提取稿

> 来源：`{a.input}`（{ext[1:].upper()}）
> 提取链路：{chain}
> 质量：正文文本，图表/版式不保留；引用前请与原书核对
> 处理时间：{datetime.date.today()}

---
"""
    with open(out, "w", encoding="utf-8") as f:
        f.write(header + "\n\n" + body)
    print(f"输出: {out}")
    print(f"正文字符: {len(body)}，行数: {body.count(chr(10))}")

if __name__ == "__main__":
    main()
