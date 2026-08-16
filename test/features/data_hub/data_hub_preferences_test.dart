import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/data_hub/application/data_hub_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('normalizes pinned and hidden modules while appending new modules',
      () async {
    SharedPreferences.setMockInitialValues({
      'lifehub.data_hub.order': ['tasks', 'inbox'],
      'lifehub.data_hub.pinned': ['inbox', 'missing'],
      'lifehub.data_hub.hidden': ['courses', 'missing'],
    });
    final preferences = await SharedPreferences.getInstance();
    final store = DataHubPreferences(preferences);

    final layout = store.loadLayout(
      ['inbox', 'tasks', 'courses', 'first_aid'],
    );
    expect(layout.order, ['tasks', 'inbox', 'courses', 'first_aid']);
    expect(layout.pinned, {'inbox'});
    expect(layout.hidden, {'courses'});
    expect(layout.visibleOrder, ['inbox', 'tasks', 'first_aid']);
  });

  test('saves and resets the complete layout', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = DataHubPreferences(preferences);

    await store.saveLayout(
      const DataHubLayout(
        order: ['tasks', 'inbox', 'courses'],
        pinned: {'courses'},
        hidden: {'inbox'},
      ),
    );
    expect(preferences.getStringList('lifehub.data_hub.order'),
        ['tasks', 'inbox', 'courses']);
    expect(preferences.getStringList('lifehub.data_hub.pinned'), ['courses']);
    expect(preferences.getStringList('lifehub.data_hub.hidden'), ['inbox']);

    await store.reset();
    expect(preferences.containsKey('lifehub.data_hub.order'), isFalse);
    expect(preferences.containsKey('lifehub.data_hub.pinned'), isFalse);
    expect(preferences.containsKey('lifehub.data_hub.hidden'), isFalse);
  });
}
