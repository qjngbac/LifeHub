import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';

Color mediaCategoryColor(MediaCategory category) => switch (category) {
      MediaCategory.tv => const Color(0xFF2563EB),
      MediaCategory.anime => const Color(0xFFE11D48),
      MediaCategory.movie => const Color(0xFF0D9488),
    };

Color mediaCategoryLightColor(MediaCategory category) => switch (category) {
      MediaCategory.tv => const Color(0xFFEFF6FF),
      MediaCategory.anime => const Color(0xFFFFF1F2),
      MediaCategory.movie => const Color(0xFFF0FDFA),
    };

List<Color> mediaCategoryGradient(MediaCategory category) => switch (category) {
      MediaCategory.tv => const [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
      MediaCategory.anime => const [Color(0xFFFB7185), Color(0xFFE11D48)],
      MediaCategory.movie => const [Color(0xFF14B8A6), Color(0xFF0F766E)],
    };

IconData mediaCategoryIcon(MediaCategory category) => switch (category) {
      MediaCategory.tv => Icons.tv_rounded,
      MediaCategory.anime => Icons.animation_rounded,
      MediaCategory.movie => Icons.movie_filter_rounded,
    };

Color mediaStatusColor(MediaWatchStatus status) => switch (status) {
      MediaWatchStatus.plan => const Color(0xFF6366F1),
      MediaWatchStatus.watching => const Color(0xFFF59E0B),
      MediaWatchStatus.completed => const Color(0xFF10B981),
      MediaWatchStatus.paused => const Color(0xFF64748B),
      MediaWatchStatus.dropped => const Color(0xFF94A3B8),
    };

Color mediaStatusLightColor(MediaWatchStatus status) => switch (status) {
      MediaWatchStatus.plan => const Color(0xFFEEF2FF),
      MediaWatchStatus.watching => const Color(0xFFFFFBEB),
      MediaWatchStatus.completed => const Color(0xFFECFDF5),
      MediaWatchStatus.paused => const Color(0xFFF1F5F9),
      MediaWatchStatus.dropped => const Color(0xFFF8FAFC),
    };

String formatRelativeDate(DateTime? dateTime) {
  if (dateTime == null) return '';
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inSeconds < 60) {
    return '刚刚';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes}分钟前';
  } else if (difference.inHours < 24) {
    return '${difference.inHours}小时前';
  } else if (difference.inDays == 1) {
    return '昨天 ${DateFormat('HH:mm').format(dateTime)}';
  } else if (difference.inDays < 7) {
    return '${difference.inDays}天前';
  } else if (dateTime.year == now.year) {
    return DateFormat('MM-dd HH:mm').format(dateTime);
  } else {
    return DateFormat('yyyy-MM-dd').format(dateTime);
  }
}

Future<int?> showEpisodeProgressDialog(
  BuildContext context,
  MediaEntry entry,
) async {
  final controller = TextEditingController(
    text: entry.completedEpisodes.toString(),
  );
  final formKey = GlobalKey<FormState>();
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        void adjust(int delta) {
          final current =
              int.tryParse(controller.text.trim()) ?? entry.completedEpisodes;
          var newVal = current + delta;
          if (newVal < 0) newVal = 0;
          if (entry.totalEpisodes != null && newVal > entry.totalEpisodes!) {
            newVal = entry.totalEpisodes!;
          }
          controller.text = newVal.toString();
          setDialogState(() {});
        }

        void setFixed(int target) {
          controller.text = target.toString();
          setDialogState(() {});
        }

        return AlertDialog(
          title: Text('修改《${entry.title}》进度'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: '后退 1 集',
                      icon: const Icon(Icons.remove),
                      onPressed: () => adjust(-1),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: controller,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '已看集数',
                          helperText: entry.totalEpisodes == null
                              ? null
                              : '共 ${entry.totalEpisodes} 集',
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value?.trim() ?? '');
                          if (parsed == null || parsed < 0) {
                            return '请输入不小于 0 的整数';
                          }
                          if (entry.totalEpisodes != null &&
                              parsed > entry.totalEpisodes!) {
                            return '不能超过总集数';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: '前进 1 集',
                      icon: const Icon(Icons.add),
                      onPressed: () => adjust(1),
                    ),
                  ],
                ),
                if (entry.totalEpisodes != null && entry.totalEpisodes! > 1) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.first_page, size: 16),
                        label: const Text('从头开始 (0)'),
                        onPressed: () => setFixed(0),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.last_page, size: 16),
                        label: Text('全部看完 (${entry.totalEpisodes})'),
                        onPressed: () => setFixed(entry.totalEpisodes!),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(
                      dialogContext, int.parse(controller.text.trim()));
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );
}

void showDeletedEntryUndo(
  BuildContext context,
  MediaRepository repository,
  MediaEntry entry, {
  required VoidCallback onRestored,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('已删除《${entry.title}》'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await repository.restoreEntry(entry.id);
            onRestored();
          },
        ),
      ),
    );
}

