import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/entertainment/domain/entertainment_models.dart';
import 'package:lifehub/features/entertainment/data/entertainment_repository.dart';
import 'package:lifehub/features/entertainment/presentation/entertainment_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('detail advances and reports the end of its sequence',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final repository = EntertainmentRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    const items = [
      EntertainmentItem(
        id: 'one',
        categoryId: 'test',
        category: '测试',
        group: 'joke',
        contentType: 'joke',
        title: '第一条',
        body: '第一条正文',
        estimatedReadSeconds: 10,
      ),
      EntertainmentItem(
        id: 'two',
        categoryId: 'test',
        category: '测试',
        group: 'joke',
        contentType: 'joke',
        title: '第二条',
        body: '第二条正文',
        estimatedReadSeconds: 10,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: EntertainmentItemPage(
        item: items.first,
        items: items,
        repository: repository,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(items.first.title), findsOneWidget);
    expect(find.text('置为最后'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('置为最后'),
        matching: find.byType(Expanded),
      ),
      findsNothing,
      reason: '娱乐操作不得被强行压成三等分后截断文字。',
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, '下一条'));
    await tester.pumpAndSettle();
    expect(find.text(items.last.title), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '下一条'));
    await tester.pump();
    expect(find.text('这已经是最后一条了'), findsOneWidget);
  });

  testWidgets('脑筋急转弯默认藏住答案，点击后才揭晓', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = EntertainmentRepository(
      preferences: await SharedPreferences.getInstance(),
    );
    const item = EntertainmentItem(
      id: 'riddle',
      categoryId: 'test',
      category: '脑筋急转弯',
      group: 'joke',
      contentType: 'riddle',
      title: '什么门永远关不上？',
      body: '答案：球门',
      estimatedReadSeconds: 8,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EntertainmentItemPage(item: item, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('点击揭晓答案'), findsOneWidget);
    expect(
      find.byType(SelectableText),
      findsNothing,
      reason: '未揭晓时不能把答案正文渲染出来（否则等于直接剧透）',
    );

    await tester.tap(find.text('点击揭晓答案'));
    await tester.pumpAndSettle();

    expect(find.text('点击揭晓答案'), findsNothing);
    final revealed =
        tester.widget<SelectableText>(find.byType(SelectableText));
    expect(revealed.data, '球门');
    expect(tester.takeException(), isNull);
  });
}
