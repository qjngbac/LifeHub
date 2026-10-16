import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifehub/features/finance/application/finance_preferences.dart';
import 'package:lifehub/features/finance/application/bill_csv_parser.dart';
import 'package:lifehub/features/finance/domain/finance_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FinancePreferences Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('stores and retrieves monthly budget correctly', () async {
      final prefs = await SharedPreferences.getInstance();
      final financePrefs = FinancePreferences(prefs);

      // Default when not set
      final defaultBudget = financePrefs.getMonthlyBudget(2026, 9);
      expect(defaultBudget, isNull);

      // Set budget
      await financePrefs.setMonthlyBudget(2026, 9, 300000); // ¥3000.00
      final retrieved = financePrefs.getMonthlyBudget(2026, 9);
      expect(retrieved, 300000);

      // Clear budget (set null)
      await financePrefs.setMonthlyBudget(2026, 9, null);
      expect(financePrefs.getMonthlyBudget(2026, 9), isNull);
    });

    test('saves, retrieves, and removes merchant learning rules', () async {
      final prefs = await SharedPreferences.getInstance();
      final financePrefs = FinancePreferences(prefs);

      // Empty rules initially
      final initialRules = financePrefs.getMerchantRules();
      expect(initialRules, isEmpty);

      // Save custom rule
      await financePrefs.saveMerchantRule(
        '罗森便利店',
        category: 'FOOD',
        subCategory: '零食饮料',
        expenseNature: 'WANT',
      );

      final rulesAfterSave = financePrefs.getMerchantRules();
      expect(rulesAfterSave.length, 1);
      final rule = rulesAfterSave['罗森便利店']!;
      expect(rule.category, 'FOOD');
      expect(rule.subCategory, '零食饮料');
      expect(rule.expenseNature, 'WANT');

      // Save another rule
      await financePrefs.saveMerchantRule(
        'Steam Games',
        category: 'ENTERTAINMENT',
        subCategory: '游戏娱乐',
        expenseNature: 'WANT',
      );

      final rulesAfterSecond = financePrefs.getMerchantRules();
      expect(rulesAfterSecond.length, 2);

      // Remove first rule
      await financePrefs.removeMerchantRule('罗森便利店');
      final rulesAfterRemove = financePrefs.getMerchantRules();
      expect(rulesAfterRemove.length, 1);
      expect(rulesAfterRemove.containsKey('罗森便利店'), isFalse);
      expect(rulesAfterRemove.containsKey('Steam Games'), isTrue);
    });

    test('custom merchant rules override default inference logic', () {
      final customRules = {
        '美团外卖': const UserMerchantRule(
          counterparty: '美团外卖',
          category: 'CUSTOM_CAT',
          subCategory: '专属外卖',
          expenseNature: 'WANT',
        ),
      };

      // Infer without custom rules (default would infer 外卖午餐 at 12:00)
      final defaultInferred = FinanceCategoryInferer.infer(
        direction: FinanceDirection.expense,
        counterparty: '美团外卖',
        description: '黄焖鸡米饭',
        rawType: '商户消费',
        transactionTime: DateTime(2026, 9, 18, 12, 0),
      );
      expect(defaultInferred.category, 'FOOD');
      expect(defaultInferred.subCategory, '外卖午餐');

      // Infer with custom rules
      final customInferred = FinanceCategoryInferer.infer(
        direction: FinanceDirection.expense,
        counterparty: '美团外卖',
        description: '黄焖鸡米饭',
        rawType: '商户消费',
        transactionTime: DateTime(2026, 9, 18, 12, 0),
        customRules: customRules,
      );
      expect(customInferred.category, 'CUSTOM_CAT');
      expect(customInferred.subCategory, '专属外卖');
      expect(customInferred.expenseNature, ExpenseNature.want);
    });

    test('BillCsvParser.parse applies custom merchant rules', () {
      const wechatCsv = '''
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-09-18 12:00:00,商户消费,某某科技公司,软件订阅,支出,¥99.00,微信支付,支付成功,45000000000001,M001,/
''';

      final customRules = {
        '某某科技公司': const UserMerchantRule(
          counterparty: '某某科技公司',
          category: 'WORK',
          subCategory: '开发工具',
          expenseNature: 'NEED',
        ),
      };

      final items = BillCsvParser.parse(wechatCsv, customRules: customRules);
      expect(items.length, 1);
      expect(items[0].category, 'WORK');
      expect(items[0].subCategory, '开发工具');
      expect(items[0].expenseNature, ExpenseNature.need);
    });
  });
}
