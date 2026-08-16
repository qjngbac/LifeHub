import 'dart:convert';
import 'dart:io';

const _output = r'assets\content\entertainment\content.json';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    throw ArgumentError(
      'Usage: dart run tool/generate_entertainment_content.dart '
      '<source-markdown> [output-json]',
    );
  }
  final sourcePath = arguments.first;
  final main = parseEntertainmentMarkdown(
    File(sourcePath).readAsStringSync(),
    source: 'main',
  );
  if (main.length != 746) {
    throw StateError('Main library must contain 746 items, got ${main.length}');
  }
  final all = main;
  for (var index = 0; index < all.length; index++) {
    all[index]['id'] = 'ent_${(index + 1).toString().padLeft(4, '0')}';
  }
  final categories = <String, Map<String, dynamic>>{};
  for (final item in all) {
    final id = item['categoryId'] as String;
    categories.putIfAbsent(
      id,
      () => {
        'id': id,
        'name': item['category'] as String,
        'group': item['group'] as String,
      },
    );
  }
  if (categories.length != 32) {
    throw StateError(
      'Main library must contain 32 categories, got ${categories.length}',
    );
  }
  final output = File(arguments.length > 1 ? arguments[1] : _output)
    ..parent.createSync(recursive: true);
  output.writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'version': 1,
    'selection': '单一主内容库：32 个分类、746 条精选离线内容',
    'categories': categories.values.toList(),
    'items': all,
  }));
  stdout.writeln(
    'Generated ${all.length} items from the main document, '
    '${categories.length} categories.',
  );
}

List<Map<String, dynamic>> parseEntertainmentMarkdown(
  String markdown, {
  required String source,
}) {
  final result = <Map<String, dynamic>>[];
  var group = '';
  var category = '';
  String? title;
  final body = <String>[];

  void finish() {
    if (title == null || category.isEmpty || group.isEmpty) return;
    final content = body.join('\n').trim();
    if (content.isNotEmpty) {
      final type = category.contains('脑筋急转弯')
          ? 'riddle'
          : group == 'joke'
              ? 'joke'
              : 'story';
      result.add({
        'id': '',
        'categoryId': _slug(category),
        'category': category,
        'group': group,
        'contentType': type,
        'title': title,
        'body': content.replaceAll(RegExp(r'^\*\*答案：\*\*\s*'), '答案：'),
        'estimatedReadSeconds':
            (content.replaceAll(RegExp(r'\s'), '').length / 5)
                .ceil()
                .clamp(8, 600),
        'source': source,
      });
    }
    title = null;
    body.clear();
  }

  for (final raw in const LineSplitter().convert(markdown)) {
    final line = raw.trim();
    if (line.startsWith('# 😂')) {
      finish();
      group = 'joke';
      continue;
    }
    if (line.startsWith('# 📖') || line.startsWith('# 🌙')) {
      finish();
      group = line.startsWith('# 🌙') ? 'atmosphere' : 'story';
      continue;
    }
    final categoryMatch = RegExp(r'^## ([^（]+)(?:（.*）)?$').firstMatch(line);
    if (categoryMatch != null && group.isNotEmpty) {
      finish();
      category = categoryMatch.group(1)!.trim();
      continue;
    }
    final itemMatch = RegExp(r'^### \d+\.\s*(.+)$').firstMatch(line);
    if (itemMatch != null && category.isNotEmpty && group.isNotEmpty) {
      finish();
      title = itemMatch.group(1)!.trim();
      continue;
    }
    if (title != null && line.isNotEmpty && line != '---') body.add(line);
  }
  finish();
  return result;
}

String _slug(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '').toLowerCase();
