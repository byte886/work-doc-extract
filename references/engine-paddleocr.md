# PaddleOCR 引擎指南（PP-OCRv6 + PP-StructureV3）

PaddleOCR 是百度飞桨的开源 OCR 工具包（Apache-2.0），包含两条本技能会用到的产品线：
- **PP-OCRv6**：传统检测+识别管线，跨平台、多语言、超轻量
- **PP-StructureV3**：7 模块确定性结构化管线，输出 Markdown/JSON，保留表格/公式/版面/坐标

> **默认不安装**。本技能的默认引擎是 macOS Vision；PaddleOCR 是可选重型后端，用到再装。

## 一、PP-OCRv6（传统管线，L1 备选）

### 1.1 适用场景
- 非 macOS 机器（Linux/Windows）的默认纯文字 OCR
- 多语言文档（50 语言单模型：简中、繁中、英文、日文 + 46 种拉丁语系）
- 竖排文字、场景文字（路牌/票据/工业零件/点阵屏/轮胎纹）
- 需要检测框坐标（后续做版面分析或定位）

### 1.2 模型档位
| 档位 | 参数 | 适用 |
|---|---|---|
| tiny | 1.5M | 端侧/嵌入式，速度优先 |
| small | 7.7M | 平衡，常用 |
| medium | 34.5M | 精度优先，横评超主流 VLM（Qwen3-VL-235B、GPT-5.5）的文字识别 |

PP-OCRv6 相对 v5：检测 +4.6%、识别 +5.1%，CPU 经 OpenVINO 加速端到端 5.2×，Apple M4 tiny 档 6.1×，A100 0.13s/页。

### 1.3 局限
- **无版面理解**：多栏跨行句子会交错（横评实测：单词 40/40 但多栏例句只对 2/40，因为行碎片）
- 不输出表格结构、不识别公式、不理解图表
- 这些是 PP-StructureV3 的事

## 二、PP-StructureV3（结构化管线，L2 本机首选）

### 2.1 适用场景
- 含表格、公式、多栏、图表、印章的复杂文档
- 需要保留版式结构和阅读顺序
- 需要细粒度坐标（表格单元格坐标、文本坐标）——VLM 给不了
- 要求输出可复现、不幻觉、不循环（确定性管线）

### 2.2 七个模块
1. **版面检测**（PP-DocLayout L/M/S，23 类：标题/段落/表格/公式/图表/印章/页眉页脚等）
2. **版面子区域检测**（多栏报纸杂志的子文章区域）
3. **文本检测+识别**（PP-OCRv6）
4. **表格识别**（SLANeXtr，输出 HTML/Markdown，支持跨页表格合并）
5. **公式识别**（→ LaTeX）
6. **图表理解**（PP-Chart2Table，图表→表格，RMS-F1 80.6%）
7. **印章识别**（检测+文本识别）

输出：Markdown 或 JSON，带阅读顺序恢复和多栏排序。

### 2.3 CPU 性能参考（官方数据）
| 模块 | CPU 常规/高性能模式 | 模型大小 |
|---|---|---|
| PP-DocLayout-L | 503ms / 251ms | 123.8MB |
| PP-DocLayout-M | 43ms / 24ms | 22.6MB |
| PP-DocLayout-S | 19ms / 6ms | 4.8MB |

整页（版面+OCR+表格+公式）CPU 约秒级~十几秒，比 VLM（分钟级）快得多。用 `enable_mkldnn=True`、`cpu_threads=10`、`enable_hpi=True`（高性能模式）加速。

## 三、安装（macOS Intel CPU）

> ⚠️ 必须用独立 Python 3.12 venv。系统 Python 3.13+ 暂不支持 PaddlePaddle；不要装进项目的转写 venv（会污染 FunASR 依赖）。

```bash
# 1. 建独立 venv（需要 python3.12；没有则 brew install python@3.12）
python3.12 -m venv ~/.venvs/paddleocr
source ~/.venvs/paddleocr/bin/activate

# 2. 装 PaddlePaddle CPU 版（macOS 仅 CPU，官方源）
pip install paddlepaddle -i https://www.paddlepaddle.org.cn/packages/stable/cpu/

# 3. 装 PaddleOCR（含 doc-parser 扩展，即 StructureV3）
pip install "paddleocr[doc-parser]>=3.7.0"

# 4. 验证
python -c "from paddleocr import PaddleOCR, PPStructureV3; print('OK')"
```

首次运行会自动下载模型到 `~/.paddleocr/`。

## 四、使用示例

### 4.1 PP-OCRv6 纯文字识别
```python
from paddleocr import PaddleOCR
ocr = PaddleOCR(use_doc_orientation_classify=False, use_doc_unwarping=False, lang="ch")
result = ocr.predict("page.png")
# result[0].rec_texts / rec_scores / rec_polys
```

### 4.2 PP-StructureV3 结构化解析（输出 Markdown）
```python
from paddleocr import PPStructureV3
engine = PPStructureV3(
    use_doc_orientation_classify=True,
    use_doc_unwarping=True,
    use_textline_orientation=True,
    use_table_recognition=True,
    use_formula_recognition=True,
    use_chart_recognition=False,   # 图表解析按需开（较慢）
    use_seal_recognition=False,
    device="cpu",
    enable_mkldnn=True,
    cpu_threads=10,
)
result = engine.predict("complex_doc.pdf")
# result[0].res["md"] 为 Markdown 文本；.res["json"] 为结构化 JSON
```

批量 PDF：`engine.predict("dir_of_pdfs/")` 或传列表。

### 4.3 命令行
```bash
paddleocr --image_dir input.pdf --type=structure --output=./out
```

## 五、选型建议

- **纯文字、在 mac**：用 Vision（零安装、更快），不用装 PP-OCRv6
- **纯文字、非 mac / 多语言 / 要坐标**：装 PP-OCRv6（轻量，几十 MB）
- **复杂文档（表格/公式/多栏）**：装 PP-StructureV3（本机首选，比 VLM 快且稳）
- **StructureV3 搞不定（手写/拍照扭曲/复杂语义）**：再上 PaddleOCR-VL（见 engine-vlm-ocr.md）

## 六、来源
- PaddleOCR 官方仓库：https://github.com/PaddlePaddle/PaddleOCR
- PP-StructureV3 官方文档：http://www.paddleocr.ai/latest/version3.x/pipeline_usage/PP-StructureV3.html
- PaddlePaddle macOS 安装：https://www.paddlepaddle.org.cn/documentation/docs/zh/3.0/install/pip/macos-pip.html
- 横评：https://github.com/girlmoony/ocr-model-comparison
