import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
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
import '../../utils/crash_log.dart';

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
  bool _showKey = false;
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

  Future<void> _exportData() async {
    final file = await Storage.notebooksFile();
    if (!file.existsSync()) {
      _toast('还没有数据可导出');
      return;
    }
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name =
        'dieci-备份-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}.json';
    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: '导出叠词备份',
        fileName: name,
        type: FileType.any,
        bytes: await file.readAsBytes(),
      );
    } catch (_) {
      path = null;
    }
    if (path == null) {
      _toast('未选择保存位置，备份文件仍在：${file.path}');
      return;
    }
    if (!path.endsWith('.json')) path = '$path.json';
    await File(path).writeAsBytes(await file.readAsBytes());
    _toast('已导出：$path');
  }

  Future<void> _importData() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    String content;
    try {
      if (f.path != null) {
        content = await File(f.path!).readAsString();
      } else if (f.bytes != null) {
        content = utf8.decode(f.bytes!);
      } else {
        _toast('无法读取该文件');
        return;
      }
    } catch (e) {
      _toast('读取失败：$e');
      return;
    }
    try {
      final list = jsonDecode(content);
      if (list is! List) throw const FormatException('不是备份数组');
    } catch (e) {
      _toast('备份文件格式不正确：$e');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(22),
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('导入备份将覆盖当前数据，确定？',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GlassButton(
                      label: '取消',
                      style: GlassButtonStyle.ghost,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const SizedBox(width: 10),
                    GlassButton(
                      label: '导入',
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final file = await Storage.notebooksFile();
    try {
      if (file.existsSync()) {
        await file.copy(
            '${file.path}.pre-import-${DateTime.now().millisecondsSinceEpoch}');
      }
      await Storage.writeAtomic(file, content);
      await Repo.i.init();
      _toast('导入成功，覆盖前已自动备份当前数据');
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  Future<void> _viewErrorLog() async {
    final log = await CrashLog.readLog();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).width * 0.9).clamp(0.0, 560),
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bug_report_rounded,
                        size: 18, color: Tokens.brandBlue),
                    SizedBox(width: 8),
                    Text('错误日志',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Tokens.textPrimary)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Tokens.brandBlue.withValues(alpha: 0.10)),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(log,
                          style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.6,
                              color: Tokens.textSecondary)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: GlassButton(
                    label: '关闭',
                    style: GlassButtonStyle.ghost,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _resetAll() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(22),
          child: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 34, color: Tokens.danger),
                const SizedBox(height: 12),
                const Text('清除全部数据？',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 8),
                const Text(
                    '将删除所有笔记本、来源、题目与错题，且无法恢复。建议先「导出备份」。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.6, color: Tokens.textSecondary)),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GlassButton(
                      label: '取消',
                      style: GlassButtonStyle.ghost,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const SizedBox(width: 10),
                    GlassButton(
                      label: '继续',
                      style: GlassButtonStyle.outline,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(22),
          fill: Tokens.danger.withValues(alpha: 0.10),
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('最后确认：删除全部数据？',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Tokens.danger)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GlassButton(
                      label: '保留数据',
                      style: GlassButtonStyle.ghost,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const SizedBox(width: 10),
                    GlassButton(
                      label: '删除',
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (second != true || !mounted) return;

    Repo.i.notebooks.clear();
    Repo.i.save();
    _toast('已清除全部数据');
  }

  Future<void> _viewBackups() async {
    final dir = await Storage.dir();
    final bkDir = Directory(
        '${dir.path}${Platform.pathSeparator}backups');
    if (!bkDir.existsSync()) {
      _toast('还没有备份');
      return;
    }
    final files = bkDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    if (files.isEmpty) {
      _toast('还没有备份');
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).width * 0.9).clamp(0.0, 420),
            height: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.restore_rounded,
                        size: 18, color: Tokens.brandBlue),
                    SizedBox(width: 8),
                    Text('自动备份（每日一份，保留 7 份）',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Tokens.textPrimary)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: files.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final f = files[i];
                      final name =
                          f.uri.pathSegments.last.replaceAll('.json', '');
                      return GlassButton(
                        label: '恢复 $name',
                        icon: Icons.history_rounded,
                        style: GlassButtonStyle.ghost,
                        onPressed: () => Navigator.pop(ctx, f.path),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: GlassButton(
                    label: '关闭',
                    style: GlassButtonStyle.ghost,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(22),
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('恢复该备份？将覆盖当前数据。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GlassButton(
                      label: '取消',
                      style: GlassButtonStyle.ghost,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const SizedBox(width: 10),
                    GlassButton(
                      label: '恢复',
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final file = await Storage.notebooksFile();
      if (file.existsSync()) {
        await file.copy(
            '${file.path}.pre-restore-${DateTime.now().millisecondsSinceEpoch}');
      }
      await Storage.writeAtomic(file, await File(chosen).readAsString());
      await Repo.i.init();
      _toast('已恢复备份（恢复前已自动留底当前数据）');
    } catch (e) {
      _toast('恢复失败：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
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
    if (_keyController.text.trim().isEmpty) {
      setState(() {
        _detectMsg = '请先在上方填写 API Key，再解析官方接口';
        _models = [];
        _proModels = [];
      });
      return;
    }
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
                      obscure: !_showKey,
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => setState(() => _showKey = !_showKey),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showKey
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 14,
                            color: Tokens.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(_showKey ? '隐藏 Key' : '显示 Key',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Tokens.textTertiary)),
                        ],
                      ),
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
                    const Text('关于叠词 · v0.3.9',
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
                    const SizedBox(height: 8),
                    const Text('开源仓库：github.com/Molelung/dieci',
                        style: TextStyle(
                            fontSize: 11, color: Tokens.textTertiary)),
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          GlassButton(
                            label: '导出备份',
                            icon: Icons.save_alt_rounded,
                            style: GlassButtonStyle.outline,
                            onPressed: _exportData,
                          ),
                          GlassButton(
                            label: '导入备份',
                            icon: Icons.upload_file_rounded,
                            style: GlassButtonStyle.ghost,
                            onPressed: _importData,
                          ),
                          GlassButton(
                            label: '错误日志',
                            icon: Icons.bug_report_rounded,
                            style: GlassButtonStyle.ghost,
                            onPressed: _viewErrorLog,
                          ),
                          GlassButton(
                            label: '恢复备份',
                            icon: Icons.restore_rounded,
                            style: GlassButtonStyle.ghost,
                            onPressed: _viewBackups,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GlassButton(
                          label: '清除全部数据（危险）',
                          icon: Icons.delete_forever_rounded,
                          style: GlassButtonStyle.ghost,
                          onPressed: _resetAll,
                        ),
                      ),
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
