# Office 文档格式提取指南（DOCX / PPTX / XLSX / CSV）

Office 格式永远直接解析，不走 OCR（除非是扫描后塞进 Word 的图片，那应先提取图片再 OCR）。

## 一、格式与工具对照

| 格式 | 首选工具 | 备选（macOS） | 输出 |
|---|---|---|---|
| DOCX | python-docx | textutil（macOS 原生） | Markdown（标题层级+段落+表格） |
| PPTX | python-pptx | — | Markdown（按幻灯片分节+文本+表格） |
| XLSX | openpyxl | — | Markdown（按工作表分节+表格） |
| CSV | csv（标准库） | — | Markdown 表格 |
| DOC（旧版） | textutil（macOS）或 LibreOffice 转换 | — | 先转 DOCX 再解析 |
| PPT（旧版） | LibreOffice 转换 | — | 先转 PPTX 再解析 |
| XLS（旧版） | xlrd（仅读）或 LibreOffice 转换 | — | 先转 XLSX 再解析 |

## 二、安装

```bash
pip install python-docx python-pptx openpyxl
# 旧版格式需要 LibreOffice: brew install --cask libreoffice
```

`extract_text.py` 已内置这些格式的解析，缺失依赖时会给出明确提示而不崩溃。

## 三、各格式提取要点

### 3.1 DOCX
- 标题层级：读取 `paragraph.style.name`（Heading 1/2/3...），转成对应 `#` 数量
- 表格：逐行读取 `table.rows`，单元格用 `cell.text`，转 Markdown 表格
- 图片：python-docx 不直接提取图片文字；如果文档里是扫描图片，需先 `unzip document.docx` 取出 `word/media/*.png` 再 OCR
- 页眉页脚：默认不提取（通常无价值），需要时遍历 `section.header` / `section.footer`

### 3.2 PPTX
- 按幻灯片分节：`## 幻灯片 N`
- 文本框：遍历 `slide.shapes`，有 `has_text_frame` 的逐段落读取
- 表格：`shape.has_table`，逐行读取
- 备注：`slide.notes_slide.notes_text_frame.text`（默认不提取，需要时加）
- 图片中的文字：不提取（需 OCR）

### 3.3 XLSX
- 按工作表分节：`## 工作表: SheetName`
- 用 `data_only=True` 读取计算后的值（而非公式）；需要公式时用 `data_only=False`
- `read_only=True` 大文件流式读取，省内存
- 空单元格输出为空字符串
- 合并单元格：openpyxl 只在左上角单元格有值，其余为空；提取时注意
- 多工作表：遍历 `wb.sheetnames`

### 3.4 CSV
- 用 `utf-8-sig` 编码打开（自动去掉 BOM）
- 第一行作为表头，第二行插入 `|---|` 分隔
- 含逗号/换行的字段用引号包裹，csv 标准库自动处理

## 四、旧版格式转换（DOC/PPT/XLS）

macOS 上用 textutil 转 DOC：
```bash
textutil -convert docx -output output.docx input.doc
```

LibreOffice 批量转换（通用）：
```bash
/Applications/LibreOffice.app/Contents/MacOS/soffice --headless --convert-to docx input.doc
/Applications/LibreOffice.app/Contents/MacOS/soffice --headless --convert-to pptx input.ppt
/Applications/LibreOffice.app/Contents/MacOS/soffice --headless --convert-to xlsx input.xls
```

## 五、统一入口用法

```bash
# 单个文件
python3 scripts/extract_text.py 报告.docx
python3 scripts/extract_text.py 幻灯片.pptx -o slides.md
python3 scripts/extract_text.py 数据.xlsx

# 批量目录
python3 scripts/extract_text.py ./docs_dir -o ./out_dir
```

输出文件名：`<原名>_extracted.md`，头部记录源文件、引擎、时间。

## 六、注意事项
- Office 文档的"文本层"是原生的，提取质量远高于 OCR，不要对 Office 文档跑 OCR
- 如果 Office 文档里嵌的是扫描图片（不是真文字），先解压提取图片再走 OCR 流程
- 加密的 Office 文档无法直接解析，需先解密
- 大 XLSX（>100MB）用 `read_only=True` 流式处理，避免内存爆炸
