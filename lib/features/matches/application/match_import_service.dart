import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/matches/application/match_file_codecs.dart';
import 'package:lifehub/features/matches/application/match_ocr_service.dart';
import 'package:lifehub/features/matches/data/match_repository.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/domain/match_rules.dart';
import 'package:lifehub/features/matches/domain/match_text_parser.dart';

class MatchImportService {
  MatchImportService({this._ocrService});

  static const maxImages = 20;
  final MatchOcrService? _ocrService;

  Future<MatchImportPreview> previewOcr(
    List<File> images, {
    required DateTime referenceDate,
    MatchRepository? repository,
    String defaultTimezoneId = 'Asia/Shanghai',
  }) async {
    if (images.isEmpty) return const MatchImportPreview(rows: [], warnings: []);
    if (images.length > maxImages) {
      throw const FormatException('一次最多识别 20 张截图。');
    }
    final ocr = _ocrService;
    if (ocr == null) throw StateError('OCR 服务未配置。');
    final drafts = <MatchDraft>[];
    final warnings = <String>[];
    for (final image in images) {
      try {
        if (await image.length() > MatchFileCodecs.maxImportBytes) {
          warnings.add('${image.path} 超过 5 MB，已跳过。');
          continue;
        }
        final text = await ocr.recognize(image);
        final parsed = MatchTextParser.parse(
          text,
          referenceDate: referenceDate,
          defaultTimezoneId: defaultTimezoneId,
          sourceType: MatchSources.screenshot,
          sourceLabel: '截图识别',
        );
        drafts.addAll(parsed.drafts);
        warnings.addAll(parsed.warnings);
      } on Object catch (error) {
        final message = error is FormatException
            ? error.message
            : '请检查图片是否完整，或裁剪后重试';
        warnings.add('${path.basename(image.path)} 识别失败：$message');
      }
    }
    final preview = _toPreview(drafts, warnings);
    if (repository == null) return preview;
    return _markDuplicates(preview, repository);
  }

  MatchImportPreview previewCsv(
    String source, {
    DateTime? referenceDate,
  }) {
    final drafts =
        MatchFileCodecs.decodeCsv(source, referenceDate: referenceDate);
    return _toPreview(drafts, const []);
  }

  Future<MatchImportPreview> previewCsvWithRepository(
    String source,
    MatchRepository repository, {
    DateTime? referenceDate,
  }) {
    return _markDuplicates(
      previewCsv(source, referenceDate: referenceDate),
      repository,
    );
  }

  MatchImportPreview previewIcs(
    String source, {
    DateTime? referenceDate,
  }) {
    final decoded = MatchFileCodecs.decodeIcsWithWarnings(
      source,
      referenceDate: referenceDate,
    );
    return _toPreview(decoded.drafts, decoded.warnings);
  }

  Future<MatchImportPreview> previewIcsWithRepository(
    String source,
    MatchRepository repository, {
    DateTime? referenceDate,
  }) {
    return _markDuplicates(
      previewIcs(source, referenceDate: referenceDate),
      repository,
    );
  }

  Future<MatchImportPreview> previewDraftsWithRepository(
    List<MatchDraft> drafts,
    List<String> warnings,
    MatchRepository repository,
  ) {
    return _markDuplicates(
      _toPreview(drafts, warnings),
      repository,
    );
  }

  Future<List<MatchRecordEntry>> saveSelectedWithRepository(
    MatchImportPreview preview,
    MatchRepository repository,
  ) async {
    final invalid = preview.rows
        .where((row) => row.selected && row.state == MatchPreviewState.invalid);
    if (invalid.isNotEmpty) {
      throw const FormatException('请先修正导入预览中的错误记录。');
    }
    final selected = preview.rows
        .where((row) => row.selected)
        .map((row) => (draft: row.draft, existingId: row.existingId))
        .toList();
    return repository.importBatch(selected);
  }

  MatchImportPreview _toPreview(
    List<MatchDraft> drafts,
    List<String> warnings,
  ) {
    final rows = <MatchImportPreviewRow>[];
    final seen = <MatchDraft>[];
    for (final draft in drafts.take(MatchFileCodecs.maxImportRows)) {
      final issues = draft
          .validate(now: DateTime.now())
          .where((issue) => issue.severity == MatchIssueSeverity.error)
          .toList(growable: false);
      final valid = issues.isEmpty;
      final duplicate =
          valid && seen.any((other) => MatchRules.areDuplicates(other, draft));
      if (valid) seen.add(draft);
      rows.add(MatchImportPreviewRow(
        draft: draft,
        issues: issues,
        state: !valid
            ? MatchPreviewState.invalid
            : duplicate
                ? MatchPreviewState.duplicate
                : MatchPreviewState.ready,
        possibleDuplicate: duplicate,
        selected: !duplicate,
      ));
    }
    return MatchImportPreview(
      rows: List.unmodifiable(rows),
      warnings: List.unmodifiable(warnings),
    );
  }

  Future<MatchImportPreview> _markDuplicates(
    MatchImportPreview preview,
    MatchRepository repository,
  ) async {
    final rows = <MatchImportPreviewRow>[];
    for (final row in preview.rows) {
      if (row.state == MatchPreviewState.duplicate) {
        rows.add(row);
        continue;
      }
      final duplicates = await repository.findPossibleDuplicates(row.draft);
      if (duplicates.isEmpty) {
        rows.add(row);
        continue;
      }
      final draft = repository.mergeImportDraft(row.draft, duplicates.first);
      final issues = draft
          .validate(now: DateTime.now())
          .where((issue) => issue.severity == MatchIssueSeverity.error)
          .toList(growable: false);
      rows.add(row.copyWith(
        draft: draft,
        issues: issues,
        state: issues.isEmpty
            ? MatchPreviewState.duplicate
            : MatchPreviewState.invalid,
        possibleDuplicate: true,
        existingId: duplicates.first.id,
        selected: false,
      ));
    }
    return MatchImportPreview(
      rows: List.unmodifiable(rows),
      warnings: preview.warnings,
    );
  }
}
