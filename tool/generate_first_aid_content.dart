import 'dart:convert';
import 'dart:io';

import 'first_aid_supplements.dart';

const _output = r'assets\content\first_aid\knowledge.json';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    throw ArgumentError(
      'Usage: dart run tool/generate_first_aid_content.dart '
      '<source-markdown> [output-json]',
    );
  }
  final source = File(arguments.first);
  if (!source.existsSync()) {
    throw StateError('Source not found: ${source.path}');
  }
  final document = parseFirstAidMarkdown(source.readAsStringSync());
  validateFirstAidDocument(document, expectedScenes: 19, expectedItems: 227);
  (document['items'] as List).addAll(firstAidSupplements);
  document['version'] = 2;
  document['reviewedAt'] = '2026-08-13';
  validateFirstAidDocument(document, expectedScenes: 19);
  final output = File(arguments.length > 1 ? arguments[1] : _output);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(document),
  );
  stdout.writeln(
    'Generated ${document['scenes'].length} scenes and '
    '${document['items'].length} items at ${output.path}',
  );
}

Map<String, dynamic> parseFirstAidMarkdown(String source) {
  final lines = const LineSplitter().convert(source);
  final scenes = <Map<String, dynamic>>[];
  final items = <Map<String, dynamic>>[];
  Map<String, dynamic>? scene;
  Map<String, dynamic>? item;

  void finishItem() {
    if (item == null) return;
    items.add(item!);
    item = null;
  }

  for (final raw in lines) {
    final line = raw.trim().replaceAll(RegExp(r'\s{2}$'), '');
    final sceneMatch = RegExp(r'^# (?:0\.|\d{1,2})\s+(.+)$').firstMatch(line);
    if (sceneMatch != null) {
      finishItem();
      final index = scenes.length;
      scene = {
        'id': 'scene_${index.toString().padLeft(2, '0')}',
        'name': sceneMatch.group(1)!,
        'subEnvironments': '',
        'rank': index,
        'color': _sceneColors[index % _sceneColors.length],
        'icon': _sceneIcons[index % _sceneIcons.length],
      };
      scenes.add(scene);
      continue;
    }
    if (line.startsWith('**子环境：**') && scene != null) {
      scene['subEnvironments'] = _field(line, '子环境');
      continue;
    }
    final question = RegExp(r'^### Q(\d+)：(.*)$').firstMatch(line);
    if (question != null) {
      finishItem();
      if (scene == null) throw const FormatException('Question before scene');
      item = {
        'id': 'q${question.group(1)}',
        'number': int.parse(question.group(1)!),
        'sceneId': scene['id'],
        'question': question.group(2)!.trim(),
      };
      continue;
    }
    if (item == null) continue;
    for (final field in const {
      '答案': 'answer',
      '操作步骤': 'steps',
      '少工具方案': 'fallback',
      '低工具方案': 'fallback',
      '禁忌': 'prohibitions',
      '紧急等级': 'risk',
    }.entries) {
      if (line.startsWith('**${field.key}：**')) {
        var value = _field(line, field.key);
        if (field.value == 'risk') {
          value = value.contains('紧急')
              ? 'EMERGENCY'
              : value.contains('高风险')
                  ? 'HIGH'
                  : 'ROUTINE';
        }
        item![field.value] = value;
      }
    }
  }
  finishItem();
  return {
    'version': 1,
    'reviewedAt': '2026-08-11',
    'notice': '仅供离线应急参考，不能替代急救培训、医疗诊断或当地救援指挥。先保证现场安全；危及生命时立即联系当地急救或救援。',
    'sources': const [
      {
        'title': 'American Red Cross First Aid Steps',
        'url':
            'https://www.redcross.org/take-a-class/first-aid/performing-first-aid/first-aid-steps'
      },
      {
        'title': 'CDC Rabies Prevention',
        'url': 'https://www.cdc.gov/rabies/prevention/index.html'
      },
      {
        'title': 'CDC Carbon Monoxide Poisoning Basics',
        'url': 'https://www.cdc.gov/carbon-monoxide/about/index.html'
      },
      {
        'title': 'National Weather Service Lightning Safety',
        'url': 'https://www.weather.gov/safety/lightning-safety'
      },
      {
        'title': 'National Park Service Wilderness Safety',
        'url': 'https://www.nps.gov/olym/planyourvisit/wilderness-safety.htm'
      },
    ],
    'scenes': scenes,
    'items': items,
  };
}

void validateFirstAidDocument(
  Map<String, dynamic> document, {
  int? expectedScenes,
  int? expectedItems,
}) {
  final scenes = document['scenes'] as List;
  final items = document['items'] as List;
  if (expectedScenes != null && scenes.length != expectedScenes) {
    throw StateError('Expected $expectedScenes scenes, got ${scenes.length}');
  }
  if (expectedItems != null && items.length != expectedItems) {
    throw StateError('Expected $expectedItems items, got ${items.length}');
  }
  final ids = <String>{};
  for (final raw in items) {
    final item = raw as Map<String, dynamic>;
    if (!ids.add(item['id'] as String)) throw StateError('Duplicate item id');
    for (final field in const [
      'question',
      'answer',
      'steps',
      'fallback',
      'prohibitions',
      'risk',
    ]) {
      if ((item[field] as String?)?.trim().isEmpty != false) {
        throw StateError('${item['id']} missing $field');
      }
    }
    if (!const {'EMERGENCY', 'HIGH', 'ROUTINE'}.contains(item['risk'])) {
      throw StateError('${item['id']} has invalid risk');
    }
  }
}

String _field(String line, String name) =>
    line.replaceFirst('**$name：**', '').replaceAll(RegExp(r'\s+$'), '').trim();

const _sceneColors = [
  '#F2D7E1',
  '#DCE8FA',
  '#DDF0E8',
  '#F5E5C8',
  '#DFDCF4',
  '#D9E8EF',
  '#D7E9D0',
  '#D9EFE0',
  '#E8E2C6',
  '#F0DFC8',
  '#E6D7C5',
  '#DCE9F3',
  '#D5EAF1',
  '#D4E6EE',
  '#D9EAF4',
  '#D5E8ED',
  '#E4DFD7',
  '#DCE9D9',
  '#F0D6D6',
];

const _sceneIcons = [
  'medical_services',
  'apartment',
  'park',
  'agriculture',
  'landscape',
  'terrain',
  'forest',
  'eco',
  'grass',
  'wb_sunny',
  'travel_explore',
  'ac_unit',
  'water',
  'waves',
  'beach_access',
  'sailing',
  'cave',
  'water_drop',
  'warning',
];
