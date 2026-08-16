import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/app/home_screen.dart';
import 'package:lifehub/core/settings/app_settings.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/onboarding/application/onboarding_preferences.dart';
import 'package:lifehub/features/onboarding/presentation/onboarding_page.dart';
import 'package:lifehub/shared/ui/lifehub_theme.dart';

class LifeHubApp extends ConsumerWidget {
  const LifeHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp(
      title: 'LifeHub',
      debugShowCheckedModeBanner: false,
      theme: LifeHubTheme.light(),
      darkTheme: LifeHubTheme.dark(),
      themeMode: settings.themeMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => LifeHubBackground(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _OnboardingGate(),
    );
  }
}

class _OnboardingGate extends ConsumerStatefulWidget {
  const _OnboardingGate();

  @override
  ConsumerState<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<_OnboardingGate> {
  var completedInSession = false;

  @override
  Widget build(BuildContext context) {
    final shared = ref.watch(sharedPreferencesProvider);
    if (shared == null ||
        completedInSession ||
        OnboardingPreferences(shared).isCompleted) {
      return const HomeScreen();
    }
    return OnboardingPage(onFinished: () async {
      await OnboardingPreferences(shared).complete();
      if (mounted) setState(() => completedInSession = true);
    });
  }
}
