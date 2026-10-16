import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 二级密码（应用内隐私锁）。
///
/// 设计说明（如实，不夸大）：
/// - 只保存 **PBKDF2-HMAC-SHA256 加盐哈希**，不保存明文，也不知道原密码；
///   忘记密码只能清掉这层锁（需重置，私密内容本身不会因此丢失）。
/// - 它是"查看入口"的门禁：本地 SQLite 里的私密正文仍是明文，备份文件也不会
///   被这层密码加密。要做真正的内容加密需要迁移数据格式并处理"忘记密码即丢数据"，
///   影响面大，这里刻意不做，避免引入新问题。
/// - 验证通过后给一个很短的解锁窗口，连续查看几条不会反复要求输入。
class AppLockService {
  AppLockService(this._preferences);

  static const _hashKey = 'app_lock.pin_hash';
  static const _saltKey = 'app_lock.pin_salt';
  static const _iterationsKey = 'app_lock.pin_iterations';
  static const _defaultIterations = 60000;

  /// 密码长度约束：太短等于没设，太长没人记得住。
  static const minLength = 4;
  static const maxLength = 16;

  final SharedPreferences? _preferences;

  Pbkdf2 _kdf(int iterations) => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      );

  /// 是否已经设置过二级密码（同步读取，SharedPreferences 内部有缓存）。
  bool get isConfigured =>
      (_preferences?.getString(_hashKey) ?? '').isNotEmpty;

  /// 仅供测试与诊断：当前存储的哈希（base64）。业务代码不要依赖它做判断。
  @visibleForTesting
  String get storedPinHash => _preferences?.getString(_hashKey) ?? '';

  Future<void> setPin(String pin) async {
    final preferences = _preferences;
    if (preferences == null) return;
    final salt = randomBytes(16);
    await preferences.setInt(_iterationsKey, _defaultIterations);
    await preferences.setString(_saltKey, base64Encode(salt));
    await preferences.setString(
      _hashKey,
      base64Encode(await _hash(pin, salt, _defaultIterations)),
    );
  }

  Future<bool> verify(String pin) async {
    final preferences = _preferences;
    if (preferences == null) return false;
    final stored = preferences.getString(_hashKey);
    final saltBase64 = preferences.getString(_saltKey);
    if (stored == null || stored.isEmpty || saltBase64 == null) return false;
    final iterations =
        preferences.getInt(_iterationsKey) ?? _defaultIterations;
    final hash = await _hash(pin, base64Decode(saltBase64), iterations);
    // 常量时间比较，避免时序侧信道
    return _constantTimeEquals(stored, base64Encode(hash));
  }

  /// 清除二级密码。调用方必须先校验旧密码。
  Future<void> clearPin() async {
    await _preferences?.remove(_hashKey);
    await _preferences?.remove(_saltKey);
    await _preferences?.remove(_iterationsKey);
  }

  Future<List<int>> _hash(String pin, List<int> salt, int iterations) async {
    final key = await _kdf(iterations)
        .deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class AppLockState {
  const AppLockState({
    required this.configured,
    this.unlockedUntil,
  });

  final bool configured;
  final DateTime? unlockedUntil;

  bool get isUnlocked {
    final until = unlockedUntil;
    return until != null && until.isAfter(DateTime.now());
  }
}

class AppLockNotifier extends StateNotifier<AppLockState> {
  AppLockNotifier(this._service)
      : super(AppLockState(configured: _service.isConfigured));

  final AppLockService _service;

  /// 解锁窗口：连续查看几条私密内容不用反复输入，超时自动重新上锁。
  static const unlockWindow = Duration(minutes: 2);

  /// 解锁一段时间；下一次校验通过时刷新窗口。
  void unlock() {
    state = AppLockState(
      configured: state.configured,
      unlockedUntil: DateTime.now().add(unlockWindow),
    );
  }

  /// 立即上锁（设置页"立即锁定"用）。
  void lock() {
    state = AppLockState(configured: state.configured);
  }

  Future<bool> verify(String pin) async {
    final ok = await _service.verify(pin);
    if (ok) {
      unlock();
    }
    return ok;
  }

  Future<void> setPin(String pin) async {
    await _service.setPin(pin);
    state = AppLockState(
      configured: _service.isConfigured,
      unlockedUntil: DateTime.now().add(unlockWindow),
    );
  }

  Future<void> clearPin() async {
    await _service.clearPin();
    state = const AppLockState(configured: false);
  }
}

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(ref.watch(sharedPreferencesProvider));
});

final appLockProvider =
    StateNotifierProvider<AppLockNotifier, AppLockState>((ref) {
  return AppLockNotifier(ref.watch(appLockServiceProvider));
});
