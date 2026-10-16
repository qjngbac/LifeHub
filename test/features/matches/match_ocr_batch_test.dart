import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/matches/application/match_import_service.dart';
import 'package:lifehub/features/matches/application/match_ocr_service.dart';

class _Ocr implements MatchOcrService {
  @override
  Future<String> recognize(File file) async {
    if (file.path.endsWith('bad.png')) throw const FormatException('无法读取截图');
    return '英超\n2099-10-12\n20:00 阿森纳 vs 切尔西';
  }
}

void main() {
  test(
    'one unreadable screenshot does not discard the other preview rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lifehub-ocr-batch-',
      );
      addTearDown(() async {
        expect(
          directory.absolute.path.startsWith(
            Directory.systemTemp.absolute.path,
          ),
          isTrue,
        );
        await directory.delete(recursive: true);
      });
      final good = await File(
        '${directory.path}/good.png',
      ).writeAsString('fixture');
      final bad = await File(
        '${directory.path}/bad.png',
      ).writeAsString('fixture');
      final preview = await MatchImportService(
        ocrService: _Ocr(),
      ).previewOcr([bad, good], referenceDate: DateTime(2026, 10, 11));
      expect(preview.rows, hasLength(1));
      expect(preview.rows.single.draft.participantA, '阿森纳');
      expect(preview.warnings, contains(contains('bad.png')));
    },
  );
}
