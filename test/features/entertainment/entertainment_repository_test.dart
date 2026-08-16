import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/entertainment/data/entertainment_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads main library plus curated supplement', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = EntertainmentRepository(
      bundle: rootBundle,
      preferences: await SharedPreferences.getInstance(),
    );
    final library = await repository.load();
    expect(library.items.length, greaterThanOrEqualTo(440));
    expect(library.categories.length, greaterThanOrEqualTo(20));
  });

  test('favorite, block and defer-last states are persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = EntertainmentRepository(
      bundle: rootBundle,
      preferences: await SharedPreferences.getInstance(),
    );
    final library = await repository.load();
    final first = library.items.first;
    final second = library.items[1];
    expect(await repository.toggleFavorite(first.id), isTrue);
    expect((await repository.favorites()), contains(first.id));
    await repository.toggleBlocked(first.id);
    expect(await repository.visibleItems(), isNot(contains(first)));
    await repository.toggleDeferred(second.id);
    expect((await repository.visibleItems()).last.id, second.id);
  });

  test('random sequence contains each eligible item once', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = EntertainmentRepository(
      bundle: rootBundle,
      preferences: await SharedPreferences.getInstance(),
    );
    final sequence = await repository.randomSequence(group: 'joke');
    expect(sequence, isNotEmpty);
    expect(sequence.every((item) => item.group == 'joke'), isTrue);
    expect(sequence.map((item) => item.id).toSet(), hasLength(sequence.length));
  });
}
