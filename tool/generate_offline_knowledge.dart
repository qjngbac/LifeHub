import 'dart:convert';
import 'dart:io';

void main() {
  final project = Directory.current.path;
  _generate(
    source: File(
      '$project${Platform.pathSeparator}..${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}LifeHub_日用品选购_431种常见日用品知识库_扩展版.md',
    ),
    output: File(
      '$project${Platform.pathSeparator}assets${Platform.pathSeparator}content'
      '${Platform.pathSeparator}consumer_guide${Platform.pathSeparator}catalog.json',
    ),
    marker: '# 三、431种常见日用品',
    idPrefix: 'goods',
    itemFields: const ['name', 'buyingTip', 'standards', 'misconception'],
  );
  _generate(
    source: File(
      '$project${Platform.pathSeparator}..${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}LifeHub_药品信息_728种常见药品知识库_扩展版.md',
    ),
    output: File(
      '$project${Platform.pathSeparator}assets${Platform.pathSeparator}content'
      '${Platform.pathSeparator}drug_info${Platform.pathSeparator}catalog.json',
    ),
    marker: '# 三、728种常见药品候选',
    idPrefix: 'drug',
    itemFields: const ['name', 'useTags', 'riskSummary'],
  );
}

void _generate({
  required File source,
  required File output,
  required String marker,
  required String idPrefix,
  required List<String> itemFields,
}) {
  final lines = source.readAsLinesSync();
  var inData = false;
  String? category;
  final categories = <String, Map<String, Object>>{};
  final items = <Map<String, Object>>[];
  for (final line in lines) {
    if (line.trim() == marker) {
      inData = true;
      continue;
    }
    if (!inData) continue;
    if (line.startsWith('# ') && line.trim() != marker) break;
    if (line.startsWith('## ')) {
      category = line.substring(3).replaceFirst(RegExp(r'（\d+种）$'), '').trim();
      categories.putIfAbsent(category, () {
        final index = categories.length + 1;
        return {
          'id': '$idPrefix-category-${index.toString().padLeft(2, '0')}',
          'name': category!,
          'count': 0,
        };
      });
      continue;
    }
    if (category == null || !RegExp(r'^\|\s*\d+\s*\|').hasMatch(line)) {
      continue;
    }
    final columns = line
        .split('|')
        .skip(1)
        .takeWhile((value) => value != line.split('|').last)
        .map((value) => value.trim())
        .toList();
    if (columns.length != itemFields.length + 1) {
      throw FormatException('Unexpected table row: $line');
    }
    final number = int.parse(columns.first);
    final categoryData = categories[category]!;
    categoryData['count'] = (categoryData['count']! as int) + 1;
    final item = <String, Object>{
      'id': '$idPrefix-${number.toString().padLeft(3, '0')}',
      'number': number,
      'categoryId': categoryData['id']!,
      'category': category,
    };
    for (var index = 0; index < itemFields.length; index++) {
      item[itemFields[index]] = columns[index + 1];
    }
    items.add(item);
  }
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'source': source.uri.pathSegments.last,
    'generatedAt': '2026-08-14',
    'categories': categories.values.toList(),
    'items': items,
  }));
  stdout.writeln('${output.path}: ${categories.length} categories, '
      '${items.length} items');
}
