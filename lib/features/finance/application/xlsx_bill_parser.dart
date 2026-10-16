import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:lifehub/features/finance/application/bill_csv_parser.dart';
import 'package:lifehub/features/finance/application/finance_preferences.dart';

/// Parses Microsoft Excel (.xlsx) bill exports from WeChat or Alipay.
class XlsxBillParser {
  /// Parses raw .xlsx bytes and returns recognized bill items.
  static List<ParsedBillItem> parseBytes(List<int> bytes,
      {Map<String, UserMerchantRule>? customRules}) {
    if (bytes.isEmpty) return [];

    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // 1. Extract shared strings dictionary (xl/sharedStrings.xml)
      final sharedStrings = <String>[];
      final sharedStringsFile = archive.files.firstWhere(
        (f) => f.name == 'xl/sharedStrings.xml',
        orElse: () => ArchiveFile('', 0, []),
      );
      if (sharedStringsFile.name.isNotEmpty) {
        final content = utf8.decode(sharedStringsFile.content as List<int>, allowMalformed: true);
        final doc = XmlDocument.parse(content);
        for (final si in doc.findAllElements('si')) {
          final textBuffer = StringBuffer();
          for (final t in si.findAllElements('t')) {
            textBuffer.write(t.innerText);
          }
          sharedStrings.add(textBuffer.toString());
        }
      }

      // 2. Locate worksheet (xl/worksheets/sheet1.xml)
      final sheetFile = archive.files.firstWhere(
        (f) => f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'),
        orElse: () => ArchiveFile('', 0, []),
      );
      if (sheetFile.name.isEmpty) return [];

      final sheetXml = utf8.decode(sheetFile.content as List<int>, allowMalformed: true);
      final sheetDoc = XmlDocument.parse(sheetXml);
      final rowsData = <List<String>>[];

      for (final rowElem in sheetDoc.findAllElements('row')) {
        final cellsMap = <int, String>{};
        int maxCol = -1;

        for (final c in rowElem.findElements('c')) {
          final cellRef = c.getAttribute('r') ?? '';
          final colIdx = _colRefToIndex(cellRef);
          if (colIdx > maxCol) maxCol = colIdx;

          final type = c.getAttribute('t');
          String cellVal = '';

          if (type == 's') {
            // Shared string lookup
            final vElem = c.findElements('v').firstOrNull;
            if (vElem != null) {
              final idx = int.tryParse(vElem.innerText.trim());
              if (idx != null && idx >= 0 && idx < sharedStrings.length) {
                cellVal = sharedStrings[idx];
              }
            }
          } else if (type == 'inlineStr') {
            final tElem = c.findAllElements('t').firstOrNull;
            cellVal = tElem?.innerText ?? '';
          } else {
            // Numbers, direct strings, formula results
            final vElem = c.findElements('v').firstOrNull;
            if (vElem != null) {
              cellVal = vElem.innerText.trim();
            } else {
              final tElem = c.findAllElements('t').firstOrNull;
              cellVal = tElem?.innerText.trim() ?? '';
            }
          }

          cellsMap[colIdx] = cellVal;
        }

        if (maxCol >= 0) {
          final rowList = List<String>.filled(maxCol + 1, '');
          cellsMap.forEach((col, val) {
            rowList[col] = val;
          });
          rowsData.add(rowList);
        }
      }

      if (rowsData.isEmpty) return [];

      // 3. Delegate to BillCsvParser using parsed matrix
      return BillCsvParser.parseMatrix(rowsData, customRules: customRules);
    } catch (_) {
      return [];
    }
  }

  /// Converts Excel column letters (A, B, C, ..., AA, AB) to 0-based column index.
  static int _colRefToIndex(String cellRef) {
    int col = 0;
    for (int i = 0; i < cellRef.length; i++) {
      final code = cellRef.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        col = col * 26 + (code - 64);
      } else if (code >= 97 && code <= 122) {
        col = col * 26 + (code - 96);
      } else {
        break; // Hit row digits
      }
    }
    return col > 0 ? col - 1 : 0;
  }
}
