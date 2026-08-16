import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/first_aid/data/first_aid_repository.dart';
import 'package:lifehub/features/first_aid/domain/first_aid_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads a varied expanded 19-scene offline knowledge base', () async {
    final repository = FirstAidRepository(bundle: rootBundle);
    final knowledge = await repository.load();
    expect(knowledge.scenes, hasLength(19));
    expect(knowledge.items.length, greaterThan(227));
    expect(knowledge.items.every((item) => item.question.isNotEmpty), isTrue);
    expect(knowledge.scenes.map((scene) => scene.id).toSet(), hasLength(19));
    expect(
      knowledge.scenes
          .take(10)
          .map((scene) =>
              knowledge.items.where((item) => item.sceneId == scene.id).length)
          .every((count) => count > 0),
      isTrue,
    );
    expect(knowledge.scenes.take(10).map((scene) => scene.icon).toSet().length,
        greaterThan(5));
    final counts = {
      for (final scene in knowledge.scenes)
        scene.id:
            knowledge.items.where((item) => item.sceneId == scene.id).length,
    };
    for (final sceneId in const [
      'scene_02',
      'scene_03',
      'scene_04',
      'scene_05',
      'scene_06',
      'scene_08',
      'scene_10',
      'scene_13',
      'scene_16',
      'scene_17',
    ]) {
      expect(counts[sceneId], greaterThanOrEqualTo(13), reason: sceneId);
    }
    expect(
      const [
        'scene_02',
        'scene_03',
        'scene_04',
        'scene_05',
        'scene_06',
        'scene_08',
        'scene_10',
        'scene_13',
        'scene_16',
        'scene_17',
      ].map((id) => counts[id]).toSet().length,
      greaterThan(1),
    );
  });

  test('search includes risk and few-tool content', () async {
    final repository = FirstAidRepository(bundle: rootBundle);
    final results = await repository.search('止血');
    expect(results, isNotEmpty);
    expect(results.any((item) => item.risk == FirstAidRisk.emergency), isTrue);
  });
}
