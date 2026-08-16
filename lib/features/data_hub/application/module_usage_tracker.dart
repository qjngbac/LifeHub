import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ModuleUsageTracker {
  ModuleUsageTracker(this._preferences);

  static const storageKey = 'lifehub.data_hub.module_usage';
  static const observationPeriod = Duration(days: 30);
  static const lowFrequencyOpenLimit = 2;

  final SharedPreferences _preferences;

  Future<void> observeModules(Iterable<String> ids, {DateTime? now}) async {
    final values = _read();
    final timestamp = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    var changed = false;
    for (final id in ids.toSet()) {
      if (!values.containsKey(id)) {
        values[id] = _Usage(firstObservedAt: timestamp);
        changed = true;
      }
    }
    if (changed) await _write(values);
  }

  Future<void> recordOpen(String id, {DateTime? now}) async {
    final values = _read();
    final timestamp = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final previous = values[id] ?? _Usage(firstObservedAt: timestamp);
    values[id] = _Usage(
      firstObservedAt: previous.firstObservedAt,
      openCount: previous.openCount + 1,
      lastOpenedAt: timestamp,
    );
    await _write(values);
  }

  Set<String> lowFrequencySuggestions(
    Iterable<String> available, {
    Set<String> pinned = const <String>{},
    DateTime? now,
  }) {
    final values = _read();
    final current = (now ?? DateTime.now()).toUtc();
    final result = <String>{};
    for (final id in available) {
      final usage = values[id];
      if (usage == null || pinned.contains(id)) continue;
      final observedAt = DateTime.fromMillisecondsSinceEpoch(
        usage.firstObservedAt,
        isUtc: true,
      );
      if (current.difference(observedAt) >= observationPeriod &&
          usage.openCount < lowFrequencyOpenLimit) {
        result.add(id);
      }
    }
    return result;
  }

  Future<void> reset() => _preferences.remove(storageKey);

  Map<String, _Usage> _read() {
    final encoded = _preferences.getString(storageKey);
    if (encoded == null) return {};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: _Usage.fromJson(entry.value as Map<String, dynamic>),
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> _write(Map<String, _Usage> values) => _preferences.setString(
        storageKey,
        jsonEncode(
            {for (final entry in values.entries) entry.key: entry.value}),
      );
}

class _Usage {
  const _Usage({
    required this.firstObservedAt,
    this.openCount = 0,
    this.lastOpenedAt,
  });

  factory _Usage.fromJson(Map<String, dynamic> json) => _Usage(
        firstObservedAt: (json['firstObservedAt'] as num?)?.toInt() ?? 0,
        openCount: (json['openCount'] as num?)?.toInt() ?? 0,
        lastOpenedAt: (json['lastOpenedAt'] as num?)?.toInt(),
      );

  final int firstObservedAt;
  final int openCount;
  final int? lastOpenedAt;

  Map<String, Object?> toJson() => {
        'firstObservedAt': firstObservedAt,
        'openCount': openCount,
        'lastOpenedAt': lastOpenedAt,
      };
}
