import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as image;
import 'package:lifehub/features/matches/application/match_ocr_service.dart';

class _Recognizer extends TextRecognizer {
  _Recognizer({this.result, this.results});
  final RecognizedText? result;
  final List<RecognizedText>? results;
  int calls = 0;
  String? inputPath;
  (int, int)? dimensions;
  final allDimensions = <(int, int)>[];
  @override
  Future<RecognizedText> processImage(InputImage inputImage) async {
    calls++;
    inputPath = inputImage.filePath;
    final decoded = image.decodeImage(await File(inputPath!).readAsBytes())!;
    dimensions = (decoded.width, decoded.height);
    allDimensions.add(dimensions!);
    return results?[calls - 1] ??
        result ??
        RecognizedText(text: 'recognised', blocks: []);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('lifehub-ocr-'),
  );
  tearDown(() => directory.delete(recursive: true));

  test('long screenshots are recognized in readable vertical pieces', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          ),
    );
    final file = await File(
      '${directory.path}/long-readable.png',
    ).writeAsBytes(image.encodePng(image.Image(width: 120, height: 5200)));
    final recognizer = _Recognizer();
    await MlKitMatchOcrService(recognizer: recognizer).recognize(file);
    expect(recognizer.calls, greaterThan(1));
    expect(
      recognizer.allDimensions.every(
        (size) => size.$1 == 120 && size.$2 <= 2400,
      ),
      isTrue,
    );
    expect(await file.exists(), isTrue);
  });

  test('cross-tile merged rows replace both old opponent columns', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          ),
    );
    TextLine line(String text, Rect box) => TextLine(
      text: text,
      boundingBox: box,
      elements: [],
      recognizedLanguages: [],
      cornerPoints: [],
      confidence: 0.99,
      angle: 0,
    );
    RecognizedText recognized(List<TextLine> lines) => RecognizedText(
      text: '',
      blocks: [
        TextBlock(
          text: '',
          lines: lines,
          boundingBox: Rect.zero,
          recognizedLanguages: [],
          cornerPoints: [],
        ),
      ],
    );
    final file = await File(
      '${directory.path}/merged-columns.png',
    ).writeAsBytes(image.encodePng(image.Image(width: 800, height: 2600)));
    final recognizer = _Recognizer(
      results: [
        recognized([
          line('广州足球俱乐部', const Rect.fromLTWH(10, 2340, 200, 60)),
          line('上海申花', const Rect.fromLTWH(400, 2340, 200, 60)),
        ]),
        recognized([
          line('广州足球俱乐部 vs 上海申花', const Rect.fromLTWH(10, 140, 590, 80)),
        ]),
      ],
    );
    expect(
      await MlKitMatchOcrService(recognizer: recognizer).recognize(file),
      '广州足球俱乐部 vs 上海申花',
    );
    final fallback = _Recognizer(
      results: [
        RecognizedText(text: '2026-10-12\n20:00', blocks: []),
        recognized([
          line('广州足球俱乐部 vs 上海申花', const Rect.fromLTWH(10, 250, 590, 80)),
        ]),
      ],
    );
    expect(
      await MlKitMatchOcrService(recognizer: fallback).recognize(file),
      '2026-10-12\n20:00\n广州足球俱乐部 vs 上海申花',
    );
  });

  test(
    'OCR line coordinates restore rows and separate opponent columns',
    () async {
      TextLine line(String text, double left, double top, double width) =>
          TextLine(
            text: text,
            elements: [],
            boundingBox: Rect.fromLTWH(left, top, width, 20),
            recognizedLanguages: [],
            cornerPoints: [],
            confidence: 0.99,
            angle: 0,
          );
      final result = RecognizedText(
        text: 'B队\nA队\n2026-10-12\n20:00',
        blocks: [
          TextBlock(
            text: '',
            lines: [
              line('B队', 250, 80, 60),
              line('A队', 10, 80, 60),
              line('20:00', 10, 40, 60),
              line('2026-10-12', 10, 10, 120),
            ],
            boundingBox: const Rect.fromLTWH(0, 0, 400, 120),
            recognizedLanguages: [],
            cornerPoints: [],
          ),
        ],
      );
      final file = await File(
        '${directory.path}/columns.png',
      ).writeAsBytes(image.encodePng(image.Image(width: 400, height: 120)));
      final text = await MlKitMatchOcrService(
        recognizer: _Recognizer(result: result),
      ).recognize(file);
      expect(text, '2026-10-12\n20:00\nA队\tB队');
    },
  );

  test('a row crossing a tile boundary is kept intact exactly once', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          ),
    );
    RecognizedText recognized(String text, double top, double height) =>
        RecognizedText(
          text: text,
          blocks: [
            TextBlock(
              text: text,
              lines: [
                TextLine(
                  text: text,
                  elements: [],
                  boundingBox: Rect.fromLTWH(10, top, 500, height),
                  recognizedLanguages: [],
                  cornerPoints: [],
                  confidence: 0.99,
                  angle: 0,
                ),
              ],
              boundingBox: Rect.fromLTWH(10, top, 500, height),
              recognizedLanguages: [],
              cornerPoints: [],
            ),
          ],
        );
    final file = await File(
      '${directory.path}/boundary.png',
    ).writeAsBytes(image.encodePng(image.Image(width: 800, height: 2600)));
    final recognizer = _Recognizer(
      results: [
        recognized('被截断的队名', 2340, 60),
        recognized('广州足球俱乐部 vs 上海申花', 140, 80),
      ],
    );
    final text = await MlKitMatchOcrService(
      recognizer: recognizer,
    ).recognize(file);
    // The second tile starts at 2200: y=2340..2420 is wholly inside it.
    expect(recognizer.allDimensions, [(800, 2400), (800, 400)]);
    expect(text, '广州足球俱乐部 vs 上海申花');
    final recoverable = _Recognizer(
      results: [
        RecognizedText(text: '', blocks: []),
        recognized('只在邻片识别到的完整行', 50, 80),
      ],
    );
    expect(
      await MlKitMatchOcrService(recognizer: recoverable).recognize(file),
      '只在邻片识别到的完整行',
    );
    expect(await file.exists(), isTrue);
  });

  test(
    'OCR rejects oversized raster dimensions before decoding pixel data',
    () async {
      // A BMP header with no pixel payload must be rejected for its dimensions,
      // rather than allocating the declared raster and failing during decoding.
      final bytes = Uint8List(54);
      final header = ByteData.sublistView(bytes);
      bytes[0] = 0x42;
      bytes[1] = 0x4d;
      header.setUint32(2, 54, Endian.little);
      header.setUint32(10, 54, Endian.little);
      header.setUint32(14, 40, Endian.little);
      header.setInt32(18, 6000, Endian.little);
      header.setInt32(22, 6000, Endian.little);
      header.setUint16(26, 1, Endian.little);
      header.setUint16(28, 24, Endian.little);
      final file = await File(
        '${directory.path}/large.bmp',
      ).writeAsBytes(bytes);
      final recognizer = _Recognizer();
      await expectLater(
        MlKitMatchOcrService(recognizer: recognizer).recognize(file),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'reason',
            contains('像素'),
          ),
        ),
      );
      expect(recognizer.calls, 0);
    },
  );

  test(
    'OCR reports unreadable image without calling the native recognizer',
    () async {
      final file = await File(
        '${directory.path}/broken.png',
      ).writeAsBytes([1, 2, 3]);
      final recognizer = _Recognizer();
      await expectLater(
        MlKitMatchOcrService(recognizer: recognizer).recognize(file),
        throwsFormatException,
      );
      expect(recognizer.calls, 0);
    },
  );

  test(
    'OCR keeps a normal screenshot intact and returns recognized text',
    () async {
      final file = await File(
        '${directory.path}/normal.png',
      ).writeAsBytes(image.encodePng(image.Image(width: 20, height: 12)));
      final recognizer = _Recognizer();
      final result = await MlKitMatchOcrService(
        recognizer: recognizer,
      ).recognize(file);
      expect(result, 'recognised');
      expect(recognizer.inputPath, file.path);
      expect(recognizer.dimensions, (20, 12));
    },
  );
  test(
    'OCR preprocessing resizes long screenshots without zero-width output',
    () async {
      final file = await File(
        '${directory.path}/long.png',
      ).writeAsBytes(image.encodePng(image.Image(width: 1, height: 3000)));
      final bytes = prepareMatchScreenshot(file.path)!;
      final result = image.decodeJpg(bytes)!;
      expect((result.width, result.height), (1, 2400));
      expect(await file.exists(), isTrue);
    },
  );
}
