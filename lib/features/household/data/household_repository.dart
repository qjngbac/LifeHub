import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/household/domain/consumable_rules.dart';
import 'package:lifehub/features/list/data/list_repository.dart';

enum HouseholdItemKind {
  durable('DURABLE'),
  consumable('CONSUMABLE');

  const HouseholdItemKind(this.dbValue);
  final String dbValue;
}

enum WarrantyState { none, active, expiringSoon, expired }

class HouseholdDraft {
  const HouseholdDraft({
    required this.name,
    this.category = 'OTHER',
    this.brandModel,
    this.serialNumber,
    this.purchaseDate,
    this.purchaseAmountMinor,
    this.currency = 'CNY',
    this.warrantyEndDate,
    this.locationId,
    this.notes,
    this.sensitive = false,
    this.itemKind = HouseholdItemKind.durable,
    this.quantity = 1,
    this.unit,
    this.openedDate,
    this.expiryDate,
    this.minimumQuantity,
  });

  final String name;
  final String category;
  final String? brandModel;
  final String? serialNumber;
  final DateTime? purchaseDate;
  final int? purchaseAmountMinor;
  final String currency;
  final DateTime? warrantyEndDate;
  final String? locationId;
  final String? notes;
  final bool sensitive;
  final HouseholdItemKind itemKind;
  final double quantity;
  final String? unit;
  final DateTime? openedDate;
  final DateTime? expiryDate;
  final double? minimumQuantity;
}

class HouseholdRepository {
  HouseholdRepository(this._database);
  final AppDatabase _database;

  Future<HouseholdItemEntry> create(HouseholdDraft draft) {
    _validate(draft);
    return _database.into(_database.householdItems).insertReturning(
          HouseholdItemsCompanion.insert(
            name: draft.name.trim(),
            category: Value(draft.category),
            brandModel: Value(_optional(draft.brandModel)),
            serialNumber: Value(_optional(draft.serialNumber)),
            purchaseDate: Value(_key(draft.purchaseDate)),
            purchaseAmountMinor: Value(draft.purchaseAmountMinor),
            currency: Value(draft.currency),
            warrantyEndDate: Value(_key(draft.warrantyEndDate)),
            locationId: Value(draft.locationId),
            notes: Value(_optional(draft.notes)),
            sensitive: Value(draft.sensitive),
            itemKind: Value(draft.itemKind.dbValue),
            quantity: Value(draft.quantity),
            unit: Value(_optional(draft.unit)),
            openedDate: Value(_key(draft.openedDate)),
            expiryDate: Value(_key(draft.expiryDate)),
            minimumQuantity: Value(draft.minimumQuantity),
          ),
        );
  }

  Future<List<HouseholdItemEntry>> list({bool includeArchived = false}) {
    final query = _database.select(_database.householdItems)
      ..where((row) {
        var expression = row.deletedAt.isNull();
        if (!includeArchived) {
          expression = expression & row.status.equals('ARCHIVED').not();
        }
        return expression;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.name)]);
    return query.get();
  }

  Future<HouseholdItemEntry> get(String id) async {
    final row = await (_database.select(_database.householdItems)
          ..where((item) => item.id.equals(id) & item.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) throw StateError('Household item not found: $id');
    return row;
  }

  Future<HouseholdItemEntry> update(String id, HouseholdDraft draft) async {
    _validate(draft);
    final current = await get(id);
    await (_database.update(_database.householdItems)
          ..where((row) => row.id.equals(id)))
        .write(HouseholdItemsCompanion(
      name: Value(draft.name.trim()),
      category: Value(draft.category),
      brandModel: Value(_optional(draft.brandModel)),
      serialNumber: Value(_optional(draft.serialNumber)),
      purchaseDate: Value(_key(draft.purchaseDate)),
      purchaseAmountMinor: Value(draft.purchaseAmountMinor),
      currency: Value(draft.currency),
      warrantyEndDate: Value(_key(draft.warrantyEndDate)),
      locationId: Value(draft.locationId),
      notes: Value(_optional(draft.notes)),
      sensitive: Value(draft.sensitive),
      itemKind: Value(draft.itemKind.dbValue),
      quantity: Value(draft.quantity),
      unit: Value(_optional(draft.unit)),
      openedDate: Value(_key(draft.openedDate)),
      expiryDate: Value(_key(draft.expiryDate)),
      minimumQuantity: Value(draft.minimumQuantity),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(current.version + 1),
    ));
    return get(id);
  }

  WarrantyState warrantyState(HouseholdItemEntry item, DateTime now) {
    final key = item.warrantyEndDate;
    if (key == null) return WarrantyState.none;
    final end = DateKeys.fromLocalDateKey(key);
    final day = DateTime(now.year, now.month, now.day);
    if (end.isBefore(day)) return WarrantyState.expired;
    if (!end.isAfter(day.add(const Duration(days: 30)))) {
      return WarrantyState.expiringSoon;
    }
    return WarrantyState.active;
  }

  ConsumableState consumableState(HouseholdItemEntry item, DateTime now) =>
      ConsumableRules.state(
        quantity: item.quantity,
        minimumQuantity: item.minimumQuantity,
        expiryDate: item.expiryDate == null
            ? null
            : DateKeys.fromLocalDateKey(item.expiryDate!),
        now: now,
      );

  Future<HouseholdItemEntry> updateQuantity(String id, double quantity) async {
    if (quantity < 0) throw RangeError('库存数量不能为负数');
    final current = await (_database.select(_database.householdItems)
          ..where((row) => row.id.equals(id)))
        .getSingle();
    await (_database.update(_database.householdItems)
          ..where((row) => row.id.equals(id)))
        .write(HouseholdItemsCompanion(
      quantity: Value(quantity),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(current.version + 1),
    ));
    return (_database.select(_database.householdItems)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<ListItemEntry> addToShoppingList(String id) async {
    final item = await (_database.select(_database.householdItems)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (item == null) throw StateError('Household item not found: $id');
    if (item.itemKind != HouseholdItemKind.consumable.dbValue) {
      throw StateError('Only consumables can be added to a shopping list.');
    }

    final lists = ListRepository(_database);
    final activeShoppingLists = await (_database.select(_database.lists)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.archived.equals(false) &
              row.title.equals('购物'))
          ..limit(1))
        .get();
    final list = activeShoppingLists.isEmpty
        ? await lists.createList('购物')
        : activeShoppingLists.single;
    final existing = await (_database.select(_database.listItems)
          ..where((row) =>
              row.listId.equals(list.id) &
              row.deletedAt.isNull() &
              row.checked.equals(false) &
              row.textValue.equals(item.name))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return existing;
    return lists.addItem(list.id, item.name);
  }

  Future<void> archive(String id) => _setStatus(id, 'ARCHIVED');

  Future<void> _setStatus(String id, String status) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.householdItems)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(HouseholdItemsCompanion(
      status: Value(status),
      updatedAt: Value(now),
    ));
  }

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.householdItems)
          ..where((row) => row.id.equals(id)))
        .write(HouseholdItemsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  static void _validate(HouseholdDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name');
    }
    if (draft.purchaseAmountMinor != null && draft.purchaseAmountMinor! < 0) {
      throw ArgumentError.value(
          draft.purchaseAmountMinor, 'purchaseAmountMinor');
    }
    if (draft.purchaseDate != null &&
        draft.warrantyEndDate != null &&
        draft.warrantyEndDate!.isBefore(draft.purchaseDate!)) {
      throw ArgumentError('Warranty cannot end before purchase.');
    }
    ConsumableRules.state(
      quantity: draft.quantity,
      minimumQuantity: draft.minimumQuantity,
      expiryDate: draft.expiryDate,
      now: DateTime.now(),
    );
    if (draft.openedDate != null &&
        draft.expiryDate != null &&
        draft.expiryDate!.isBefore(draft.openedDate!)) {
      throw ArgumentError('Expiry cannot be before opened date.');
    }
  }
}

int? _key(DateTime? value) =>
    value == null ? null : DateKeys.toLocalDateKey(value);
String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
