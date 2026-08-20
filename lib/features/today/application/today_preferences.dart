import 'package:shared_preferences/shared_preferences.dart';

class TodayPreferences {
  TodayPreferences(this._preferences);

  static const defaultOrder = <String>[
    'focus',
    'goals',
    'tasks',
    'events',
    'courses',
    'habits',
    'anniversaries',
    'trips',
  ];

  static const _orderKey = 'today.module.order';
  static const _collapsedKey = 'today.module.collapsed';
  static const _mottoKey = 'today.motto';

  final SharedPreferences _preferences;

  List<String> loadOrder() {
    final saved = _preferences.getStringList(_orderKey) ?? const [];
    final normalized = <String>[];
    for (final id in saved) {
      if (defaultOrder.contains(id) && !normalized.contains(id)) {
        normalized.add(id);
      }
    }
    normalized.addAll(defaultOrder.where((id) => !normalized.contains(id)));
    return normalized;
  }

  Future<void> saveOrder(List<String> ids) =>
      _preferences.setStringList(_orderKey, _normalize(ids));

  Set<String> loadCollapsed() {
    final saved = _preferences.getStringList(_collapsedKey) ?? const [];
    return saved.where(defaultOrder.contains).toSet();
  }

  Future<void> setCollapsed(String id, bool collapsed) async {
    if (!defaultOrder.contains(id)) return;
    final values = loadCollapsed();
    collapsed ? values.add(id) : values.remove(id);
    await _preferences.setStringList(_collapsedKey, values.toList()..sort());
  }

  String? loadMotto() {
    final value = _preferences.getString(_mottoKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveMotto(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _preferences.remove(_mottoKey);
    } else {
      await _preferences.setString(_mottoKey, normalized);
    }
  }

  List<String> _normalize(List<String> ids) {
    final result = <String>[];
    for (final id in ids) {
      if (defaultOrder.contains(id) && !result.contains(id)) result.add(id);
    }
    result.addAll(defaultOrder.where((id) => !result.contains(id)));
    return result;
  }
}
