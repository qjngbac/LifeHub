import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/calendar/domain/ics_codec.dart';
import 'package:lifehub/features/calendar/presentation/calendar_exchange_page.dart';
import 'package:lifehub/features/event/data/event_repository.dart';

class _ExportPicker extends FilePicker {
  Uint8List? saved;
  @override
  Future<String?> saveFile({String? dialogTitle, String? fileName,
    String? initialDirectory, FileType type = FileType.any,
    List<String>? allowedExtensions, Uint8List? bytes,
    bool lockParentWindow = false}) async {
    saved = bytes;
    return 'calendar.ics';
  }
}

void main() {
  setUpAll(() => FilePicker.platform = _ExportPicker());
  testWidgets('future-year export expands repetitions that began in the past',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final previousPicker = FilePicker.platform;
    final picker = _ExportPicker();
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = previousPicker);
    final repository = EventRepository(database);
    final now = DateTime.now();
    final past = DateTime(now.year, now.month, now.day - 7, 11);
    for (final rule in ['DAILY', 'WEEKLY']) {
      await repository.create(EventDraft(title: rule, start: past,
          end: past.add(const Duration(hours: 1)), repeatRule: 'FREQ=$rule;INTERVAL=1'));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: CalendarExchangePage()),
    ));
    await tester.tap(find.text('导出未来一年日程'));
    await tester.pumpAndSettle();
    final decoded = IcsCodec.decode(utf8.decode(picker.saved!));
    expect(decoded.items.map((row) => row.title), containsAll(['DAILY', 'WEEKLY']));
    expect(decoded.items.map((row) => row.uid).toSet(), hasLength(decoded.items.length));
    expect(decoded.items.every((row) => row.end.isAfter(now)), isTrue);
    expect(decoded.warnings, isEmpty);
  });

  for (final capacity in ['bytes', 'rows']) {
    testWidgets('calendar export rejects $capacity overflow without truncation',
        (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final previousPicker = FilePicker.platform;
      addTearDown(() => FilePicker.platform = previousPicker);
      final picker = _ExportPicker();
      FilePicker.platform = picker;
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day + 1, 11);
      final repository = EventRepository(database);
      for (var i = 0; i < (capacity == 'rows' ? 14 : 1); i++) {
        await repository.create(EventDraft(
          title: 'capacity $i', start: start,
          end: start.add(const Duration(hours: 1)),
          notes: capacity == 'bytes' ? 'x' * IcsCodec.maxImportBytes : null,
          repeatRule: capacity == 'rows' ? 'FREQ=DAILY;INTERVAL=1' : null,
        ));
      }
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: CalendarExchangePage()),
      ));
      await tester.tap(find.text('导出未来一年日程'));
      await tester.pumpAndSettle();
      expect(picker.saved, isNull);
      expect(find.textContaining('完整备份'), findsOneWidget);
    });
  }
}
