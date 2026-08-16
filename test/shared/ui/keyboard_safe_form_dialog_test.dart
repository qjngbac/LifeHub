import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

void main() {
  testWidgets('keeps title and actions visible above the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => KeyboardSafeFormDialog(
                title: const Text('新建任务'),
                body: Column(children: [
                  for (var index = 0; index < 8; index++)
                    TextField(
                        decoration: InputDecoration(labelText: '字段$index')),
                ]),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('取消')),
                  FilledButton(onPressed: () {}, child: const Text('保存')),
                ],
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('新建任务'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(tester.getBottomRight(find.text('保存')).dy, lessThan(480));
    expect(tester.takeException(), isNull);
  });
}
