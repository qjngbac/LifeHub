import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/presentation/match_dialogs.dart';
import 'package:lifehub/shared/ui/lifehub_theme.dart';
import '../../shared/ui/responsive_test_harness.dart';

void main() {
  for (final historical in [false, true]) {
    testWidgets(
      'match form labels and grouped dates fit large text historical=$historical',
      (tester) async {
        await configurePhone(
          tester,
          const ResponsiveTestCase(
            'match-form',
            size: Size(320, 800),
            textScale: 1.6,
            keyboardHeight: 220,
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: LifeHubTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showMatchDraftDialog(
                      context,
                      finished: historical,
                      initial: MatchDraft(
                        sportType: '足球',
                        competition: '国际友谊赛',
                        participantA: '中国',
                        participantB: '马尔代夫',
                        matchDate: DateTime(2099, 10, 11),
                        startAt: historical
                            ? null
                            : DateTime.utc(2099, 10, 11, 12),
                        status: historical
                            ? MatchStatuses.finished
                            : MatchStatuses.scheduled,
                      ),
                    ),
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        final label = find.text('参赛方 A *');
        expect(label, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
          isFalse,
        );
        expect(find.text('2099-'), findsOneWidget);
        expect(find.text('10-11'), findsOneWidget);
        expect(find.text('补充信息'), findsNothing);
        expect(find.text('交换双方'), findsNothing);
        final a = find.widgetWithText(TextField, '参赛方 A *');
        final b = find.widgetWithText(TextField, '参赛方 B *');
        expect(tester.getTopLeft(a).dy, tester.getTopLeft(b).dy);
        expect(find.byTooltip('主客对调'), findsOneWidget);
        final decorations = tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => field.decoration?.labelText ?? '')
            .toList();
        expect(decorations.any((label) => label.contains('可选')), isFalse);
        expect(
          tester.getRect(find.widgetWithText(FilledButton, '保存')).bottom,
          lessThanOrEqualTo(580),
        );
        expectNoLayoutFailure(tester);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expectNoLayoutFailure(tester);
      },
    );
  }
}
