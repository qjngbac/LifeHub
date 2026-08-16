import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/onboarding/application/onboarding_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('onboarding is incomplete until explicitly finished', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = OnboardingPreferences(
      await SharedPreferences.getInstance(),
    );

    expect(preferences.isCompleted, isFalse);
    await preferences.complete();
    expect(preferences.isCompleted, isTrue);
    await preferences.reset();
    expect(preferences.isCompleted, isFalse);
  });
}
