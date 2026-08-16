import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';

enum ParcelStatus {
  inTransit('IN_TRANSIT'),
  ready('READY'),
  collected('COLLECTED'),
  returned('RETURNED'),
  archived('ARCHIVED');

  const ParcelStatus(this.dbValue);
  final String dbValue;
}

class ParcelDraft {
  const ParcelDraft({
    required this.title,
    this.carrier,
    this.trackingNumber,
    this.pickupCode,
    this.status = ParcelStatus.inTransit,
    this.expectedAt,
    this.arrivedAt,
    this.pickupDeadline,
    this.locationId,
    this.notes,
    this.sensitive = true,
  });

  final String title;
  final String? carrier;
  final String? trackingNumber;
  final String? pickupCode;
  final ParcelStatus status;
  final DateTime? expectedAt;
  final DateTime? arrivedAt;
  final DateTime? pickupDeadline;
  final String? locationId;
  final String? notes;
  final bool sensitive;
}

class ParcelRepository {
  ParcelRepository(this._database);
  final AppDatabase _database;

  Future<ParcelEntry> create(ParcelDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(draft.title, 'title');
    if (draft.arrivedAt != null &&
        draft.pickupDeadline != null &&
        draft.pickupDeadline!.isBefore(draft.arrivedAt!)) {
      throw ArgumentError('Pickup deadline cannot be before arrival.');
    }
    return _database.into(_database.parcels).insertReturning(
          ParcelsCompanion.insert(
            title: title,
            carrier: Value(_optional(draft.carrier)),
            trackingNumber: Value(_optional(draft.trackingNumber)),
            pickupCode: Value(_optional(draft.pickupCode)),
            status: Value(draft.status.dbValue),
            expectedAt: Value(draft.expectedAt?.millisecondsSinceEpoch),
            arrivedAt: Value(draft.arrivedAt?.millisecondsSinceEpoch),
            pickupDeadline: Value(draft.pickupDeadline?.millisecondsSinceEpoch),
            locationId: Value(draft.locationId),
            notes: Value(_optional(draft.notes)),
            sensitive: Value(draft.sensitive),
          ),
        );
  }

  Future<ParcelEntry> get(String id) async {
    final row = await (_database.select(_database.parcels)
          ..where((item) => item.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw StateError('Parcel not found: $id');
    return row;
  }

  Future<List<ParcelEntry>> list({bool includeArchived = false}) =>
      (_database.select(_database.parcels)
            ..where((row) {
              var result = row.deletedAt.isNull();
              if (!includeArchived) {
                result = result & row.status.equals('ARCHIVED').not();
              }
              return result;
            })
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .get();

  Future<ParcelEntry> update(String id, ParcelDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(draft.title, 'title');
    if (draft.arrivedAt != null &&
        draft.pickupDeadline != null &&
        draft.pickupDeadline!.isBefore(draft.arrivedAt!)) {
      throw ArgumentError('Pickup deadline cannot be before arrival.');
    }
    final current = await get(id);
    await (_database.update(_database.parcels)
          ..where((item) => item.id.equals(id)))
        .write(ParcelsCompanion(
      title: Value(title),
      carrier: Value(_optional(draft.carrier)),
      trackingNumber: Value(_optional(draft.trackingNumber)),
      pickupCode: Value(_optional(draft.pickupCode)),
      status: Value(draft.status.dbValue),
      expectedAt: Value(draft.expectedAt?.millisecondsSinceEpoch),
      arrivedAt: Value(draft.arrivedAt?.millisecondsSinceEpoch),
      pickupDeadline: Value(draft.pickupDeadline?.millisecondsSinceEpoch),
      locationId: Value(draft.locationId),
      notes: Value(_optional(draft.notes)),
      sensitive: Value(draft.sensitive),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(current.version + 1),
    ));
    return get(id);
  }

  Future<ParcelEntry> advance(String id, {DateTime? at}) async {
    final row = await get(id);
    final current = ParcelStatus.values.firstWhere(
      (value) => value.dbValue == row.status,
      orElse: () => ParcelStatus.inTransit,
    );
    final next = switch (current) {
      ParcelStatus.inTransit => ParcelStatus.ready,
      ParcelStatus.ready => ParcelStatus.collected,
      _ => current,
    };
    return _setStatus(id, next, at: at);
  }

  Future<List<ParcelEntry>> pendingPickup() => (_database
          .select(_database.parcels)
        ..where((row) => row.deletedAt.isNull() & row.status.equals('READY'))
        ..orderBy([(row) => OrderingTerm.asc(row.pickupDeadline)]))
      .get();

  Future<List<ParcelEntry>> search(String query) {
    final value = query.trim();
    if (value.isEmpty) return list();
    final pattern = '%${value.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    return (_database.select(_database.parcels)
          ..where((row) =>
              row.deletedAt.isNull() &
              (row.title.like(pattern) |
                  row.carrier.like(pattern) |
                  row.trackingNumber.like(pattern) |
                  row.pickupCode.like(pattern)))
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .get();
  }

  Future<ParcelEntry> markCollected(String id, {DateTime? at}) =>
      _setStatus(id, ParcelStatus.collected, at: at);

  Future<ParcelEntry> archive(String id) =>
      _setStatus(id, ParcelStatus.archived);

  Future<void> delete(String id) async {
    final row = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.parcels)
          ..where((item) => item.id.equals(id)))
        .write(ParcelsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(row.version + 1),
    ));
  }

  Future<ParcelEntry> _setStatus(String id, ParcelStatus status,
      {DateTime? at}) async {
    final row = await get(id);
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    await (_database.update(_database.parcels)
          ..where((item) => item.id.equals(id)))
        .write(ParcelsCompanion(
      status: Value(status.dbValue),
      updatedAt: Value(now),
      version: Value(row.version + 1),
    ));
    return get(id);
  }
}

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
