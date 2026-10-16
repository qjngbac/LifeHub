import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';

class SafetyChecklistExportSheet extends StatefulWidget {
  const SafetyChecklistExportSheet({
    super.key,
    required this.stage,
    this.memberName,
  });

  final LifecycleStage stage;
  final String? memberName;

  @override
  State<SafetyChecklistExportSheet> createState() =>
      _SafetyChecklistExportSheetState();
}

class _SafetyChecklistExportSheetState
    extends State<SafetyChecklistExportSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isExporting = false;

  String _buildWeChatText() {
    final s = widget.stage;
    final nameStr = widget.memberName != null ? '（专属成员：${widget.memberName}）' : '';
    final buffer = StringBuffer();

    buffer.writeln('🛡️【全生命周期选品避坑清单 · ${s.codeLabel}】$nameStr');
    buffer.writeln('阶段：${s.rawTitle}');
    buffer.writeln('----------------------------------------');

    if (s.redlines.isNotEmpty) {
      buffer.writeln('\n🚨【核心安全红线 · 务必严守】');
      for (var i = 0; i < s.redlines.length; i++) {
        buffer.writeln('${i + 1}. ${s.redlines[i]}');
      }
    }

    if (s.subsections.isNotEmpty) {
      buffer.writeln('\n📋【选品重点与采购避坑】');
      for (final sub in s.subsections.take(4)) {
        buffer.writeln('\n▶ ${sub.title}');
        for (final b in sub.bullets.take(3)) {
          buffer.writeln('• $b');
        }
      }
    }

    buffer.writeln('\n----------------------------------------');
    buffer.writeln('💡 提示：本清单基于国家安全强制标准与权威指南整理。采购时请仔细核对执行标准与材质标签。');
    buffer.writeln('—— 由 LifeHub 个人生活管理系统生成');

    return buffer.toString();
  }

  void _copyToClipboard(BuildContext context) {
    final text = _buildWeChatText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制微信清单至剪贴板，可直接粘贴发给家人！'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _previewCardImage(BuildContext context) async {
    setState(() => _isExporting = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();

      if (!context.mounted || bytes == null) return;

      await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('选品清单长图预览'),
            content: SingleChildScrollView(
              child: Image.memory(bytes),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制文本'),
                onPressed: () {
                  _copyToClipboard(context);
                  Navigator.pop(ctx);
                },
              ),
            ],
          );
        },
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = widget.stage;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            // Sheet Header
            Row(
              children: [
                Icon(Icons.assignment_outlined,
                    color: colorScheme.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '选品避坑安全清单导出',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              '支持一键生成微信结构化消息或长图，方便采购时发给家庭成员',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 14),

            // Action Buttons Row
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('复制微信文本'),
                    onPressed: () => _copyToClipboard(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: _isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_outlined, size: 18),
                    label: const Text('生成长图卡片'),
                    onPressed: _isExporting ? null : () => _previewCardImage(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Visual Card (Bound by RepaintBoundary for capture)
            RepaintBoundary(
              key: _cardKey,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand & Stage Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'LifeHub 选品指南',
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (widget.memberName != null)
                          Text(
                            '专属成员：${widget.memberName}',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.rawTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '全生命周期选品避坑红线与采购指导建议',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                        fontSize: 11,
                      ),
                    ),
                    const Divider(height: 24),

                    // Redlines
                    if (s.redlines.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: colorScheme.error.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    size: 18, color: colorScheme.error),
                                const SizedBox(width: 6),
                                Text(
                                  '核心安全红线 (严禁违背)',
                                  style: TextStyle(
                                    color: colorScheme.error,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final r in s.redlines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('🚨 ',
                                        style: TextStyle(
                                            color: colorScheme.error,
                                            fontSize: 11)),
                                    Expanded(
                                      child: Text(
                                        r,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onErrorContainer,
                                          fontWeight: FontWeight.w500,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Subsections Checklist
                    Text(
                      '采购要点与选品清单',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final sub in s.subsections.take(4)) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '▶ ${sub.title}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            for (final b in sub.bullets.take(3))
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• ',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Expanded(
                                      child: Text(
                                        b,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontSize: 11,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '—— 守护全家健康 · 科学理性消费 ——',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
