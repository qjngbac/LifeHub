import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';

enum LifeMode { student, work, daily, outdoor }

extension LifeModeLabel on LifeMode {
  String get label => switch (this) {
        LifeMode.student => '学生',
        LifeMode.work => '工作',
        LifeMode.daily => '日常',
        LifeMode.outdoor => '户外',
      };
}

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.modes = const {LifeMode.daily},
  });
  final ThemeMode themeMode;
  final Set<LifeMode> modes;

  AppSettings copyWith({ThemeMode? themeMode, Set<LifeMode>? modes}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        modes: modes ?? this.modes,
      );
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier(this.ref) : super(_load(ref));
  final Ref ref;

  static AppSettings _load(Ref ref) {
    final preferences = ref.read(sharedPreferencesProvider);
    final themeName = preferences?.getString('theme_mode');
    final theme =
        ThemeMode.values.where((value) => value.name == themeName).firstOrNull;
    final savedModes = preferences?.getStringList('life_modes');
    final modes = savedModes
        ?.map((name) =>
            LifeMode.values.where((value) => value.name == name).firstOrNull)
        .whereType<LifeMode>()
        .toSet();
    return AppSettings(
      themeMode: theme ?? ThemeMode.system,
      modes: modes == null || modes.isEmpty ? {LifeMode.daily} : modes,
    );
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await ref
        .read(sharedPreferencesProvider)
        ?.setString('theme_mode', mode.name);
  }

  Future<void> toggleMode(LifeMode mode, bool enabled) async {
    final modes = {...state.modes};
    if (enabled) {
      modes.add(mode);
    } else if (modes.length > 1) {
      modes.remove(mode);
    }
    state = state.copyWith(modes: modes);
    await ref.read(sharedPreferencesProvider)?.setStringList(
        'life_modes', modes.map((value) => value.name).toList());
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>(
  (ref) => AppSettingsNotifier(ref),
);
