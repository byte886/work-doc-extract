# 知网格式提取：CAJ / KDH / HN / C8（format-caj-kdh）

知网（CNKI）下载的 `*.caj` / `*.kdh` / `*.nh` 等为私有格式，普通 PDF 工具无法直接读取。
本技能提供一条 **纯命令行、macOS 实测可用** 的提取链路，无需 CAJViewer GUI。

## 1. 格式背景（先判型）

| 后缀 | 实际格式 | 内容特征 |
|---|---|---|
| `.caj` | 可能是 CAJ / C8 / HN-A / HN-B（扩展名不可靠，以内容判定） | CAJ=原生文本+书签；C8/HN-B=图像页+原生文本页；HN-A=纯扫描图像页 |
| `.kdh` | KDH | 内嵌 PDF（最易转） |
| `.nh` | 实测可能是 HN-A | 扫描图像页+书签，无文本层 |
| `.caj`（学位论文常见） | 多为 C8 | 扫描页，转出 PDF 无文本层，需 OCR |

**判型方法**：`caj2pdf inspect <file> --json` 返回 format / variant / pages / outline；
或打开时看 CAJViewer 另存 TXT 的头部——`扫描影像` 开头说明是扫描型（无文本通道，OCR 是唯一提取路）。

## 2. 工具选型（为什么是 caj2pdf-rust）

| 方案 | 结论 |
|---|---|
| **caj2pdf-rust v0.8.1+（首选）** | GitHub `rwv/caj2pdf-rust`（MIT），crate `caj2pdf-cli`。**原生 Rust 实现，无需 jbig2dec/poppler**（Python 版在 macOS 卡死的正是 JBIG2 原生库依赖）；支持 CAJ(含书签)/KDH(内嵌PDF)/HN-A(图像页需OCR)/C8·HN-B(图像+文本页自动字体)；macOS 可 `cargo install --locked caj2pdf-cli`（需 rustc 1.88+，本机 1.95 实测 37s 编译完成）或 GitHub Releases 预编译二进制；内存有界、流式写 |
| caj2pdf-restructured（PyPI，弃用） | wheel 仅 Windows/manylinux；macOS 需源码编译 + poppler/jbig2dec 开发库，本机不满足；仅支持 CAJ 格式、HN 未完善 |
| CAJViewer GUI（最后手段） | 导出只有 CAJ/TXT 两种（TXT 为 COMPRESSTEXT 压缩布局非纯文本）；无导出 PDF；打印对话框无 macOS PDF 下拉；「一键读图」无输出。**不推荐** |

## 3. 安装

```bash
# 需要 rustc 1.88+（本机实测 1.95）
cargo install --locked caj2pdf-cli          # 装到 ~/.cargo/bin/caj2pdf
# 或下载 GitHub Releases 预编译二进制（含 58.6MB 字体包，C8/HN-B 原生文本页自动字体，离线可用）
```

## 4. 一键提取（推荐）

```bash
bash "$HOME/Doubao/skills/work-doc-extract/scripts/caj_extract.sh <input.caj> [-o out.md]"
```

内部链路：`caj2pdf convert`（转 PDF）→ PyMuPDF 渲染 200DPI PNG → macOS Vision OCR（`ocr_vision.swift`）→ 汇总 Markdown（来源头 + 分页标记 + 正文）。

**实测数据（2026-10-13，宋元耳环.caj）**：C8 格式 5 页 → 2.07MB PDF（约 2s）→ 200DPI 渲染 1760×2046/页 → Vision OCR 约 3s/页 → 全文 6,649 字（杨之水《宋元耳环》，《紫禁城》2018.01，含 15 组图注），质量高、个别字误识（基/墓、掩/捭）可读可检索。

## 5. 手动链路（分步）

```bash
caj2pdf inspect songyuan.caj --json        # Format: C8 / Pages: 5
caj2pdf songyuan.caj -o out.pdf --force    # 转换；C8/HN-B 书签未验证时输出 warning（可用 --no-bookmarks 静默）
# 渲染 + OCR
python3 - <<'EOF'
import pymupdf
doc = pymupdf.open('out.pdf')
for i, page in enumerate(doc):
    page.get_pixmap(dpi=200).save(f'/tmp/p{i+1}.png')
EOF
swift "$HOME/Doubao/skills/work-doc-extract/scripts/ocr_vision.swift" /tmp/p1.png
```

## 6. 已知坑

- **C8/HN-A 转出的 PDF 无文本层**（扫描件），必须 OCR；`pymupdf get_text` 返回空属正常，不是转换失败。
- **`warning: C8/HN-B bookmarks are not verified; wrote no outline`** 是预期警告（大纲未验证），不是错误；介意可加 `--no-bookmarks`。
- **C8/HN-B 原生文本页自动嵌入字体**（CAJViewer 7.3 Wine 预设），无需装字体；字体包 58.6MB 已含在原生二进制内、离线可用。
- **支持矩阵以官方为准**（docs.rs/crate/caj2pdf-cli → support matrix）：TEB 不能转、CAA 仅可 inspect、CAS 无样本仍未实现。
- **OCR 专有名词后处理**：考古/文博类易混字（基/墓、掩/捭、镤/鏤）用替换表修正，勿硬编码进脚本。

## 7. 与其他格式的关系

CAJ/KDH 转换成功后即变为普通 PDF，后续统一走本技能第 0 层/L1 流程（文本层直取或 OCR）。
产物命名沿用 `<原名>_extracted.md`，元信息头记录来源/链路/页数/时间。
