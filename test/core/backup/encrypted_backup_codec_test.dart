import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/backup/encrypted_backup_codec.dart';

void main() {
  final codec = EncryptedBackupCodec(
    memoryKiB: 1024,
    iterations: 1,
    parallelism: 1,
  );

  test('round trips with the password and randomizes every envelope', () async {
    const json = '{"schemaVersion":7,"private":"心情"}';
    final first = await codec.encrypt(json, 'correct horse battery staple');
    final second = await codec.encrypt(json, 'correct horse battery staple');

    expect(first, isNot(second));
    expect(await codec.decrypt(first, 'correct horse battery staple'), json);
    final root = jsonDecode(first) as Map<String, dynamic>;
    expect(root['format'], 'LifeHubEncryptedBackup');
    expect(root['cipher'], 'AES-256-GCM');
    expect(root['kdf'], 'Argon2id');
  });

  test('rejects wrong passwords, tampering and invalid headers', () async {
    final envelope = await codec.encrypt('{"ok":true}', 'secret-123');
    await expectLater(
      codec.decrypt(envelope, 'wrong-password'),
      throwsA(isA<EncryptedBackupException>()),
    );

    final root = jsonDecode(envelope) as Map<String, dynamic>;
    final bytes = base64Decode(root['ciphertext'] as String);
    bytes[0] ^= 1;
    root['ciphertext'] = base64Encode(bytes);
    await expectLater(
      codec.decrypt(jsonEncode(root), 'secret-123'),
      throwsA(isA<EncryptedBackupException>()),
    );

    root['format'] = 'Unknown';
    await expectLater(
      codec.decrypt(jsonEncode(root), 'secret-123'),
      throwsA(isA<EncryptedBackupException>()),
    );
  });

  test('requires a useful password and valid envelope json', () async {
    await expectLater(codec.encrypt('{}', 'short'), throwsArgumentError);
    await expectLater(
      codec.decrypt('not-json', 'valid-password'),
      throwsA(isA<EncryptedBackupException>()),
    );
  });
}
