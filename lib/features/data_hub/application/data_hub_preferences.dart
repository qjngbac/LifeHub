import 'package:shared_preferences/shared_preferences.dart';

class DataHubLayout {
  const DataHubLayout({
    required this.order,
    this.pinned = const <String>{},
    this.hidden = const <String>{},
  });

  final List<String> order;
  final Set<String> pinned;
  final Set<String> hidden;

  List<String> get visibleOrder => <String>[
        ...order.where((id) => pinned.contains(id) && !hidden.contains(id)),
        ...order.where((id) => !pinned.contains(id) && !hidden.contains(id)),
      ];

  DataHubLayout copyWith({
    List<String>? order,
    Set<String>? pinned,
    Set<String>? hidden,
  }) =>
      DataHubLayout(
        order: order ?? this.order,
        pinned: pinned ?? this.pinned,
        hidden: hidden ?? this.hidden,
      );
}

class DataHubPreferences {
  DataHubPreferences(this._preferences);

  static const orderKey = 'lifehub.data_hub.order';
  static const pinnedKey = 'lifehub.data_hub.pinned';
  static const hiddenKey = 'lifehub.data_hub.hidden';
  final SharedPreferences _preferences;

  DataHubLayout loadLayout(List<String> available) {
    final availableSet = available.toSet();
    final storedOrder =
        _preferences.getStringList(orderKey) ?? const <String>[];
    final order = <String>[];
    for (final id in storedOrder) {
      if (availableSet.contains(id) && !order.contains(id)) order.add(id);
    }
    for (final id in available) {
      if (!order.contains(id)) order.add(id);
    }

    Set<String> normalized(String key) =>
        (_preferences.getStringList(key) ?? const <String>[])
            .where(availableSet.contains)
            .toSet();

    return DataHubLayout(
      order: order,
      pinned: normalized(pinnedKey),
      hidden: normalized(hiddenKey),
    );
  }

  Future<void> saveLayout(DataHubLayout layout) async {
    await _preferences.setStringList(orderKey, layout.order);
    await _preferences.setStringList(
      pinnedKey,
      layout.order.where(layout.pinned.contains).toList(),
    );
    await _preferences.setStringList(
      hiddenKey,
      layout.order.where(layout.hidden.contains).toList(),
    );
  }

  Future<void> reset() async {
    await _preferences.remove(orderKey);
    await _preferences.remove(pinnedKey);
    await _preferences.remove(hiddenKey);
  }
}
