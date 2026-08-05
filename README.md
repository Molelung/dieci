# 叠词（dieci）· 0.0.1

AI 智能刷题学习应用 —— Flutter 桌面（Windows）+ Android 双端。
轻盈、高效、碎片化复习：Obsidian 笔记库只读接入 → 主题聚焦 → 动态大纲（流式）→ 智能出题（强约束）→ 刷题 → 错题。

## 快速开始

```bash
flutter pub get
# 桌面（需安装 Visual Studio + C++ 桌面开发工作负载）
flutter run -d windows
# Android
flutter run -d <device>        # 或 flutter build apk --debug
```

> 注意：工程目录必须是 ASCII 路径（Gradle 限制），当前位于 `D:\dieci`。

## 首次使用

1. 设置页填入 Gemini API Key（aistudio.google.com/app/apikey，用自己的 Google 账号，Pro 订阅自动提升额度）。
2. 新建笔记本 → 「来源」页导入 Obsidian 笔记库文件夹（只读）或粘贴文本。
3. 「大纲」页输入学习主题 → 实时生成大纲 → 勾选节点。
4. 「刷题」页设定题型/题量/难度/考点词 → AI 严格按 Schema 出题 → 作答交卷 → 错题自动归档。
5. 「对话」页可对笔记库提问，回答可一键「沉淀为来源」「据此出题」。

## 架构

```
lib/
├─ core/          # 液态玻璃设计系统：GradientBackground / GlassCard / GlassButton / GlassInput / GlassChip
├─ models/        # Notebook / Source / Chunk / OutlineNode / Question / Mistake / ChatMessage
├─ data/          # JSON 本地持久化（Repo）· 主题聚焦切分器（Chunker）· 加密 Key 存储（SettingsStore）
├─ ai/            # Gemini REST 客户端（SSE 流式 + responseSchema）· 强约束提示词 · L4 校验重试
├─ utils/         # Obsidian 库扫描（跳过 .obsidian/.trash，剥 frontmatter）
└─ features/      # 笔记本主页 / 工作台（大纲·刷题·对话·来源）/ 设置
```

## 已知事项

- Windows 桌面构建需本机安装 Visual Studio（Desktop development with C++）。
- 0.0.1 存储为本地 JSON 文件（应用支持目录 dieci_data/notebooks.json）。
- gradle.properties 已设 `kotlin.incremental=false`（规避 Windows 上 Kotlin 增量缓存损坏问题）。
