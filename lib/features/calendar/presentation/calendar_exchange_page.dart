import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/calendar/domain/ics_codec.dart';
import 'package:lifehub/features/event/data/event_repository.dart';

class CalendarExchangePage extends ConsumerWidget {
  const CalendarExchangePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('日历导入导出')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.visibility_outlined),
                title: Text('始终先预览'),
                subtitle: Text('导入不会静默覆盖数据；不支持的重复规则会明确提示。'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('导入 ICS 文件'),
                subtitle: const Text('预览标题、时间与警告后再确认'),
                onTap: () => _import(context, ref),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('导出未来一年日程'),
                subtitle: const Text('周期与心情等隐私数据不会进入普通日历'),
                onTap: () => _export(context, ref),
              ),
            ),
          ],
        ),
      );

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ics'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final source = file.bytes != null
          ? utf8.decode(file.bytes!)
          : await File(file.path!).readAsString();
      final result = IcsCodec.decode(source);
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Text('预览 ${result.items.length} 项日程'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...result.warnings.map(
                      (warning) => ListTile(
                        leading: const Icon(Icons.warning_amber_outlined),
                        title: Text(warning),
                      ),
                    ),
                    ...result.items.take(20).map(
                          (item) => ListTile(
                            title: Text(item.title),
                            subtitle: Text(item.start.toLocal().toString()),
                          ),
                        ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: result.items.isEmpty
                        ? null
                        : () => Navigator.pop(context, true),
                    child: const Text('确认导入')),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      final repository = EventRepository(ref.read(databaseProvider));
      for (final item in result.items) {
        await repository.create(EventDraft(
          title: item.title,
          start: item.start.toLocal(),
          end: item.end.toLocal(),
          allDay: item.allDay,
          localDate: item.allDay
              ? item.start.year * 10000 +
                  item.start.month * 100 +
                  item.start.day
              : null,
          location: item.location,
          notes: item.notes,
        ));
      }
      ref.read(refreshProvider.notifier).state++;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${result.items.length} 项')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ICS 文件无法解析')));
      }
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final now = DateTime.now();
      final events = await EventRepository(ref.read(databaseProvider))
          .listWindow(now, now.add(const Duration(days: 366)));
      final items = events
          .map((event) => CalendarExchangeItem(
                uid: event.id,
                title: event.title,
                start: DateTime.fromMillisecondsSinceEpoch(
                  event.startAt,
                  isUtc: true,
                ).toLocal(),
                end: DateTime.fromMillisecondsSinceEpoch(
                  event.endAt,
                  isUtc: true,
                ).toLocal(),
                allDay: event.allDay,
                location: event.location,
                notes: event.notes,
              ))
          .toList();
      final bytes = Uint8List.fromList(utf8.encode(IcsCodec.encode(items)));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出 LifeHub 日历',
        fileName: 'lifehub_calendar.ics',
        type: FileType.custom,
        allowedExtensions: const ['ics'],
        bytes: bytes,
      );
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('日历已导出')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('日历导出失败')));
      }
    }
  }
}
