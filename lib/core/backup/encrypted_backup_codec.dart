import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';

class EncryptedBackupException implements Exception {
  const EncryptedBackupException(this.message);

  final String message;

  @override
  String toString() => 'EncryptedBackupException: $message';
}

class EncryptedBackupCodec {
  EncryptedBackupCodec({
    this.memoryKiB = 64 * 1024,
    this.iterations = 2,
    this.parallelism = 2,
  });

  static const format = 'LifeHubEncryptedBackup';
  static const version = 1;
  static final _aad = utf8.encode('$format:$version');

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Future<String> encrypt(String clearJson, String password) async {
    if (password.length < 8) {
      throw ArgumentError.value(password, 'password', '至少需要 8 个字符');
    }
    _validateKdf(memoryKiB, iterations, parallelism);
    final salt = randomBytes(16);
    final algorithm = Argon2id(
      memory: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: 32,
    );
    final key = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final cipher = AesGcm.with256bits();
    final secretBox = await cipher.encrypt(
      utf8.encode(clearJson),
      secretKey: key,
      aad: _aad,
    );
    return jsonEncode({
      'format': format,
      'version': version,
      'kdf': 'Argon2id',
      'memoryKiB': memoryKiB,
      'iterations': iterations,
      'parallelism': parallelism,
      'salt': base64Encode(salt),
      'cipher': 'AES-256-GCM',
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  Future<String> decrypt(String envelope, String password) async {
    try {
      final root = jsonDecode(envelope);
      if (root is! Map<String, dynamic> ||
          root['format'] != format ||
          root['version'] != version ||
          root['kdf'] != 'Argon2id' ||
          root['cipher'] != 'AES-256-GCM') {
        throw const EncryptedBackupException('不是受支持的 LifeHub 加密备份');
      }
      final memory = (root['memoryKiB'] as num).toInt();
      final rounds = (root['iterations'] as num).toInt();
      final lanes = (root['parallelism'] as num).toInt();
      _validateKdf(memory, rounds, lanes);
      final salt = base64Decode(root['salt'] as String);
      if (salt.length != 16) {
        throw const EncryptedBackupException('加密备份盐值无效');
      }
      final key = await Argon2id(
        memory: memory,
        iterations: rounds,
        parallelism: lanes,
        hashLength: 32,
      ).deriveKeyFromPassword(password: password, nonce: salt);
      final secretBox = SecretBox(
        base64Decode(root['ciphertext'] as String),
        nonce: base64Decode(root['nonce'] as String),
        mac: Mac(base64Decode(root['mac'] as String)),
      );
      final clearBytes = await AesGcm.with256bits().decrypt(
        secretBox,
        secretKey: key,
        aad: _aad,
      );
      return utf8.decode(clearBytes);
    } on EncryptedBackupException {
      rethrow;
    } catch (_) {
      throw const EncryptedBackupException('密码错误、文件损坏或内容被篡改');
    }
  }

  static bool looksEncrypted(String value) {
    try {
      final root = jsonDecode(value);
      return root is Map<String, dynamic> && root['format'] == format;
    } catch (_) {
      return false;
    }
  }

  static void _validateKdf(int memory, int rounds, int lanes) {
    if (memory < 1024 ||
        memory > 256 * 1024 ||
        rounds < 1 ||
        rounds > 10 ||
        lanes < 1 ||
        lanes > 8) {
      throw const EncryptedBackupException('加密备份的密码派生参数无效');
    }
  }
}
