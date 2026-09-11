# DocxReplace

批量查找替换文件夹下所有 Word 文档（`.docx`）中的文字，**格式完全不变**。

A macOS app that batch find/replaces text across every `.docx` in a folder, **preserving all formatting byte-for-byte**.

---

## 为什么不是"看起来没变"

大多数批量替换工具会解析文档再重新生成，结果往往字体变了、行距变了、表格错位了。DocxReplace 的做法不同：

- **只重写被替换的那几个文字节点**，XML 的其余部分**一个字节都不动**（属性顺序、命名空间、空白全部保留）
- **未改动的压缩包条目直接拷贝原始压缩数据**，不重新压缩
- 测试用「把所有文字节点内容清空后逐字节比对」来钉住这一点——任何结构改动都会立刻让测试失败

## 功能

| | |
|---|---|
| **跨 run 匹配** | Word 常把一句话拆成多段存储（拼写检查、格式变化、修订记录都会导致拆分）。本工具按段落重新拼接后再匹配，这是「明明有却搜不到」的常见原因 |
| **先扫描预览** | 扫描后列出每个文件的命中数；点开任意一行可展开查看**每处命中的上下文**（命中文字高亮），确认无误再替换 |
| **覆盖范围** | 正文、表格、页眉、页脚、文本框/形状、脚注、尾注、批注 |
| **自动备份** | 替换前把原文件备份到 `DocxReplace备份_时间戳/`，保留原目录结构 |
| **失败隔离** | 单个文件损坏/加密/无权限只跳过并报告，不影响其余文件 |
| **多语言** | 简体中文 / English，可跟随系统语言，切换即时生效 |
| **零依赖** | ZIP 读写、XML 定位与改写、DEFLATE 压缩解压全部自研，不依赖任何第三方库 |

## 安装

从 [Releases](https://github.com/goshawker/docxRepleace/releases) 下载 `DocxReplace.dmg`，双击打开，把 `DocxReplace` 拖进 `Applications`。

**系统要求**：macOS 14.0 或更高。已适配 Intel 与 Apple Silicon。

> **首次打开可能被拦截**：应用使用本地 ad-hoc 签名（无付费开发者账号公证）。若提示「无法验证开发者」，请**右键点应用图标 → 打开 → 再点「打开」**，之后即可正常运行。

## 使用

1. 选择文件夹（会递归包含所有子文件夹）
2. 输入查找内容与替换内容
3. 点「扫描」，查看哪些文件命中、命中多少处；**点开任意一行可确认命中的具体上下文**
4. 确认无误后点「全部替换」

### 需要注意

- **替换前请先关闭 Word**。Word 中打开的文档会在保存时覆盖本工具的修改。
- 查找是**精确匹配**。`成都市“蓉政通”平台` 与 `成都市 “蓉政通” 平台`（引号两侧带空格）是两个不同的字符串，需要分别搜索。用展开预览可以确认命中的具体写法。
- `.doc` 旧格式不支持，扫描时会提示先转为 `.docx`。

## 能力边界

- 匹配不跨段落，也不跨手动换行（`w:br`）与制表符（`w:tab`）
- 查找词与替换词都不能含换行符；粘贴 XML 非法控制字符会被界面拦下
- 只处理 `w:t` 文字节点：**不动域代码**（自动目录、页码的代码原样保留），**不处理修订痕迹中被删除的文字**（`w:delText`）
- 替换文字的格式继承命中处**第一个字**的格式（与 Word 默认行为一致）
- 文档带数字签名时，修改后签名会失效
- 含图形的文档若同时保存了现代与兼容两套表示（`mc:AlternateContent`），两套都会被替换——命中计数可能大于肉眼可见的处数，这是预期行为

## 从源码构建

```bash
git clone https://github.com/goshawker/docxRepleace.git
cd docxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' build
```

运行测试（约 140 项）：

```bash
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test
```

打包 DMG：

```bash
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -configuration Release \
  -destination 'platform=macOS' build
# 产物在 DerivedData 的 Build/Products/Release/DocxReplace.app，
# 复制出来后用 hdiutil create 打包即可
```

## 架构

```
DocxReplace/
├── Core/                     纯逻辑，无 UI 依赖，可独立测试
│   ├── ZipArchive / ZipWriter    ZIP 读写（基于系统 Compression 框架）
│   ├── XmlTextLocator            在原始 XML 字节上定位与改写 w:t 元素
│   ├── DocxXmlAnalyzer           解析段落与分段结构（XMLDocument，仅用于结构）
│   ├── ParagraphMatcher          跨 run 的文本查找与替换区间计算
│   ├── DocxTextReplacer          单个 .docx 的替换主流程
│   ├── FileScanner               递归扫描
│   ├── BackupManager             备份
│   └── ReplaceCoordinator        扫描/替换编排（并行扫描、串行替换、进度、取消）
├── AppViewModel.swift        界面状态机
├── ContentView.swift         界面
└── Localization.swift        多语言词表
```

几个关键设计：

- **文字来自字节扫描器，结构来自 XML 解析器**。两者交叉校验节点数量，不一致就报错跳过——避免解析器的归一化（编码、实体、换行）悄悄改变被替换的文字。
- **偏移量一律以 UTF-16 码元计**。按 Swift 的 `Character` 计数在字符串拼接时不可加，一旦某个字素簇（组合符号、肤色 emoji、国旗）横跨相邻文字节点，run 起始偏移就会与拼接串错位，导致静默改错文字。
- **写入用原子替换**，且写入前把改写后的 XML 重新解析一遍作为最后一道防线——宁可整份文件报错跳过，也不写出 Word 打不开的文档。

## 许可

未指定。如需开源授权请自行添加 `LICENSE`。

---

## English

**DocxReplace** batch find/replaces text across every `.docx` in a folder while preserving formatting **byte-for-byte**: only the matched text nodes are rewritten, every other byte of the document XML is copied verbatim, and untouched ZIP entries keep their original compressed bytes.

- **Cross-run matching** — Word splits sentences across runs; this app rejoins them per paragraph before matching.
- **Scan first, then replace** — expand any result row to see each match *in context* before committing.
- **Covers** body, tables, headers, footers, text boxes, footnotes, endnotes, comments.
- **Automatic backup** before modifying, with the original folder structure preserved.
- **Zero dependencies** — ZIP, XML surgery and DEFLATE are all implemented in-house.

Requires macOS 14.0+. Universal binary (Intel + Apple Silicon). First launch may be blocked by Gatekeeper (ad-hoc signed, not notarized) — right-click the app → Open.

Not supported: `.doc`, matches spanning paragraphs or manual line breaks, and editing field codes or tracked-change deletions.
