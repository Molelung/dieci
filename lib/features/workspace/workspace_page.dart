import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/gradient_background.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import 'chat_page.dart';
import 'outline_page.dart';
import 'practice_page.dart';
import 'sources_page.dart';

enum WorkspaceTab { outline, practice, chat, sources }

class WorkspacePage extends StatefulWidget {
  final String notebookId;

  const WorkspacePage({super.key, required this.notebookId});

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  WorkspaceTab _tab = WorkspaceTab.outline;

  static const _tabs = [
    (WorkspaceTab.outline, '大纲', Icons.account_tree_rounded),
    (WorkspaceTab.practice, '刷题', Icons.quiz_rounded),
    (WorkspaceTab.chat, '对话', Icons.chat_bubble_rounded),
    (WorkspaceTab.sources, '来源', Icons.folder_copy_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final nb = Repo.i.notebook(widget.notebookId);

    return Scaffold(
      body: GradientBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 760;
            final content = switch (_tab) {
              WorkspaceTab.outline =>
                OutlinePage(notebookId: widget.notebookId),
              WorkspaceTab.practice =>
                PracticePage(notebookId: widget.notebookId),
              WorkspaceTab.chat => ChatPage(notebookId: widget.notebookId),
              WorkspaceTab.sources =>
                SourcesPage(notebookId: widget.notebookId),
            };

            return SafeArea(
              child: desktop
                  ? Row(
                      children: [
                        _sidebar(context, nb),
                        Expanded(
                          child: Column(
                            children: [
                              _header(context, nb),
                              Expanded(child: content),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _header(context, nb),
                        Expanded(child: content),
                        _bottomNav(),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Notebook nb) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: Tokens.textSecondary),
          ),
          const SizedBox(width: 10),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: notebookGradient(nb.gradientIndex),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              nb.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Tokens.textPrimary),
            ),
          ),
          const Spacer(),
          _chip('${nb.sources.length} 来源'),
          const SizedBox(width: 8),
          _chip('${nb.totalChunks} 分块'),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: Tokens.brandBlue.withValues(alpha: 0.14)),
      ),
      child: Text(text,
          style:
              const TextStyle(fontSize: 11, color: Tokens.textSecondary)),
    );
  }

  Widget _sidebar(BuildContext context, Notebook nb) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            for (final (tab, label, icon) in _tabs)
              _navItem(context, tab, label, icon),
          ],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, WorkspaceTab tab, String label,
      IconData icon) {
    final selected = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: selected ? Tokens.brandGradient : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Tokens.brandBlue.withValues(alpha: 0.30),
                    blurRadius: 16,
                    spreadRadius: -4,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: selected ? Colors.white : Tokens.textSecondary),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? Colors.white : Tokens.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _bottomNav() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Tokens.brandBlue.withValues(alpha: 0.16), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Tokens.brandBlue.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final (tab, label, icon) in _tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = tab),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 20,
                          color: _tab == tab
                              ? Tokens.brandBlue
                              : Tokens.textTertiary),
                      const SizedBox(height: 3),
                      Text(label,
                          style: TextStyle(
                              fontSize: 10,
                              color: _tab == tab
                                  ? Tokens.textPrimary
                                  : Tokens.textTertiary)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
