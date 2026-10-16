import 'package:lifehub/features/medication/data/medication_repository.dart';

class UserMedicationAlert {
  const UserMedicationAlert({
    required this.userDrugName,
    required this.drugCategory,
    required this.foodTarget,
    required this.riskDescription,
    this.isDanger = true,
  });

  final String userDrugName;
  final String drugCategory;
  final String foodTarget;
  final String riskDescription;
  final bool isDanger;
}

class MedicationFoodInteractionService {
  const MedicationFoodInteractionService({
    this.activeMedicationNames = const <String>[],
  });

  final List<String> activeMedicationNames;

  static Future<MedicationFoodInteractionService> fromRepository(
    MedicationRepository? repo,
  ) async {
    if (repo == null) {
      return const MedicationFoodInteractionService();
    }
    try {
      final plans = await repo.plans(activeOnly: true);
      final names = plans.map((p) => p.name.trim()).where((n) => n.isNotEmpty).toList();
      return MedicationFoodInteractionService(activeMedicationNames: names);
    } catch (_) {
      return const MedicationFoodInteractionService();
    }
  }

  UserMedicationAlert? checkFoodAlert(String foodName, List<String> tags) {
    if (activeMedicationNames.isEmpty) return null;

    final fName = foodName.toLowerCase();
    final tagStr = tags.join(' ').toLowerCase();

    for (final med in activeMedicationNames) {
      final m = med.toLowerCase();

      // 1. 他汀类降脂药 (Statins)
      if (m.contains('他汀') || m.contains('statin') || m.contains('立普妥') || m.contains('可定')) {
        if (fName.contains('西柚') || fName.contains('葡萄柚') || fName.contains('蜜柚') || tagStr.contains('西柚')) {
          return UserMedicationAlert(
            userDrugName: med,
            drugCategory: '他汀类降脂药',
            foodTarget: '西柚/葡萄柚',
            riskDescription: '西柚富含呋喃香豆素，强烈抑制肝脏CYP3A4代谢酶，会导致他汀血药浓度骤升数十倍，引发横纹肌溶解或急性肝肾衰竭，严禁食用！',
            isDanger: true,
          );
        }
      }

      // 2. 华法林抗凝药 (Warfarin)
      if (m.contains('华法林') || m.contains('抗凝')) {
        if (fName.contains('菠菜') ||
            fName.contains('苋菜') ||
            fName.contains('空心菜') ||
            fName.contains('油菜') ||
            fName.contains('西兰花') ||
            fName.contains('西蓝花') ||
            tagStr.contains('维k')) {
          return UserMedicationAlert(
            userDrugName: med,
            drugCategory: '华法林（抗凝药）',
            foodTarget: foodName,
            riskDescription: '此类深绿叶蔬菜富含极高维生素K，会显著拮抗华法林抗凝效果导致凝血指标波动及血栓风险，服药期间应保持每日摄入量恒定，切忌突然大量进食！',
            isDanger: true,
          );
        }
      }

      // 3. 降压/保钾类药物 (ACEI/ARB/螺内酯/保钾利尿剂)
      if (m.contains('沙坦') ||
          m.contains('普利') ||
          m.contains('螺内酯') ||
          m.contains('降压') ||
          m.contains('氯沙坦') ||
          m.contains('缬沙坦') ||
          m.contains('厄贝沙坦')) {
        if (fName.contains('香蕉') ||
            fName.contains('菠菜') ||
            fName.contains('土豆') ||
            fName.contains('低钠盐') ||
            tagStr.contains('高钾')) {
          return UserMedicationAlert(
            userDrugName: med,
            drugCategory: '降压/保钾类药物',
            foodTarget: foodName,
            riskDescription: '此类食物富含极高钾元素，合用易导致体内钾蓄积引发高钾血症，严重时可致心律失常甚至心跳骤停，请遵医嘱严格控量！',
            isDanger: false,
          );
        }
      }

      // 4. 左甲状腺素片 (优甲乐)
      if (m.contains('甲状腺') || m.contains('优甲乐') || m.contains('雷替斯')) {
        if (fName.contains('豆浆') || fName.contains('豆腐') || fName.contains('大豆') || tagStr.contains('高钙')) {
          return UserMedicationAlert(
            userDrugName: med,
            drugCategory: '左甲状腺素片',
            foodTarget: foodName,
            riskDescription: '大豆异黄酮及高钙食物会严重阻碍药物在胃肠道的结合与吸收，服药与进食豆制品或钙剂需至少间隔 4 小时以上！',
            isDanger: false,
          );
        }
      }

      // 5. 铁剂 (琥珀酸亚铁/硫酸亚铁)
      if (m.contains('铁') || m.contains('力蜚能')) {
        if (fName.contains('柿子') || fName.contains('山楂') || fName.contains('茶') || tagStr.contains('鞣酸')) {
          return UserMedicationAlert(
            userDrugName: med,
            drugCategory: '补铁制剂',
            foodTarget: foodName,
            riskDescription: '含鞣酸、多酚及咖啡因的食物会与铁结合生成不溶性沉淀，极大地抑制人体铁吸收，服药期间请间隔 2 小时以上食用！',
            isDanger: false,
          );
        }
      }
    }

    return null;
  }
}
