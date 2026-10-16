import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

abstract interface class MatchOcrService {
  Future<String> recognize(File imageFile);
}

class MlKitMatchOcrService implements MatchOcrService {
  MlKitMatchOcrService({TextRecognizer? recognizer})
    : _recognizer =
          recognizer ?? TextRecognizer(script: TextRecognitionScript.chinese);

  static const maxImageDimension = 2400;
  static const maxDecodedPixels = 32 * 1024 * 1024;

  final TextRecognizer _recognizer;

  @override
  Future<String> recognize(File imageFile) async {
    final parts = await compute(prepareMatchScreenshotParts, imageFile.path);
    final directory = parts.isEmpty ? null : await getTemporaryDirectory();
    final lines = <_OcrLine>[];
    final fallbackText = <int, String>{};
    for (var index = 0; index < (parts.isEmpty ? 1 : parts.length); index++) {
      File? temporaryFile;
      try {
        var inputFile = imageFile;
        if (parts.isNotEmpty) {
          temporaryFile = File(
            path.join(
              directory!.path,
              'lifehub_match_${DateTime.now().microsecondsSinceEpoch}_$index.jpg',
            ),
          );
          await temporaryFile.writeAsBytes(parts[index].bytes, flush: true);
          inputFile = temporaryFile;
        }
        final result = await _recognizer.processImage(
          InputImage.fromFilePath(inputFile.path),
        );
        final part = parts.isEmpty ? null : parts[index];
        final nativeLines = result.blocks
            .expand((block) => block.lines)
            .where(
              (line) =>
                  line.text.trim().isNotEmpty && line.boundingBox.height > 0,
            )
            .toList();
        if (nativeLines.isEmpty && result.text.trim().isNotEmpty) {
          fallbackText[index] = result.text;
        }
        for (final line in nativeLines) {
          final positioned = _OcrLine(
            line.text.trim(),
            line.boundingBox.shift(Offset(0, (part?.top ?? 0).toDouble())),
            index,
            part != null &&
                (line.boundingBox.top <= 2 ||
                    line.boundingBox.bottom >= part.height - 2),
          );
          // Retain a complete result from either tile if its neighbour missed it.
          final duplicates = lines
              .where(
                (existing) =>
                    existing.part != index && existing.overlaps(positioned),
              )
              .toList();
          if (duplicates.isEmpty) {
            lines.add(positioned);
          } else {
            final best = duplicates.reduce(
              (a, b) =>
                  (a.atEdge && !b.atEdge) ||
                      (a.atEdge == b.atEdge && b.text.length > a.text.length)
                  ? b
                  : a,
            );
            if ((best.atEdge && !positioned.atEdge) ||
                (best.atEdge == positioned.atEdge &&
                    positioned.text.length > best.text.length)) {
              lines.removeWhere(duplicates.contains);
              lines.add(positioned);
            }
          }
        }
      } finally {
        if (temporaryFile != null && await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      }
    }
    if (fallbackText.isEmpty) return _recognizedRows(lines);
    return [
      for (var index = 0; index < (parts.isEmpty ? 1 : parts.length); index++)
        fallbackText[index] ??
            _recognizedRows(lines.where((line) => line.part == index).toList()),
    ].where((text) => text.isNotEmpty).join('\n');
  }

  Future<void> dispose() => _recognizer.close();
}

Uint8List? prepareMatchScreenshot(String filePath) {
  return _resizeScreenshot(_decodeScreenshot(filePath));
}

List<({Uint8List bytes, int top, int height})> prepareMatchScreenshotParts(
  String filePath,
) {
  var decoded = _decodeScreenshot(filePath);
  if (decoded.height > MlKitMatchOcrService.maxImageDimension &&
      decoded.height >= decoded.width * 3) {
    if (decoded.width > MlKitMatchOcrService.maxImageDimension) {
      decoded = image.copyResize(
        decoded,
        width: MlKitMatchOcrService.maxImageDimension,
      );
    }
    final parts = <({Uint8List bytes, int top, int height})>[];
    // Keep complete text on either side of a seam, even in large phone fonts.
    final overlapPixels = math.max(192, math.min(480, decoded.width ~/ 4));
    for (
      var top = 0;
      top < decoded.height;
      top += MlKitMatchOcrService.maxImageDimension - overlapPixels
    ) {
      final height = math.min(
        MlKitMatchOcrService.maxImageDimension,
        decoded.height - top,
      );
      parts.add((
        bytes: image.encodeJpg(
          image.copyCrop(
            decoded,
            x: 0,
            y: top,
            width: decoded.width,
            height: height,
          ),
          quality: 88,
        ),
        top: top,
        height: height,
      ));
      if (top + height == decoded.height) break;
    }
    return parts;
  }
  final resized = _resizeScreenshot(decoded);
  return resized == null
      ? []
      : [
          (
            bytes: resized,
            top: 0,
            height: math.max(
              1,
              (decoded.height *
                      MlKitMatchOcrService.maxImageDimension /
                      math.max(decoded.width, decoded.height))
                  .round(),
            ),
          ),
        ];
}

image.Image _decodeScreenshot(String filePath) {
  try {
    final bytes = File(filePath).readAsBytesSync();
    final decoder = image.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) {
      throw const FormatException('无法读取截图。');
    }
    if (info.width * info.height > MlKitMatchOcrService.maxDecodedPixels) {
      throw const FormatException('图片像素过大，请裁剪后再识别。');
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) throw const FormatException('无法读取截图。');
    return decoded;
  } on FormatException {
    rethrow;
  } on image.ImageException {
    throw const FormatException('无法读取截图。');
  } on RangeError {
    throw const FormatException('无法读取截图。');
  }
}

Uint8List? _resizeScreenshot(image.Image decoded) {
  if (decoded.width <= MlKitMatchOcrService.maxImageDimension &&
      decoded.height <= MlKitMatchOcrService.maxImageDimension) {
    return null;
  }
  final scale =
      MlKitMatchOcrService.maxImageDimension /
      math.max(decoded.width, decoded.height);
  return image.encodeJpg(
    image.copyResize(
      decoded,
      width: math.max(1, (decoded.width * scale).round()),
      height: math.max(1, (decoded.height * scale).round()),
    ),
    quality: 88,
  );
}

class _OcrLine {
  const _OcrLine(this.text, this.boundingBox, this.part, this.atEdge);
  final String text;
  final Rect boundingBox;
  final int part;
  final bool atEdge;

  bool overlaps(_OcrLine other) {
    final intersection = boundingBox.intersect(other.boundingBox);
    return intersection.height >
            math.min(boundingBox.height, other.boundingBox.height) * 0.5 &&
        intersection.width >
            math.min(boundingBox.width, other.boundingBox.width) * 0.5;
  }
}

String _recognizedRows(List<_OcrLine> lines) {
  lines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
  final rows = <List<_OcrLine>>[];
  for (final line in lines) {
    final sameRow = rows
        .where(
          (row) =>
              (row.first.boundingBox.center.dy - line.boundingBox.center.dy)
                  .abs() <=
              math.min(row.first.boundingBox.height, line.boundingBox.height) *
                  0.6,
        )
        .firstOrNull;
    if (sameRow == null) {
      rows.add([line]);
    } else {
      sameRow.add(line);
    }
  }
  rows.sort(
    (a, b) => a.first.boundingBox.top.compareTo(b.first.boundingBox.top),
  );
  return rows
      .map((row) {
        row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
        return row.map((line) => line.text.trim()).join('\t');
      })
      .join('\n');
}
