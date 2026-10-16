import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MediaPreferences {
  const MediaPreferences(this._preferences);

  static const categoryKey = 'media_last_category';
  static const entryTypeKey = 'media_last_entry_type';

  final SharedPreferences _preferences;

  MediaCategory? loadCategory() =>
      _enumByValue(MediaCategory.values, _preferences.getString(categoryKey));

  MediaEntryType? loadEntryType() => _enumByValue(
        MediaEntryType.values,
        _preferences.getString(entryTypeKey),
      );

  Future<void> saveSelection({
    required MediaCategory category,
    MediaEntryType? entryType,
  }) async {
    await _preferences.setString(categoryKey, category.dbValue);
    if (entryType != null) {
      await _preferences.setString(entryTypeKey, entryType.dbValue);
    }
  }
}

T? _enumByValue<T>(Iterable<T> values, String? saved) {
  if (saved == null) return null;
  for (final value in values) {
    final dbValue = switch (value) {
      MediaCategory item => item.dbValue,
      MediaEntryType item => item.dbValue,
      _ => null,
    };
    if (dbValue == saved) return value;
  }
  return null;
}
