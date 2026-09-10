# 后端选型矩阵与决策树

本文档是引擎选型的权威依据。SKILL.md 只给速查表，这里给完整能力对比、实测数据和决策逻辑。

## 一、五个引擎完整对比

| 维度 | macOS Vision | PP-OCRv6 | PP-StructureV3 | PaddleOCR-VL 1.6 | Unlimited-OCR |
|---|---|---|---|---|---|
| 类型 | 系统原生 OCR | 传统 det+rec 管线 | 7 模块确定性结构化管线 | 0.9B 文档 VLM | 3.3B VLM（DeepSeek-OCR 谱系） |
| 模型体积 | 系统内置 | tiny 1.5M / small 7.7M / medium 34.5M | 版面 L 124MB + OCR + 表格 + 公式模块 | GGUF 全套约 1–1.5GB（语言模型 Q4 约 300MB + mmproj） | unlocr Q8 2.91GB / 约 6GB 内存；BF16 5.47GB |
| 本机（Intel Mac）可行性 | ✅ 零安装 | ✅ 官方 macOS x86 CPU wheel（Python≤3.13） | ✅ CPU 可跑（MKL-DNN，默认 10 线程） | ✅ llama.cpp ≥ b8110，GGUF CPU 可跑 | ⚠️ 仅 unlocr 第三方 GGUF（补丁版 llama.cpp，PR 未合并） |
| 纯文字速度 | 约 1s/页（项目 116 页实测 1m53s） | GPU 实测 1.2–2s/页；CPU 经 OpenVINO 加速端到端 5.2× | 秒级~十几秒/页（模块多） | 默认后端 GPU 实测 76–141s/页；CPU 更慢 | GPU 实测 32–52s/页；CPU 更慢 |
| 表格保结构 | ❌ | ❌ | ✅ HTML/Markdown + 单元格坐标 | ✅ | ✅ |
| 公式→LaTeX | ❌ | ❌ | ✅ | ✅ | ✅ |
| 图表理解 | ❌ | ❌ | ✅ PP-Chart2Table（RMS-F1 80.6%） | ✅ | ✅ figure 任务 |
| 多栏阅读顺序 | ❌ | ❌（行交错） | ✅ 23 类版面 + 跨页表合并 | ✅ | ✅ 独有跨页工作记忆（整本不"失忆"） |
| 语言 | 中英为主 | 50 语言单模型（中日+46 拉丁语系）、竖排/场景文字 | 同 PP-OCR | 109–111 语言、手写/古籍/印章/扭曲拍照 | 以中英文档为主 |
| 坐标输出 | 可出 | ✅ | ✅ 细粒度坐标（VLM 给不了） | 仅检测框 | 仅检测框 |
| 输出可复现 | ✅ | ✅ 确定性、不幻觉不循环 | ✅ | 横评零循环 | ⚠️ 会重复循环（1/5 页），需重试守卫 |
| 许可 | 苹果系统 | Apache-2.0 | Apache-2.0 | Apache-2.0 | MIT |
| 最适场景 | macOS 纯文字扫描件默认 | 非 mac 兜底、多语/竖排/场景文字、要坐标 | 本机复杂结构化文档首选 | StructureV3 失效时的质量优先重型后端 | 仅超长跨页整本特化备选 |

来源：PaddleOCR 官方仓库、PP-StructureV3 官方文档、PaddlePaddle macOS 安装文档、llama.cpp 合入说明、Unlimited-OCR 官方仓库与 unlocr、girlmoony/ocr-model-comparison 横评。

## 二、决策树（按内容复杂度逐级升级）

```
输入文件
 │
 ├─ 有文本层？（PDF 平均每页 ≥20 可提取字符 / Office 格式）
 │   └─ 是 → 第 0 层：直接解析（PyMuPDF / python-docx / python-pptx / openpyxl）
 │
 └─ 否（图片型 PDF / 扫描件 / 图片）
     │
     ├─ 内容是连续纯文字？
     │   ├─ 是，且在 macOS → L1：macOS Vision（默认）
     │   ├─ 是，但非 mac / 多语言 / 竖排 / 要坐标 → L1 备选：PP-OCRv6
     │   └─ 否（有表格/公式/多栏/图表/印章）→ 进入 L2
     │
     ├─ L2：PP-StructureV3（本机首选）
     │   └─ 失败？（手写 / 拍照扭曲 / 复杂语义 / 质量差 / 识别率低）
     │       └─ 是 → 进入 L3
     │
     ├─ L3：PaddleOCR-VL 0.9B（首选重型）
     │   └─ 文档是超长跨页整本（>50 页连续、需要页间上下文）？
     │       └─ 是 → L3 备选：Unlimited-OCR（unlocr）
     │
     └─ 只有零星几页 / 要图表语义描述 → 在线补充：豆包多模态视觉（零安装）
```

## 三、关键决策原则

1. **轻优先于重**：Vision 约 1s/页、零安装；StructureV3 十几秒/页；VLM 分钟级/页。能用轻的绝不上重的。
2. **确定性优先于 VLM**：StructureV3 是模块拼装，输出可复现、给坐标、不循环；VLM 有幻觉和循环风险，只在确定性管线失效时用。
3. **PaddleOCR-VL 优先于 Unlimited-OCR**：同厂、更小（1.5GB vs 6GB）、横评更准、零循环、CPU 路径更成熟（llama.cpp 官方合入 vs unlocr 第三方补丁）。Unlimited-OCR 唯一不可替代的是 R-SWA 跨页记忆，只留给超长整本。
4. **在线补充不做整本批量**：豆包多模态视觉适合零星几页和图表语义描述；整本批量用本地引擎（成本、一致性、隐私）。
5. **跨平台兜底**：Vision 仅 macOS；如果技能要在 Linux/Windows 跑，L1 必须用 PP-OCRv6，L2 用 StructureV3（两者都跨平台）。
