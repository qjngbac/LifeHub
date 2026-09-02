import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('privacy mode is persisted in app settings', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
    ]);
    addTearDown(container.dispose);

    expect(container.read(appSettingsProvider).privacyMode, isFalse);
    await container.read(appSettingsProvider.notifier).setPrivacyMode(true);

    expect(container.read(appSettingsProvider).privacyMode, isTrue);
    expect(preferences.getBool(AppSettings.privacyModeKey), isTrue);
  });
}
