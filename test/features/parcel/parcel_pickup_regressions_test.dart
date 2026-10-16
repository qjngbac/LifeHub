import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/parcel/data/parcel_repository.dart';
import 'package:lifehub/features/parcel/presentation/parcel_form_style.dart';
import 'package:lifehub/features/parcel/presentation/parcels_page.dart';

/// 快递取件的「实用」回归：取件倒计时、到达时间、检索范围与状态流转。
void main() {
  late AppDatabase database;
  late ParcelRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ParcelRepository(database);
  });
  tearDown(() => database.close());

  test('快递默认不标私密：模块不做二级密码门禁', () async {
    final parcel = await repository.create(
      const ParcelDraft(title: '苹果'),
    );
    expect(
      parcel.sensitive,
      isFalse,
      reason: '界面上没有密码门禁，却把数据标成私密会让备份/同步逻辑误判',
    );
  });

  testWidgets('添加快递表单里没有私密开关', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: ParcelsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('快递'));
    await tester.pumpAndSettle();
    expect(find.text('添加快递'), findsOneWidget);
    expect(find.text('私密保护'), findsNothing);
    expect(find.text('取件截止（可选）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('到达取件点时自动记录到达时间（倒计时的基准）', () async {
    final parcel = await repository.create(
      const ParcelDraft(title: '书籍'),
    );
    expect(parcel.arrivedAt, isNull);

    final arrived = await repository.advance(parcel.id);
    expect(arrived.status, ParcelStatus.ready.dbValue);
    expect(arrived.arrivedAt, isNotNull,
        reason: '进入待取件必须记录到达时间，否则"到柜多久没取"算不出来');

    // 再次推进不再覆盖到达时间
    final before = arrived.arrivedAt;
    final collected = await repository.advance(parcel.id);
    expect(collected.arrivedAt, before);
  });

  test('可以标记退回，且退回后不再参与推进', () async {
    final parcel = await repository.create(
      const ParcelDraft(title: '退件', status: ParcelStatus.ready),
    );
    final returned = await repository.markReturned(parcel.id);
    expect(returned.status, ParcelStatus.returned.dbValue);

    final unchanged = await repository.advance(parcel.id);
    expect(unchanged.status, ParcelStatus.returned.dbValue);
  });

  test('检索覆盖物品信息，且保留 LIKE 字面量转义', () async {
    await repository.create(
      const ParcelDraft(title: '耳机', notes: '顺丰到付 3 件'),
    );
    await repository.create(
      const ParcelDraft(title: '100%完成'),
    );
    await repository.create(
      const ParcelDraft(title: '1000完成'),
    );
    await repository.create(
      const ParcelDraft(title: 'A_B'),
    );

    expect(await repository.search('顺丰到付'), hasLength(1),
        reason: '写在"物品信息"里的内容必须能搜到');
    expect((await repository.search('100%')).map((e) => e.title), ['100%完成']);
    expect((await repository.search('A_B')).map((e) => e.title), ['A_B']);
  });

  group('取件截止倒计时提示', () {
    final now = DateTime(2026, 10, 12, 9, 0);

    test('超过 24 小时只提示还剩几天', () {
      final hint = pickupDeadlineHint(
        status: 'READY',
        pickupDeadline: now.add(const Duration(days: 3)).millisecondsSinceEpoch,
        arrivedAt: null,
        now: now,
      );
      expect(hint?.text, '3 天后到期');
      expect(hint?.tone, 0);
    });

    test('24 小时内提示剩余小时', () {
      final hint = pickupDeadlineHint(
        status: 'READY',
        pickupDeadline: now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
        arrivedAt: null,
        now: now,
      );
      expect(hint?.text, '剩 5 小时取件');
      expect(hint?.tone, 1);
    });

    test('不到一小时提示剩余分钟', () {
      final hint = pickupDeadlineHint(
        status: 'READY',
        pickupDeadline: now.add(const Duration(minutes: 40)).millisecondsSinceEpoch,
        arrivedAt: null,
        now: now,
      );
      expect(hint?.text, '剩 40 分钟取件');
      expect(hint?.tone, 1);
    });

    test('已超时用红色提示并给出超时小时数', () {
      final hint = pickupDeadlineHint(
        status: 'READY',
        pickupDeadline: now.subtract(const Duration(hours: 7)).millisecondsSinceEpoch,
        arrivedAt: null,
        now: now,
      );
      expect(hint?.text, '已超时 7 小时');
      expect(hint?.tone, 2);
    });

    test('已取件 / 已退回 / 没有截止时间都不提示', () {
      for (final status in ['COLLECTED', 'RETURNED']) {
        expect(
          pickupDeadlineHint(
            status: status,
            pickupDeadline: now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
            arrivedAt: null,
            now: now,
          ),
          isNull,
        );
      }
      expect(
        pickupDeadlineHint(
          status: 'READY',
          pickupDeadline: null,
          arrivedAt: null,
          now: now,
        ),
        isNull,
      );
    });
  });
}
