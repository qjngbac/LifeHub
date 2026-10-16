import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/media/application/media_preferences.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('new media remembers the last category and entry type', () async {
    final store = MediaPreferences(await SharedPreferences.getInstance());

    expect(store.loadCategory(), isNull);
    expect(store.loadEntryType(), isNull);

    await store.saveSelection(
      category: MediaCategory.anime,
      entryType: MediaEntryType.ova,
    );

    final reopened = MediaPreferences(await SharedPreferences.getInstance());
    expect(reopened.loadCategory(), MediaCategory.anime);
    expect(reopened.loadEntryType(), MediaEntryType.ova);
  });

  test('invalid saved media defaults are ignored', () async {
    SharedPreferences.setMockInitialValues({
      MediaPreferences.categoryKey: 'BROKEN',
      MediaPreferences.entryTypeKey: 'BROKEN',
    });
    final store = MediaPreferences(await SharedPreferences.getInstance());

    expect(store.loadCategory(), isNull);
    expect(store.loadEntryType(), isNull);
  });
}
