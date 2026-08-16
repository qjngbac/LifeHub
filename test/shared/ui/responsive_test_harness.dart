import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ResponsiveTestCase {
  const ResponsiveTestCase(
    this.name, {
    required this.size,
    required this.textScale,
    this.keyboardHeight = 0,
  });

  final String name;
  final Size size;
  final double textScale;
  final double keyboardHeight;
}

const phoneAccessibilityMatrix = <ResponsiveTestCase>[
  ResponsiveTestCase(
    'compact',
    size: Size(320, 568),
    textScale: 1,
  ),
  ResponsiveTestCase(
    'compact-large-text',
    size: Size(320, 568),
    textScale: 2,
  ),
  ResponsiveTestCase(
    'medium-large-text',
    size: Size(360, 800),
    textScale: 1.6,
  ),
  ResponsiveTestCase(
    'large-phone',
    size: Size(412, 915),
    textScale: 1.3,
  ),
];

Future<void> configurePhone(
  WidgetTester tester,
  ResponsiveTestCase testCase,
) async {
  tester.view.physicalSize = testCase.size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: testCase.keyboardHeight);
  tester.platformDispatcher.textScaleFactorTestValue = testCase.textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void expectNoLayoutFailure(WidgetTester tester) {
  final errors = <Object>[];
  Object? error;
  while ((error = tester.takeException()) != null) {
    errors.add(error!);
  }
  expect(errors, isEmpty, reason: errors.join('\n\n'));
}
