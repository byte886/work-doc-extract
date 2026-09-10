# macOS Vision OCR 引擎指南

macOS 系统原生的 Vision 框架 OCR，是本技能的默认纯文字引擎。零安装、免费、离线、中文识别效果好。

## 一、能力边界（实测）

| 内容类型 | 识别能力 | 说明 |
|---|---|---|
| 纯文字（印刷体中英） | ✅ 好 | 中文识别准确率高，项目 116 页讲义实测可用 |
| 表格 | ⚠️ 有限 | 只能识别出文字，**无法保留行列结构**，表格页必须升级 |
| 公式 | ⚠️ 有限 | 符号识别可能不准确，不输出 LaTeX |
| 图表 | ❌ 差 | 只能识别图表中的文字标签，无法描述图表内容和数据趋势 |
| 手写 | ⚠️ 一般 | 工整手写可识别，潦草手写差 |
| 竖排/多栏 | ❌ 差 | 不做版面分析，多栏会按视觉行交错输出 |

## 二、性能基线（项目实战数据）

| 指标 | 数据 |
|---|---|
| 测试样本 | 税法讲义，116 页，图片型 PDF |
| 总耗时 | 1 分 53 秒 |
| 每页耗时 | 约 1 秒 |
| 输出字数 | 16190 字 |
| DPI | 200（PyMuPDF 转图） |
| 并发 | 单核/实例，可 1–2 个并行（与压缩等 CPU 任务错开） |

## 三、使用方式

### 3.1 单图 OCR（直接跑，无需编译）

```bash
swift scripts/ocr_vision.swift page.png
```

输出识别文本到 stdout；无文字时输出 `未识别到文字`。

### 3.2 PDF 批量 OCR（推荐）

```bash
bash scripts/pdf_ocr.sh 讲义.pdf [输出目录]
```

流程：PyMuPDF 200DPI 逐页转 PNG → Vision OCR → 合并 Markdown（`## 第N页` + `---` 分隔）。

特性：
- **断点续跑**：分页 txt 缓存在 `/tmp/work_doc_extract_pages/`，中断后重跑自动跳过已完成页
- **ETA 进度**：实时显示已用时间和预计剩余
- **可配置错字替换表**：`OCR_CORRECT_FILE=words.txt`（每行 `旧词|新词`）
- **二进制缓存**：首次自动编译到 `~/.cache/work-doc-extract/ocr_vision`，后续复用
- **环境变量**：`OCR_DPI`（默认 200）、`OCR_TMP_DIR`、`OCR_BIN`

### 3.3 统一入口

```bash
python3 scripts/extract_text.py 讲义.pdf
# 自动判断文本层 vs 图片型，图片型自动调 pdf_ocr.sh
```

## 四、混合处理流程（表格/公式/图表页）

Vision 搞不定的页面，用 AI 视觉或 PP-StructureV3 补：

```
PDF → 分页转图片 → Vision 批量 OCR（纯文字页直接用）
                  ↓
          检查是否有表格/图表/公式页
                  ↓
        ┌─────────┴─────────┐
        ↓                   ↓
   纯文字页             表格/公式/图表页
   （OCR 结果直接用）   （AI 视觉或 PP-StructureV3 补充）
        └─────────┬─────────┘
                  ↓
           合并为完整文字稿
```

- **AI 视觉补充**（零星几页）：将该页转图后用豆包多模态视觉识别，表格→Markdown 表格、公式→LaTeX、图表→文字描述
- **PP-StructureV3 补充**（整本复杂）：见 `engine-paddleocr.md`，整份跑结构化管线

## 五、已知坑与解决方案

| 问题 | 原因 | 解决方案 |
|---|---|---|
| iTerm 直接跑 OCR 脚本会退出 | 原因待查（iTerm 环境问题） | 用 `nohup bash pdf_ocr.sh ... &` + `tail -f` 日志；或用 `extract_text.py`（Python 进程更稳） |
| 中文 + bash 变量拼接报 `unbound variable` | nohup 后台环境 locale 为 C，中文首字节被并入变量名 | 脚本已设 `LANG/LC_ALL=en_US.UTF-8` 兜底 |
| 专有名词反复识别错误 | OCR 模型不认识特定术语 | 用 `OCR_CORRECT_FILE` 替换表后处理 sed 修正 |
| 表格页输出乱序 | Vision 不做版面分析 | 表格页单独用 PP-StructureV3 或 AI 视觉 |
| 大 PDF 内存占用高 | 一次性加载 | 脚本逐页处理，临时图片用完即删，只留 txt 缓存 |

## 六、与项目脚本的关系

本技能的 `pdf_ocr.sh` 和 `ocr_vision.swift` 泛化自高顿课程知识库项目的 `scripts/batch_ocr.sh` 和 `scripts/ocr/ocr_vision.swift`，去除了项目硬编码（默认路径、固定错字表），增加了可配置性。项目实战验证了该管线在 116 页讲义上的可靠性。
