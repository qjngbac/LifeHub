import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/location/data/location_repository.dart';

void main() {
  late AppDatabase database;
  late LocationRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocationRepository(database);
  });
  tearDown(() => database.close());

  test('stores manually supplied place coordinates and searches it', () async {
    await repository.create(const LocationDraft(
      name: '西湖断桥',
      locationType: LocationType.scenic,
      address: '杭州市西湖区',
      latitude: 30.259,
      longitude: 120.149,
    ));
    expect((await repository.search('西湖')).single.locationType,
        LocationType.scenic);
  });

  test('validates coordinate bounds without requesting location permission',
      () {
    expect(
      () => repository.create(const LocationDraft(
        name: '无效位置',
        latitude: 95,
        longitude: 120,
      )),
      throwsA(isA<ArgumentError>()),
    );
  });
}
