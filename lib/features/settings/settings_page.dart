import 'dart:io';
import 'package:flutter/material.dart';
import '../../ai/gemini_client.dart';
import '../../ai/prompts.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/gradient_background.dart';
import '../../data/repository.dart';
import '../../data/settings_store.dart';
import '../../data/storage.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();
  final _modelController = TextEditingController();
  bool _saved = false;
  bool _testing = false;
  String? _testResult;
  bool _detecting = false;
  String? _detectMsg;
  List<String> _models = [];
  List<String> _proModels = [];
  String _dataPath = '';

  @override
  void initState() {
    super.initState();
    _keyController.text = SettingsStore.i.apiKey;
    _urlController.text = SettingsStore.i.baseUrl;
    _modelController.text = SettingsStore.i.model;
    _loadDataPath();
  }

  Future<void> _loadDataPath() async {
    final dir = await Storage.dir();
    if (mounted) setState(() => _dataPath = dir.path);
  }

  Future<void> _save() async {
    final s = SettingsStore.i;
    s.apiKey = _keyController.text.trim();
    s.baseUrl = _urlController.text.trim().isEmpty
        ? 'https://generativelanguage.googleapis.com/v1beta'
        : _urlController.text.trim();
    s.model = _modelController.text.trim();
    await s.save();
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final client = GeminiClient(SettingsStore.i);
      final reply = await client.generateOnce(
        contents: [const AiMessage('user', '回复"连接成功"四个字')],
        system: Prompts.chatSystem(),
        temperature: 0,
      );
      setState(() => _testResult = '✓ 连接成功，模型回复：$reply');
    } catch (e) {
      setState(() => _testResult = '✗ 失败：$e');
    } finally {
      setState(() => _testing = false);
    }
  }

  /// 解析官方 `GET /v1beta/models` 接口 + 探测 Pro 模型可用性
  Future<void> _detect() async {
    final client = GeminiClient(SettingsStore.i);
    setState(() {
      _detecting = true;
      _detectMsg = null;
      _models = [];
      _proModels = [];
    });
    try {
      final models = await client.listModels();
      final proModels = await client.detectProModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _proModels = proModels;
        if (models.isNotEmpty && _modelController.text.trim().isEmpty) {
          _modelController.text = models.first;
          SettingsStore.i.model = models.first;
        }
        final proOk = proModels.isNotEmpty ? '✓ 可用 Pro 模型：${proModels.take(3).join('、')}' : '✗ 未探测到 Pro 专属模型（可能只有免费档）';
        _detectMsg = models.isEmpty
            ? '未拉取到模型列表（请检查 Key / 网络）'
            : '已解析到 ${models.length} 个模型；$proOk';
      });
    } catch (e) {
      if (mounted) setState(() => _detectMsg = '检测失败：$e');
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 18, color: Tokens.textSecondary),
                  ),
                  const SizedBox(width: 10),
                  const Text('设置',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Tokens.textPrimary)),
                ],
              ),
              const SizedBox(height: 16),
              GlassCard(
                glow: true,
                margin: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.key_rounded, size: 17, color: Tokens.brandBlue),
                        SizedBox(width: 8),
                        Text('Gemini API 配置（BYOK，用自己的账户）',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Tokens.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '在 aistudio.google.com/app/apikey 用你的 Google 账号免费创建 Key。\n拥有 Google AI Pro 订阅时，同一 Key 自动获得更高速率限制；\n点下方「解析官方接口」可直接拉取你的账号可用模型、并探测 Pro 模型。',
                      style: TextStyle(
                          fontSize: 12, height: 1.6, color: Tokens.textTertiary),
                    ),
                    const SizedBox(height: 16),
                    GlassInput(
                      controller: _keyController,
                      label: 'API Key',
                      hint: 'AIza…',
                      icon: Icons.vpn_key_rounded,
                      obscure: true,
                    ),
                    const SizedBox(height: 12),
                    GlassInput(
                      controller: _urlController,
                      label: 'Base URL（默认官方）',
                      icon: Icons.link_rounded,
                    ),
                    const SizedBox(height: 12),
                    GlassInput(
                      controller: _modelController,
                      label: '模型',
                      hint: 'gemini-2.5-flash',
                      icon: Icons.memory_rounded,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in SettingsStore.modelSuggestions)
                          _modelChip(m),
                      ],
                    ),
                    if (_models.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  Tokens.brandBlue.withValues(alpha: 0.16)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _modelController.text.trim().isNotEmpty &&
                                    _models.contains(_modelController.text.trim())
                                ? _modelController.text.trim()
                                : null,
                            isExpanded: true,
                            hint: const Text('选择已解析的可用模型',
                                style: TextStyle(
                                    fontSize: 13, color: Tokens.textTertiary)),
                            dropdownColor: Colors.white,
                            iconEnabledColor: Tokens.brandBlue,
                            items: [
                              for (final m in _models)
                                DropdownMenuItem(
                                  value: m,
                                  child: Row(
                                    children: [
                                      if (m.contains('pro'))
                                        const Icon(Icons.workspace_premium_rounded,
                                            size: 14, color: Tokens.brandBlue),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(m,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: Tokens.textPrimary)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _modelController.text = v;
                                SettingsStore.i.model = v;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('温度：',
                            style: TextStyle(
                                fontSize: 12, color: Tokens.textSecondary)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: Tokens.brandBlue,
                              thumbColor: Tokens.brandBlue,
                              inactiveTrackColor:
                                  Colors.white.withValues(alpha: 0.12),
                              trackHeight: 3,
                            ),
                            child: Slider(
                              value: SettingsStore.i.temperature,
                              min: 0,
                              max: 1,
                              divisions: 20,
                              label: SettingsStore.i.temperature.toStringAsFixed(1),
                              onChanged: (v) => setState(
                                  () => SettingsStore.i.temperature = v),
                            ),
                          ),
                        ),
                        Text(
                          SettingsStore.i.temperature.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 12, color: Tokens.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        GlassButton(
                          label: _saved ? '已保存 ✓' : '保存配置',
                          icon: _saved ? null : Icons.save_rounded,
                          onPressed: _save,
                        ),
                        const SizedBox(width: 10),
                        GlassButton(
                          label: _testing ? '测试中…' : '测试连接',
                          icon: Icons.wifi_tethering_rounded,
                          style: GlassButtonStyle.outline,
                          loading: _testing,
                          onPressed: _testing ? null : _test,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GlassButton(
                      label: _detecting ? '解析接口中…' : '解析官方接口 · 检测 Pro 权限',
                      icon: Icons.workspace_premium_rounded,
                      style: GlassButtonStyle.ghost,
                      loading: _detecting,
                      onPressed: _detecting ? null : _detect,
                    ),
                    if (_detectMsg != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  Tokens.brandBlue.withValues(alpha: 0.12)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _detectMsg!,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: _detectMsg!.contains('✗')
                                      ? Tokens.warn
                                      : Tokens.textSecondary),
                            ),
                            if (_models.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                _models.join(' · '),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Tokens.textTertiary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (_proModels.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.workspace_premium_rounded,
                              size: 15, color: Tokens.brandBlue),
                          const SizedBox(width: 6),
                          const Text('Pro 推荐：',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Tokens.textPrimary)),
                          Expanded(
                            child: Text(
                              _proModels.first,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: Tokens.brandBlue),
                            ),
                          ),
                          GlassButton(
                            label: '切换',
                            style: GlassButtonStyle.ghost,
                            onPressed: () => setState(() {
                              _modelController.text = _proModels.first;
                              SettingsStore.i.model = _proModels.first;
                            }),
                          ),
                        ],
                      ),
                    ],
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      Text(_testResult!,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: _testResult!.startsWith('✓')
                                  ? Tokens.success
                                  : Tokens.danger)),
                    ],
                  ],
                ),
              ),
              GlassCard(
                margin: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('模型速查',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Tokens.textPrimary)),
                    const SizedBox(height: 8),
                    _tip('gemini-2.5-flash', '免费档兼容性最好，推荐默认'),
                    _tip('gemini-3-flash-preview', '更快更新的 3 系闪卡模型'),
                    _tip('gemini-3.6-flash', '2026 年 7 月最新快速模型'),
                    _tip('gemini-3-pro-preview', '深度推理，出难题/大纲质量高（需付费档）'),
                    _tip('出题/大纲建议 temperature 0.2~0.4', '随机性越低越遵循要求'),
                  ],
                ),
              ),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('关于叠词 0.0.1',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Tokens.textPrimary)),
                    const SizedBox(height: 8),
                    const Text(
                      '轻盈、高效、碎片化复习。\n数据全部保存在本机应用目录；导入 Obsidian 库为只读，不会改动你的笔记。\n支持协议：Gemini REST（SSE 流式 + responseSchema 强约束）。',
                      style: TextStyle(
                          fontSize: 12, height: 1.7, color: Tokens.textTertiary),
                    ),
                    const SizedBox(height: 12),
                    if (_dataPath.isNotEmpty) ...[
                      Text('数据目录：$_dataPath',
                          style: const TextStyle(
                              fontSize: 11, color: Tokens.textTertiary)),
                      const SizedBox(height: 4),
                      Text(
                          '已保存 ${Repo.i.notebooks.length} 个笔记本（含来源、题目、错题）。写入为原子操作，损坏自动回滚 .bak。',
                          style: const TextStyle(
                              fontSize: 11, color: Tokens.textTertiary)),
                      if (Platform.isWindows) ...[
                        const SizedBox(height: 8),
                        GlassButton(
                          label: '打开数据目录',
                          icon: Icons.folder_open_rounded,
                          style: GlassButtonStyle.ghost,
                          onPressed: () {
                            try {
                              Process.start('explorer', [_dataPath]);
                            } catch (_) {}
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modelChip(String model) {
    final selected = _modelController.text.trim() == model;
    return GestureDetector(
      onTap: () => setState(() {
        _modelController.text = model;
        SettingsStore.i.model = model;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? Tokens.brandBlue.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.8),
          border: Border.all(
            color: selected
                ? Tokens.brandBlue.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(model,
            style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white : Tokens.textSecondary)),
      ),
    );
  }

  Widget _tip(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.fiber_manual_record_rounded,
                size: 6, color: Tokens.brandBlue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '$title  ',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Tokens.textPrimary),
                ),
                TextSpan(
                  text: desc,
                  style: const TextStyle(
                      fontSize: 12, color: Tokens.textTertiary),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
