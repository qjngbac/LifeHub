import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/library/presentation/note_edit_page.dart';

void main() {
  group('stripMarkdownDecorators tests', () {
    test('strips bold, strikethrough, italic, bold+italic, and heading prefixes', () {
      expect(stripMarkdownDecorators('**瑞幸**'), '瑞幸');
      expect(stripMarkdownDecorators('***双柚美式***'), '双柚美式');
      expect(stripMarkdownDecorators('~~生椰拿铁~~'), '生椰拿铁');
      expect(stripMarkdownDecorators('*美式*'), '美式');
      expect(stripMarkdownDecorators('# 一级标题\n## 二级标题'), '一级标题\n二级标题');
      expect(
        stripMarkdownDecorators('**瑞幸** ~~生椰拿铁~~ *咖啡* ***特调***'),
        '瑞幸 生椰拿铁 咖啡 特调',
      );
    });
  });

  group('Markdown formatting engine tests (toggleMarkdownStyle & word detection)', () {
    test('two-character short line formatting: bold, italic toggle, combine and untoggle seamlessly', () {
      const text = '库迪';
      // 1. 选中“库迪”（两字），点击加粗
      final res1 = toggleMarkdownStyle(
        text: text,
        targetStart: 0,
        targetEnd: 2,
        style: MarkdownInlineStyle.bold,
      );
      expect(res1.newText, '**库迪**');
      expect(res1.selectionStart, 2);
      expect(res1.selectionEnd, 4);

      // 2. 在加粗状态下，再点击斜体 -> 升级为粗斜体 ***库迪***
      final res2 = toggleMarkdownStyle(
        text: res1.newText,
        targetStart: res1.selectionStart,
        targetEnd: res1.selectionEnd,
        style: MarkdownInlineStyle.italic,
      );
      expect(res2.newText, '***库迪***');
      expect(res2.selectionStart, 3);
      expect(res2.selectionEnd, 5);

      // 3. 在粗斜体状态下，再次点击加粗 -> 取消加粗，保留斜体 *库迪*
      final res3 = toggleMarkdownStyle(
        text: res2.newText,
        targetStart: res2.selectionStart,
        targetEnd: res2.selectionEnd,
        style: MarkdownInlineStyle.bold,
      );
      expect(res3.newText, '*库迪*');
      expect(res3.selectionStart, 1);
      expect(res3.selectionEnd, 3);

      // 4. 再次点击斜体 -> 取消斜体，变回纯文本“库迪”
      final res4 = toggleMarkdownStyle(
        text: res3.newText,
        targetStart: res3.selectionStart,
        targetEnd: res3.selectionEnd,
        style: MarkdownInlineStyle.italic,
      );
      expect(res4.newText, '库迪');
      expect(res4.selectionStart, 0);
      expect(res4.selectionEnd, 2);
    });

    test('supports strikethrough combination without breaking markers', () {
      const text = '拿铁';
      final res1 = toggleMarkdownStyle(
        text: text,
        targetStart: 0,
        targetEnd: 2,
        style: MarkdownInlineStyle.strikethrough,
      );
      expect(res1.newText, '~~拿铁~~');

      final res2 = toggleMarkdownStyle(
        text: res1.newText,
        targetStart: 2,
        targetEnd: 4,
        style: MarkdownInlineStyle.bold,
      );
      expect(res2.newText, '~~**拿铁**~~');

      final res3 = toggleMarkdownStyle(
        text: res2.newText,
        targetStart: 4,
        targetEnd: 6,
        style: MarkdownInlineStyle.strikethrough,
      );
      expect(res3.newText, '**拿铁**');
    });

    test('findWordRangeAt smart word detection at cursor', () {
      const text = '库迪\n双柚美式 咖啡';
      // 光标在第一行末尾（紧跟“迪”）
      final range1 = findWordRangeAt(text, 2);
      expect(range1, isNotNull);
      expect(text.substring(range1!.start, range1.end), '库迪');

      // 光标在第二行“双柚美式”中间
      final range2 = findWordRangeAt(text, 5);
      expect(range2, isNotNull);
      expect(text.substring(range2!.start, range2.end), '双柚美式');

      // 光标在空行或空白处返回 null
      expect(findWordRangeAt('\n\n', 1), isNull);
      expect(findWordRangeAt('   ', 1), isNull);
    });
  });

  group('NoteUndoController tests', () {
    test('handles undo and redo history correctly', () {
      final undoController = NoteUndoController();
      expect(undoController.canUndo, false);
      expect(undoController.canRedo, false);

      const val1 = TextEditingValue(text: 'A');
      const val2 = TextEditingValue(text: 'AB');
      const val3 = TextEditingValue(text: 'ABC');

      undoController.recordChange(val1);
      undoController.recordChange(val2);
      expect(undoController.canUndo, true);
      expect(undoController.canRedo, false);

      final previous = undoController.undo(val3);
      expect(previous?.text, 'AB');
      expect(undoController.canUndo, true);
      expect(undoController.canRedo, true);

      final next = undoController.redo(previous!);
      expect(next?.text, 'ABC');
      expect(undoController.canRedo, false);
    });
  });

  group('NoteTextEditingController tests', () {
    testWidgets('preserves exact string length in buildTextSpan for accurate cursor positioning', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(SizedBox));
      final controller = NoteTextEditingController(
        text: '# 标题\n**瑞幸**\n~~生椰拿铁~~\n*斜体*\n***特调***',
      );
      final span = controller.buildTextSpan(
        context: context,
        withComposing: false,
      );

      int countSpanLength(InlineSpan s) {
        int length = 0;
        if (s is TextSpan) {
          length += (s.text?.length ?? 0);
          if (s.children != null) {
            for (final child in s.children!) {
              length += countSpanLength(child);
            }
          }
        }
        return length;
      }

      final totalSpanLength = countSpanLength(span);
      expect(totalSpanLength, controller.text.length);
    });

    test('preserves unrestricted multi-line long-press drag selection across newlines', () {
      final controller = NoteTextEditingController(text: '第一行\n第二行\n第三行\n第四行');
      // 用户长按并拖选跨越多行（0 到 10）
      controller.value = const TextEditingValue(
        text: '第一行\n第二行\n第三行\n第四行',
        selection: TextSelection(baseOffset: 0, extentOffset: 10),
      );

      // 绝不擅自截断或回弹选区，保持原生拖拽跨行流畅度
      expect(controller.selection.start, 0);
      expect(controller.selection.end, 10);
    });

    test('smart backspace deletion directly removes character and preserves/cleans formatting without exposing asterisks', () {
      final controller = NoteTextEditingController(text: '**库迪**');

      // 1. 用户光标在 **库迪** 末尾按 Backspace，键盘删除了末尾的一个 '*'（变为 '**库迪*'）
      controller.value = const TextEditingValue(
        text: '**库迪*',
        selection: TextSelection.collapsed(offset: 5),
      );

      // 拦截器生效：直接删除内部汉字“迪”，保留粗体格式 '**库**'，绝不暴露残缺星号
      expect(controller.text, '**库**');
      expect(controller.selection.baseOffset, 3);

      // 2. 再次按 Backspace，键盘删除了 '**库**' 末尾的一个 '*'（变为 '**库*'）
      controller.value = const TextEditingValue(
        text: '**库*',
        selection: TextSelection.collapsed(offset: 4),
      );

      // 拦截器生效：唯一字符“库”被删除，整个格式块彻底消失为干净空串，绝不留下 '****'
      expect(controller.text, '');
      expect(controller.selection.baseOffset, 0);
    });

    test('smart backspace on italic and strikethrough directly deletes characters', () {
      final controller1 = NoteTextEditingController(text: '*美式*');
      controller1.value = const TextEditingValue(
        text: '*美式',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(controller1.text, '*美*');

      final controller2 = NoteTextEditingController(text: '~~拿铁~~');
      controller2.value = const TextEditingValue(
        text: '~~拿铁~',
        selection: TextSelection.collapsed(offset: 5),
      );
      expect(controller2.text, '~~拿~~');
    });

    test('auto-purges empty formatting markers when inner content is replaced', () {
      final controller = NoteTextEditingController(text: '**库迪**');
      // 内部全部选中并删除
      controller.value = const TextEditingValue(
        text: '****',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(controller.text, '');
    });
  });

  group('NoteEditPage Widget tests', () {
    testWidgets('renders toolbar above keyboard and AppBar undo/redo icons', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NoteEditPage(),
          ),
        ),
      );

      expect(find.byType(NoteEditPage), findsOneWidget);
      expect(find.byIcon(Icons.undo_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.redo_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.format_bold), findsOneWidget);
      expect(find.byIcon(Icons.format_strikethrough), findsOneWidget);
    });

    testWidgets('exiting existing note without modification does not bump updatedAt', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = SavedItemRepository(db);
      final created = await repo.create(
        const SavedItemDraft(title: '原有便签', content: '原有内容'),
      );
      final initialUpdatedAt = created.updatedAt;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            home: NoteEditPage(initialNote: created),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击返回图标
      await tester.tap(find.byTooltip('返回并保存'));
      await tester.pumpAndSettle();

      final reloaded = await repo.get(created.id);
      expect(reloaded.updatedAt, initialUpdatedAt);
      expect(reloaded.version, created.version);
      await db.close();
    });
  });
}


