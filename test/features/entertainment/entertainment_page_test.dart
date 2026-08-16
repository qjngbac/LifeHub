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
}
