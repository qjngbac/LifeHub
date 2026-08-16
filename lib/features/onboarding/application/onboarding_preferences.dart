import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPreferences {
  OnboardingPreferences(this._preferences);

  static const completedKey = 'lifehub.onboarding.completed';

  final SharedPreferences _preferences;

  bool get isCompleted => _preferences.getBool(completedKey) ?? false;

  Future<void> complete() => _preferences.setBool(completedKey, true);

  Future<void> reset() => _preferences.remove(completedKey);
}
