import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/household/data/household_repository.dart';

void main() {
  late AppDatabase database;
  late HouseholdRepository repository;
  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = HouseholdRepository(database);
  });
  tearDown(() => database.close());

  test('validates purchase data and calculates warranty state', () async {
    expect(
      () => repository.create(const HouseholdDraft(name: '')),
      throwsArgumentError,
    );
    expect(
      () => repository.create(const HouseholdDraft(
        name: '耳机',
        purchaseAmountMinor: -1,
      )),
      throwsArgumentError,
    );
    final item = await repository.create(HouseholdDraft(
      name: '耳机',
      purchaseDate: DateTime(2026, 1, 1),
      warrantyEndDate: DateTime(2027, 1, 1),
      purchaseAmountMinor: 89900,
    ));
    expect(repository.warrantyState(item, DateTime(2026, 12, 10)),
        WarrantyState.expiringSoon);
    expect(repository.warrantyState(item, DateTime(2027, 1, 2)),
        WarrantyState.expired);
  });

  test('archives and soft deletes household items', () async {
    final item = await repository.create(const HouseholdDraft(name: '电饭煲'));
    await repository.archive(item.id);
    expect(await repository.list(), isEmpty);
    expect((await repository.list(includeArchived: true)).single.status,
        'ARCHIVED');
    await repository.delete(item.id);
    expect(await repository.list(includeArchived: true), isEmpty);
  });

  test('updates all editable household fields', () async {
    final item = await repository.create(const HouseholdDraft(name: '旧名称'));
    final updated = await repository.update(
      item.id,
      HouseholdDraft(
        name: '笔记本电脑',
        brandModel: '联想 小新 Pro',
        purchaseDate: DateTime(2026, 8, 1),
        warrantyEndDate: DateTime(2028, 8, 1),
        notes: '保修凭证在附件',
      ),
    );
    expect(updated.name, '笔记本电脑');
    expect(updated.brandModel, '联想 小新 Pro');
    expect(updated.notes, '保修凭证在附件');
    expect(updated.version, item.version + 1);
  });

  test('stores consumable quantity and reports low stock', () async {
    final item = await repository.create(HouseholdDraft(
      name: '咖啡豆',
      itemKind: HouseholdItemKind.consumable,
      quantity: 1,
      unit: '袋',
      minimumQuantity: 2,
      expiryDate: DateTime(2026, 8, 20),
    ));

    expect(item.itemKind, 'CONSUMABLE');
    expect(repository.consumableState(item, DateTime(2026, 8, 15)).lowStock,
        isTrue);
    expect(
      () => repository.create(const HouseholdDraft(
        name: '无效库存',
        itemKind: HouseholdItemKind.consumable,
        quantity: -1,
      )),
      throwsRangeError,
    );
  });

  test('adds a low-stock consumable to one active shopping list item',
      () async {
    final item = await repository.create(const HouseholdDraft(
      name: '洗衣液',
      itemKind: HouseholdItemKind.consumable,
      quantity: 0,
      minimumQuantity: 1,
      unit: '瓶',
    ));

    final first = await repository.addToShoppingList(item.id);
    final second = await repository.addToShoppingList(item.id);
    final lists = await database.select(database.lists).get();
    final items = await database.select(database.listItems).get();

    expect(first.id, second.id);
    expect(lists.single.title, '购物');
    expect(items.single.textValue, '洗衣液');
    expect(items.single.checked, isFalse);
  });
}
