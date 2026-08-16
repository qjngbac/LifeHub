import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';

class CredentialDraft {
  const CredentialDraft({
    required this.name,
    this.credentialType = 'OTHER',
    this.holder,
    this.numberHint,
    this.issuedDate,
    this.expiryDate,
    this.reminderDays = 30,
    this.notes,
    this.sensitive = true,
  });

  final String name;
  final String credentialType;
  final String? holder;
  final String? numberHint;
  final DateTime? issuedDate;
  final DateTime? expiryDate;
  final int reminderDays;
  final String? notes;
  final bool sensitive;
}

class CredentialRepository {
  CredentialRepository(this._database);
  final AppDatabase _database;

  Future<CredentialRecordEntry> create(CredentialDraft draft) {
    _validate(draft);
    return _database.into(_database.credentialRecords).insertReturning(
          CredentialRecordsCompanion.insert(
            name: draft.name.trim(),
            credentialType: Value(draft.credentialType),
            holder: Value(_optional(draft.holder)),
            numberHint: Value(_optional(draft.numberHint)),
            issuedDate: Value(_key(draft.issuedDate)),
            expiryDate: Value(_key(draft.expiryDate)),
            reminderDays: Value(draft.reminderDays),
            notes: Value(_optional(draft.notes)),
            sensitive: Value(draft.sensitive),
          ),
        );
  }

  Future<List<CredentialRecordEntry>> list({bool includeArchived = false}) {
    final query = _database.select(_database.credentialRecords)
      ..where((row) {
        var expression = row.deletedAt.isNull();
        if (!includeArchived) {
          expression = expression & row.status.equals('ARCHIVED').not();
        }
        return expression;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.expiryDate)]);
    return query.get();
  }

  Future<CredentialRecordEntry> get(String id) async {
    final row = await (_database.select(_database.credentialRecords)
          ..where((item) => item.id.equals(id) & item.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) throw StateError('Credential not found: $id');
    return row;
  }

  Future<CredentialRecordEntry> update(
    String id,
    CredentialDraft draft,
  ) async {
    _validate(draft);
    final current = await get(id);
    await (_database.update(_database.credentialRecords)
          ..where((row) => row.id.equals(id)))
        .write(CredentialRecordsCompanion(
      name: Value(draft.name.trim()),
      credentialType: Value(draft.credentialType),
      holder: Value(_optional(draft.holder)),
      numberHint: Value(_optional(draft.numberHint)),
      issuedDate: Value(_key(draft.issuedDate)),
      expiryDate: Value(_key(draft.expiryDate)),
      reminderDays: Value(draft.reminderDays),
      notes: Value(_optional(draft.notes)),
      sensitive: Value(draft.sensitive),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(current.version + 1),
    ));
    return get(id);
  }

  DateTime? reminderDate(CredentialRecordEntry record) {
    if (record.expiryDate == null || record.reminderDays < 0) return null;
    return DateKeys.fromLocalDateKey(record.expiryDate!)
        .subtract(Duration(days: record.reminderDays));
  }

  Future<void> archive(String id) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.credentialRecords)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(CredentialRecordsCompanion(
      status: const Value('ARCHIVED'),
      updatedAt: Value(now),
    ));
  }

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.credentialRecords)
          ..where((row) => row.id.equals(id)))
        .write(CredentialRecordsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  static void _validate(CredentialDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name');
    }
    if (draft.reminderDays < -1) {
      throw ArgumentError.value(draft.reminderDays, 'reminderDays');
    }
    if (draft.issuedDate != null &&
        draft.expiryDate != null &&
        draft.expiryDate!.isBefore(draft.issuedDate!)) {
      throw ArgumentError('Expiry cannot precede issue date.');
    }
  }
}

int? _key(DateTime? value) =>
    value == null ? null : DateKeys.toLocalDateKey(value);
String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
