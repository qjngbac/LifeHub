import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

abstract final class LocationType {
  static const place = 'PLACE';
  static const home = 'HOME';
  static const school = 'SCHOOL';
  static const work = 'WORK';
  static const scenic = 'SCENIC';
  static const restaurant = 'RESTAURANT';
  static const transport = 'TRANSPORT';
  static const values = {
    place,
    home,
    school,
    work,
    scenic,
    restaurant,
    transport
  };
}

class LocationDraft {
  const LocationDraft({
    required this.name,
    this.locationType = LocationType.place,
    this.address,
    this.latitude,
    this.longitude,
    this.notes,
  });
  final String name;
  final String locationType;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? notes;
}

class LocationRepository {
  LocationRepository(this._database);
  final AppDatabase _database;

  Future<LocationEntry> create(LocationDraft draft) async {
    _validate(draft);
    final id = const Uuid().v4();
    await _database.into(_database.locations).insert(LocationsCompanion.insert(
          id: Value(id),
          name: draft.name.trim(),
          locationType: Value(draft.locationType),
          address: Value(_optional(draft.address)),
          latitude: Value(draft.latitude),
          longitude: Value(draft.longitude),
          notes: Value(_optional(draft.notes)),
        ));
    return get(id);
  }

  Future<LocationEntry> get(String id) async {
    final value = await (_database.select(_database.locations)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (value == null) throw StateError('Location not found: $id');
    return value;
  }

  Future<List<LocationEntry>> list({bool archived = false}) =>
      (_database.select(_database.locations)
            ..where((row) =>
                row.deletedAt.isNull() &
                row.status.equals(archived ? 'ARCHIVED' : 'ACTIVE'))
            ..orderBy([(row) => OrderingTerm(expression: row.name)]))
          .get();

  Future<List<LocationEntry>> search(String query) {
    final value = query.trim();
    if (value.isEmpty) return list();
    final pattern = '%$value%';
    return (_database.select(_database.locations)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ACTIVE') &
              (row.name.like(pattern) |
                  row.address.like(pattern) |
                  row.notes.like(pattern))))
        .get();
  }

  Future<void> archive(String id) => _setStatus(id, 'ARCHIVED');
  Future<void> restore(String id) => _setStatus(id, 'ACTIVE');

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.locations)
          ..where((row) => row.id.equals(id)))
        .write(LocationsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  Future<void> _setStatus(String id, String status) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.locations)
          ..where((row) => row.id.equals(id)))
        .write(LocationsCompanion(
      status: Value(status),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  static void _validate(LocationDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name');
    }
    if (!LocationType.values.contains(draft.locationType)) {
      throw ArgumentError.value(draft.locationType, 'locationType');
    }
    if ((draft.latitude == null) != (draft.longitude == null)) {
      throw ArgumentError('Latitude and longitude must be supplied together.');
    }
    if (draft.latitude != null &&
        (draft.latitude! < -90 || draft.latitude! > 90)) {
      throw ArgumentError.value(draft.latitude, 'latitude');
    }
    if (draft.longitude != null &&
        (draft.longitude! < -180 || draft.longitude! > 180)) {
      throw ArgumentError.value(draft.longitude, 'longitude');
    }
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
