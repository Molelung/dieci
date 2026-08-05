# 叠词（dieci）

AI 智能刷题学习应用 —— Flutter 桌面（Windows）+ Android 双端。
轻盈、高效、碎片化复习：Obsidian 笔记库只读接入 → 主题聚焦 → 动态大纲（流式）→ 智能出题（强约束）→ 刷题 → 错题本 → 闪卡复习。

## 快速开始

```bash
flutter pub get
# 桌面（需安装 Visual Studio + C++ 桌面开发工作负载）
flutter run -d windows
# Android
flutter run -d <device>        # 或 flutter build apk --debug
```

> 注意：工程目录必须是 ASCII 路径（Gradle 限制）。文档在 `D:\叠词\docs`。

## 首次使用

1. 设置页填入 Gemini API Key（aistudio.google.com/app/apikey，用自己的 Google 账号；**Google AI Pro 订阅自动提升额度**）。
2. 「解析官方接口 · 检测 Pro 权限」：直接拉取账号可用模型，自动探测 Pro 模型并推荐切换。
3. 新建笔记本 → 「来源」导入 Obsidian 库（只读）或粘贴文本 / .md 文件。
4. 「大纲」输入主题 → 流式生成大纲（节点勾选 / 折叠 / 全选）→ 对勾选范围出题。
5. 「刷题」设定题型/题量/难度/考点词 → AI 严格按 Schema 出题（带校验重试）→ 计时作答 → 错题自动归档。
6. 「复习」错题本（统计 / 重做 / 移出）+ 闪卡（3D 翻转，不会的自动写回错题本）。
7. 「对话」对笔记库提问（引用 [n] 悬浮原文），回答可沉淀为来源 / 据此出题。

## 架构

```
lib/
├─ core/        # 蓝白液态玻璃设计系统 + HeroArt 插画 + 错误提示
├─ models/      # Notebook/Source/Chunk/OutlineNode/Question/Mistake/ChatMessage
├─ data/        # 原子写入+损坏恢复存储 · 主题聚焦切分 · 加密 Key 存储
├─ ai/          # Gemini REST(SSE 行缓冲/重试/finishReason) · 强约束提示词 · L4 校验
├─ utils/       # Obsidian 库扫描 · 崩溃日志落盘
└─ features/    # 笔记本主页 / 工作台(大纲·刷题·复习·对话·来源) / 设置
```

## 稳定性设计

- 原子写入（tmp+flush+rename）+ 损坏自动回滚 `.bak`，全部损坏改名留底不静默覆盖
- 三层错误捕获（FlutterError / PlatformDispatcher / runZonedGuarded）+ 落盘日志（≤1MB 轮转）
- SSE 行缓冲、坏事件自愈、429/5xx 指数退避（尊重 Retry-After）、finishReason 全覆盖
- 请求 CancelToken 随页面销毁取消；Obsidian 大目录遍历放后台 isolate
- 渲染节流（大纲/对话流式逐帧合并）；上下文预算封顶（出题 8K 字符 / 对话 6K / 大纲 12K）
- prompt injection 防护（系统指令与材料严格分隔）；错题本「越错越练」闭环
- 数据导出 / 导入备份（覆盖前自动留底）；Android 禁用自动备份

## 版本

| 版本 | 内容 |
| --- | --- |
| 0.0.1 | 首版：液态玻璃 UI / Gemini BYOK / 动态大纲 / 强约束出题 / Obsidian 只读导入 |
| 0.0.2 | 蓝白浅色主题重构 + HeroArt 插画 + 应用名「叠词」 |
| 0.0.3 | Google AI Pro 直连：解析 /v1beta/models、Pro 权限探测、模型下拉 |
| 0.0.4 | 复习工作区：错题本 + 3D 翻转闪卡 |
| 0.0.5 | 稳定性：原子写入/崩溃日志/SSE 加固/隔离遍历/渲染节流/禁用备份 |
| 0.0.6 | 关联：错题重做闭环、复习统计、对话引用悬浮、注入防护、上下文预算 |
| 0.0.7 | CancelToken 生命周期、大纲全选/折叠、来源搜索、数据目录可视化 |
| 0.0.8 | 刷题计时/交卷确认/题号、数据导出导入备份 |
| 0.0.9 | 闪卡不会自动写回错题本、对话清空 |
| 0.1.0 | 首页大纲统计、流式光标、Key 错误「去设置」引导、单元测试 |
| 0.1.1 | 写入队列防并发、来源 Markdown 预览、删除笔记本确认、沉淀空保护 |
| 0.1.2 | 对话多轮记忆（最近 6 条历史）、闪卡进度条、复习统计卡移动端适配 |
| 0.1.3 | 出题题干去重校验、大纲生成滚动跟随、设置页错误日志查看 |
| 0.1.4 | 对话重新生成/删除单条、大纲复制 Markdown、Repo 空安全 |
| 0.1.5 | 大纲勾选持久化、错题题型筛选、启动页蓝白渐变 |
| 0.1.6 | 刷题题目快速跳转、对话多行输入 |
| 0.1.7 | 练习「再刷一组」、设置页版本号 |

## 无线调试安装（免数据线）

手机与电脑连同一 Wi-Fi：
```bash
adb devices                          # 先有线连接确认
adb -s <设备号> tcpip 5555            # 打开无线调试端口
adb -s <设备号> connect <手机IP>:5555 # 之后可拔线
flutter install -d <设备号>           # 或 adb install -r app-debug.apk
```
> 手机 IP 在「设置 → WLAN → 当前网络」查看；手机重启后需重新 connect。
