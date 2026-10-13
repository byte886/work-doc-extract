# 电子书格式提取：mobi / epub（format-ebook-mobi）

电子书（`.mobi` / `.azw` / `.azw3` / `.epub`）→ 可搜索 Markdown 的本地提取方案。
配合 `scripts/ebook_extract.py` 使用（也可手动按本文链路执行）。

## 1. 格式背景

| 后缀 | 实际结构 | 提取难度 |
|---|---|---|
| `.mobi`（老式） | PalmDB 容器 + MOBI/EXTH 头 + **PalmDOC 压缩**（LZ77 变体）的 HTML 文本记录 | 中：需解 PalmDB + PalmDOC |
| `.azw` / `.azw3` / `.kf8` | Kindle 专有，kf8 是 MOBI8 变体（含混合排版） | 高：python-mobi 可能不支持 kf8，需 calibre |
| `.epub` | zip 包 + OPF 清单 + XHTML 章节 | 低：标准库 zipfile + XML 即可 |

## 2. 工具选型

| 方案 | 结论 |
|---|---|
| **python-mobi 库 + html.parser（首选）** | `pip install mobi`（约 2MB）；`mobi.extract()` 返回 `(tempdir, html路径)` 已含 PalmDB 解析 + PalmDOC 解压；html.parser 抽正文。**纯 Python、无需 calibre、无 GUI**。实测（2026-10-13）：金融炼金术-索罗斯.mobi → 196,569 字符 md，与既有 PDF 提取同源同译本、差异 0.18%（前言页+换行） |
| calibre `ebook-convert`（重型备选） | 支持全格式含 azw3/kf8，但需安装 calibre（brew cask calibre）；转换是"再封装"而非"提取正文"，体积大。**仅当 mobi 库解不了 kf8/azw3 时才装** |
| 自写 PalmDOC 解压 | 不推荐：LZ77 变体细节多、易错；mobi 库已封装 |

## 3. 一键提取（推荐）

```bash
python3 "$HOME/Doubao/skills/work-doc-extract/scripts/ebook_extract.py 金融炼金术.mobi [-o out.md]"
```

- `.mobi`：mobi 库解包（自动处理 PalmDB + PalmDOC）→ HTML 抽正文 → Markdown
- `.epub`：zipfile 读 OPF spine → XHTML 抽正文 → Markdown（标准库，零额外依赖）

## 4. 手动链路（分步，mobi）

```bash
pip install mobi
python3 - <<'EOF'
import mobi, html
from html.parser import HTMLParser
tempdir, filepath = mobi.extract("book.mobi")   # filepath 即解出的 HTML
# 然后用 TextExtractor（见 ebook_extract.py）抽正文，或直接阅读 HTML
EOF
```

## 5. 已知坑

- **mobi 库只认老式 mobi**：kf8/azw3（MOBI8）可能解包失败或乱码 → 此时换 calibre：`ebook-convert book.azw3 out.txt`。
- **PalmDOC 压缩**：老式 mobi 正文是 PalmDOC LZ77 压缩的 HTML，必须经 mobi 库解压；直接 `strings` 提取会得到乱码（此为常见误区）。
- **正文 vs 全量**：`_extracted.md` 是抽正文（去 script/style/nav，块级换行），图表与复杂排版不保留；若需完整还原（含图片/目录），改用 calibre 输出 epub 或 html 再转。
- **DRM**：有 DRM 的 Kindle 书 mobi 库/calibre 都解不了，需先脱 DRM（本技能不提供）。
- **同源双格式**：同一本书若有 PDF 和 mobi 两个来源，提取后应做交叉比对（如短语抽样），一致则互证、差异仅前言/换行时标注"互为备份"。

## 6. 与其他格式的关系

mobi/epub 提取后即得到 Markdown 正文，后续统一进知识库管线（OKF 摄入、分类、入库），与 PDF/CAJ 提取产物同构。
产物命名沿用 `<原名>_extracted.md`，元信息头记录来源/链路/时间。
