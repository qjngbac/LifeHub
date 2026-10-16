import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/library/presentation/note_edit_page.dart';
import 'package:lifehub/shared/ui/lifehub_theme.dart';

import '../../shared/ui/responsive_test_harness.dart';

Finder get _contentField => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.controller is NoteTextEditingController,
);

Future<void> _pumpNote(
  WidgetTester tester,
  AppDatabase database,
  SavedItemEntry note, {
  double keyboard = 0,
}) async {
  await configurePhone(
    tester,
    ResponsiveTestCase(
      'note-tags',
      size: const Size(390, 844),
      textScale: 1,
      keyboardHeight: keyboard,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        theme: LifeHubTheme.light(),
        home: NoteEditPage(initialNote: note),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('short note tags follow the last line and align from the left', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SavedItemRepository(database);
    final note = await repository.create(
      const SavedItemDraft(title: '咖啡', content: '**库迪**\n双柚美式7'),
    );
    await repository.replaceTags(note.id, ['咖啡', '清单']);
    await _pumpNote(tester, database, note);

    final content = find.descendant(
      of: _contentField,
      matching: find.byType(EditableText),
    );
    final render = tester.state<EditableTextState>(content).renderEditable;
    final lastLine = render.localToGlobal(
      render
          .getLocalRectForCaret(TextPosition(offset: note.content!.length))
          .bottomLeft,
    );
    final firstTag = tester.getRect(find.widgetWithText(Chip, '# 咖啡'));
    final secondTag = tester.getRect(find.widgetWithText(Chip, '# 清单'));
    expect(firstTag.left, closeTo(20, 1));
    expect(firstTag.top, greaterThanOrEqualTo(lastLine.dy));
    expect(firstTag.top - lastLine.dy, lessThan(40));
    expect(secondTag.top, firstTag.top);
    expect(secondTag.left, greaterThan(firstTag.right));
    expectNoLayoutFailure(tester);
  });

  testWidgets(
    'adding a tag reveals article end above the keyboard and saves tags only',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SavedItemRepository(database);
      final text = List.generate(40, (i) => '**库迪$i**\n咖啡清单$i').join('\n');
      final note = await repository.create(
        SavedItemDraft(title: '长便签', content: text),
      );
      await repository.replaceTags(note.id, ['咖啡']);
      await _pumpNote(tester, database, note, keyboard: 260);

      final controller = tester.widget<TextField>(_contentField).controller!;
      await tester.tapAt(
        tester.getTopLeft(_contentField) + const Offset(20, 10),
      );
      const selection = TextSelection(baseOffset: 2, extentOffset: 4);
      controller.selection = selection;
      await tester.pumpAndSettle();
      final toolbarTop = tester.getRect(find.byTooltip('加粗')).top;
      expect(
        tester.getRect(find.widgetWithText(Chip, '# 咖啡')).top,
        greaterThan(toolbarTop),
      );
      final addTag = find.byTooltip('添加标签');
      await tester.ensureVisible(addTag);
      await tester.tap(addTag);
      await tester.pumpAndSettle();
      expect(find.text('添加便签标签'), findsOneWidget);
      expect(
        tester.getRect(find.widgetWithText(Chip, '# 咖啡')).bottom,
        lessThanOrEqualTo(toolbarTop),
      );
      final dialogInput = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogInput, '新标签');
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.widgetWithText(Chip, '# 新标签')).bottom,
        lessThanOrEqualTo(toolbarTop),
      );
      expect(controller.selection, selection);
      expect((await repository.get(note.id)).content, text);
      expect(
        (await repository.tagsFor(note.id)).map((tag) => tag.name),
        containsAll(['咖啡', '新标签']),
      );
      expectNoLayoutFailure(tester);
    },
  );

  testWidgets(
    'article scrolling preserves native multiline selection and formatting',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final text = List.generate(30, (i) => '**库迪$i**\n咖啡清单$i').join('\n');
      final repository = SavedItemRepository(database);
      final note = await repository.create(
        SavedItemDraft(title: '拖选测试', content: text),
      );
      await repository.replaceTags(note.id, ['咖啡']);
      await _pumpNote(tester, database, note, keyboard: 260);
      final controller = tester.widget<TextField>(_contentField).controller!;
      final editable = tester.state<EditableTextState>(
        find.descendant(of: _contentField, matching: find.byType(EditableText)),
      );
      final render = editable.renderEditable;
      Offset caretCenter(int offset) => render.localToGlobal(
        render.getLocalRectForCaret(TextPosition(offset: offset)).center,
      );

      final gesture = await tester.startGesture(caretCenter(3));
      await tester.pump(const Duration(milliseconds: 600));
      final base = controller.selection.baseOffset;
      await gesture.moveTo(caretCenter(text.indexOf('咖啡清单3') + 3));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.selection.baseOffset, base);
      expect(controller.selection.textInside(text), contains('\n'));
      await gesture.up();
      await tester.pumpAndSettle();
      editable.hideToolbar();

      final start = text.indexOf('咖啡清单3');
      controller.selection = TextSelection(
        baseOffset: start,
        extentOffset: start + 5,
      );
      await tester.tap(find.byTooltip('加粗'));
      await tester.pumpAndSettle();
      expect(controller.text, contains('**咖啡清单3**'));
      expect(controller.text, contains('**库迪0**'));
      expectNoLayoutFailure(tester);
    },
  );

  testWidgets('editing at article end keeps the caret above the keyboard', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final text = List.generate(40, (i) => '第$i行内容').join('\n');
    final repository = SavedItemRepository(database);
    final note = await repository.create(
      SavedItemDraft(title: '光标测试', content: text),
    );
    await repository.replaceTags(note.id, ['长文']);
    await _pumpNote(tester, database, note, keyboard: 260);
    await tester.tapAt(tester.getTopLeft(_contentField) + const Offset(20, 10));
    final controller = tester.widget<TextField>(_contentField).controller!;
    controller.selection = TextSelection.collapsed(offset: text.length);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('$text\n新增内容');
    await tester.pumpAndSettle();
    final render = tester
        .state<EditableTextState>(
          find.descendant(
            of: _contentField,
            matching: find.byType(EditableText),
          ),
        )
        .renderEditable;
    final caret = render.localToGlobal(
      render
          .getLocalRectForCaret(TextPosition(offset: controller.text.length))
          .bottomLeft,
    );
    expect(
      caret.dy,
      lessThanOrEqualTo(tester.getRect(find.byTooltip('加粗')).top),
    );
    expect(controller.text, '$text\n新增内容');
    expectNoLayoutFailure(tester);
  });
}
