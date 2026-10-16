import 'package:flutter/material.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/project/data/project_repository.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

const List<String> projectColorPalette = [
  '#4F46E5', // 经典靛青
  '#0EA5E9', // 天空之蓝
  '#10B981', // 翡翠深绿
  '#F59E0B', // 琥珀暖黄
  '#F43F5E', // 玫瑰绯红
  '#8B5CF6', // 梦幻紫罗兰
  '#14B8A6', // 沧浪青碧
  '#F97316', // 活力暖橙
];

Color parseProjectColor(String? hex, [Color fallback = const Color(0xFF4F46E5)]) {
  if (hex == null || hex.isEmpty) return fallback;
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  } else if (clean.length == 8) {
    return Color(int.parse(clean, radix: 16));
  }
  return fallback;
}

Future<ProjectDraft?> showProjectForm(
  BuildContext context, {
  ProjectEntry? current,
}) async {
  final nameController = TextEditingController(text: current?.name);
  final descController = TextEditingController(text: current?.description);
  String selectedColor = current?.color ?? '#4F46E5';
  String? error;

  final result = await showDialog<ProjectDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final theme = Theme.of(context);
        return KeyboardSafeFormDialog(
          title: Text(current == null ? '新建项目' : '编辑项目'),
          body: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: current == null,
                  decoration: const InputDecoration(
                    labelText: '项目名称 *',
                    hintText: '如 2026 生活重构与健康计划',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '愿景与目标描述（可选）',
                    hintText: '简要描述该项目期望达成的愿景…',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '项目主题色',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: projectColorPalette.map((hex) {
                    final color = parseProjectColor(hex);
                    final isSelected =
                        selectedColor.toUpperCase() == hex.toUpperCase();
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setDialogState(() => selectedColor = hex),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.onSurface
                                : Colors.transparent,
                            width: isSelected ? 2.5 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded,
                                size: 20, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => error = '请输入项目名称');
                  return;
                }
                Navigator.pop(
                  context,
                  ProjectDraft(
                    name: name,
                    description: descController.text.trim().isEmpty
                        ? null
                        : descController.text.trim(),
                    color: selectedColor,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );

  nameController.dispose();
  descController.dispose();
  return result;
}
