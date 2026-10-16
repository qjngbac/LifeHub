import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/finance/application/bill_csv_parser.dart';
import 'package:lifehub/features/finance/application/pdf_bill_parser.dart';
import 'package:lifehub/features/finance/domain/finance_models.dart';

void main() {
  const samplePdfPath =
      r'd:\appDate\xwechat_files\wxid_1sqa6hldufdr22_e47c\msg\file\2026-10\招商银行交易流水(申请时间2026年10月07日15时17分45秒).pdf';

  group('PdfBillParser unit tests', () {
    test('identifies PDF signature', () {
      expect(PdfBillParser.isPdf([0x25, 0x50, 0x44, 0x46]), isTrue);
      expect(PdfBillParser.isPdf([0x50, 0x4B, 0x03, 0x04]), isFalse);
      expect(PdfBillParser.isPdf([]), isFalse);
    });

    test('parses CMB text and treats 李小辉 as transfer', () {
      const mockText = '''
招商银行交易流水
Transaction Statement of China Merchants Bank
户  名：
李小辉
账号：5342********1612
记账日期 货币 交易金额 联机余额 交易摘要 对手信息
2026-07-03
CNY
102.00
102.00
网联收款
李小辉
2026-07-03
CNY
-100.00
1.98
享定存开户起息
李小辉
2026-07-20
CNY
-15.18
470.82
快捷支付
上海拉扎斯信息科技有限公司
2026-07-20
CNY
0.85
471.67
一网通支付鼓励金
其它应收款-零售客户移动支付
2026-07-23
CNY
-50.00
394.47
快捷支付
昆明理工大学
2026-09-21
CNY
0.03
109.81
账户结息
应付利息
''';

      final items = PdfBillParser.parseText(mockText);
      expect(items.length, 6);

      // 1. 李小辉收款 -> TRANSFER
      final item1 = items[0];
      expect(item1.direction, FinanceDirection.transfer);
      expect(item1.category, 'TRANSFER');
      expect(item1.amountMinor, 10200);
      expect(item1.counterparty, '李小辉');
      expect(item1.subCategory, '账户转入');

      // 2. 李小辉享定存 -> TRANSFER
      final item2 = items[1];
      expect(item2.direction, FinanceDirection.transfer);
      expect(item2.category, 'TRANSFER');
      expect(item2.amountMinor, 10000);
      expect(item2.counterparty, '李小辉');
      expect(item2.subCategory, '定存理财');

      // 3. 拉扎斯 -> 支出 / 餐饮
      final item3 = items[2];
      expect(item3.direction, FinanceDirection.expense);
      expect(item3.category, 'FOOD');
      expect(item3.amountMinor, 1518);
      expect(item3.counterparty, '上海拉扎斯信息科技有限公司');

      // 4. 鼓励金 -> 收入
      final item4 = items[3];
      expect(item4.direction, FinanceDirection.income);
      expect(item4.category, 'SIDE_INCOME');
      expect(item4.amountMinor, 85);

      // 5. 昆明理工大学 -> 支出 / 教育
      final item5 = items[4];
      expect(item5.direction, FinanceDirection.expense);
      expect(item5.category, 'EDUCATION');
      expect(item5.amountMinor, 5000);

      // 6. 账户结息 -> 收入 / 理财利息
      final item6 = items[5];
      expect(item6.direction, FinanceDirection.income);
      expect(item6.category, 'INVESTMENT_INCOME');
      expect(item6.amountMinor, 3);
    });

    final realPdfFile = File(samplePdfPath);
    if (realPdfFile.existsSync()) {
      test('parses real 招商银行交易流水 PDF accurately', () async {
        final bytes = await realPdfFile.readAsBytes();
        final items = BillCsvParser.parseBytes(bytes, fileName: realPdfFile.path);

        expect(items.isNotEmpty, isTrue);
        expect(items.length, 31);

        // Verify that all items where counterparty is 李小辉 are TRANSFER
        final liItems = items.where((i) => i.counterparty == '李小辉').toList();
        expect(liItems.length, 8);
        for (final item in liItems) {
          expect(item.direction, FinanceDirection.transfer,
              reason: '李小辉流水必须为转账: ${item.description} ${item.amountMinor}');
          expect(item.category, 'TRANSFER');
        }

        // Verify normal expenses
        final foodItem = items.firstWhere(
            (i) => i.counterparty.contains('上海拉扎斯信息科技有限公司'));
        expect(foodItem.direction, FinanceDirection.expense);
        expect(foodItem.category, 'FOOD');

        final schoolItem =
            items.firstWhere((i) => i.counterparty.contains('昆明理工大学'));
        expect(schoolItem.direction, FinanceDirection.expense);
        expect(schoolItem.category, 'EDUCATION');

        final chatGptItem = items.firstWhere(
            (i) => i.counterparty.contains('CHATGPT'));
        expect(chatGptItem.direction, FinanceDirection.expense);

        // Verify income
        final interestItem =
            items.firstWhere((i) => i.description.contains('账户结息'));
        expect(interestItem.direction, FinanceDirection.income);
        expect(interestItem.category, 'INVESTMENT_INCOME');
        expect(interestItem.amountMinor, 3);
      });
    }
  });
}
