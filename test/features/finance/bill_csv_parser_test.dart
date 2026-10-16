import 'dart:io';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/finance/application/bill_csv_parser.dart';
import 'package:lifehub/features/finance/application/bill_import_service.dart';
import 'package:lifehub/features/finance/application/finance_export_service.dart';
import 'package:lifehub/features/finance/data/account_repository.dart';
import 'package:lifehub/features/finance/domain/finance_models.dart';
import 'package:drift/native.dart';

void main() {
  group('BillCsvParser Tests', () {
    test('parses WeChat bill CSV correctly', () {
      const wechatCsv = '''
微信支付账单明细,,,,,,,,,,
微信昵称：[用户测试],,,,,,,,,,
起始时间：[2026-09-01 00:00:00] 终止时间：[2026-09-18 23:59:59],,,,,,,,,,
----------------------------------------------------------------------------------------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-09-15 12:30:00,商户消费,美团外卖,美团订单,支出,¥35.50,零钱,支付成功,4200001234567890,10001,/
2026-09-15 18:00:00,微信红包,微信好友,微信红包,支出,¥50.00,招商银行储蓄卡(1234),支付成功,4200001234567891,10002,/
2026-09-16 08:30:00,商户消费,滴滴出行,网约车费,支出,¥24.80,微信支付,支付成功,4200001234567892,10003,/
2026-09-16 10:00:00,零钱提现,零钱通,零钱提现到银行卡,/,¥500.00,招商银行,提现成功,4200001234567893,10004,/
2026-09-17 15:20:00,转账,张三,朋友还款,收入,¥200.00,/,已收钱,4200001234567894,10005,/
''';

      final items = BillCsvParser.parse(wechatCsv);
      expect(items.length, 5);

      // Item 1: Meituan (at 12:30 lunch time -> 外卖午餐, need)
      expect(items[0].counterparty, '美团外卖');
      expect(items[0].amountMinor, 3550);
      expect(items[0].direction, FinanceDirection.expense);
      expect(items[0].category, 'FOOD');
      expect(items[0].subCategory, '外卖午餐');
      expect(items[0].expenseNature, ExpenseNature.need);
      expect(items[0].orderId, '4200001234567890');

      // Item 2: Red Packet
      expect(items[1].amountMinor, 5000);
      expect(items[1].direction, FinanceDirection.expense);
      expect(items[1].category, 'SOCIAL');
      expect(items[1].subCategory, '微信红包');
      expect(items[1].tags, contains('微信红包'));

      // Item 3: Didi Transport
      expect(items[2].amountMinor, 2480);
      expect(items[2].category, 'TRANSPORT');
      expect(items[2].subCategory, '打车出行');

      // Item 4: Transfer / Withdraw
      expect(items[3].amountMinor, 50000);
      expect(items[3].direction, FinanceDirection.transfer);
      expect(items[3].category, 'TRANSFER');

      // Item 5: Income
      expect(items[4].amountMinor, 20000);
      expect(items[4].direction, FinanceDirection.income);
    });

    test('parses Alipay bill CSV including Kuaishou platform withdrawal', () {
      const alipayCsv = '''
------------------------------------------------------------------------------------
支付宝交易记录明细查询
账号：test@example.com
起始日期：2026-09-01 00:00:00    终止日期：2026-09-18 23:59:59
----------------------------------------交易记录明细列表----------------------------------------
交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额（元）,收/付款方式,交易状态,交易订单号,商家订单号,备注
2026-09-14 09:15:00,收入,快手科技,kuaishou@service,快手收益提现到账,收入,1280.00,支付宝账户,交易成功,202609142200140001,KS8881,/
2026-09-14 14:00:00,餐饮美食,星巴克咖啡,starbucks@pay,生椰拿铁,支出,38.00,花呗,交易成功,202609142200140002,SB9992,/
2026-09-15 19:30:00,生活日用,永辉超市,supermarket@pay,蔬菜肉类,支出,86.50,招商银行储蓄卡,交易成功,202609142200140003,YH7773,/
2026-09-16 20:00:00,其他,支付宝,alipay@service,花呗自动还款,不计收支,150.00,余额宝,还款成功,202609142200140004,HB6664,/
''';

      final items = BillCsvParser.parse(alipayCsv);
      expect(items.length, 4);

      // Item 1: Kuaishou withdrawal
      expect(items[0].counterparty, '快手科技');
      expect(items[0].amountMinor, 128000);
      expect(items[0].direction, FinanceDirection.income);
      expect(items[0].category, 'PLATFORM_INCOME');
      expect(items[0].subCategory, '快手提现');

      // Item 2: Starbucks Coffee (Drink -> 咖啡奶茶, want)
      expect(items[1].amountMinor, 3800);
      expect(items[1].direction, FinanceDirection.expense);
      expect(items[1].category, 'FOOD');
      expect(items[1].subCategory, '咖啡奶茶');
      expect(items[1].expenseNature, ExpenseNature.want);
      expect(items[1].suggestedAccountType, FinanceAccountType.credit);

      // Item 3: Supermarket (Convenience / Supermarket -> 商超便利, need)
      expect(items[2].amountMinor, 8650);
      expect(items[2].category, 'FOOD');
      expect(items[2].subCategory, '商超便利');
      expect(items[2].expenseNature, ExpenseNature.need);

      // Item 4: Repayment (Huabei auto repayment -> expense per user rule)
      expect(items[3].amountMinor, 15000);
      expect(items[3].direction, FinanceDirection.expense);
      expect(items[3].category, 'FINANCE_EXPENSE');
      expect(items[3].subCategory, '花呗还款');
    });

    test('parses real user WeChat bill data with currency symbols and order IDs', () {
      const realWechat = '''
微信支付账单明细
微信昵称: [Aport]
起始时间: [2026-06-18 00:00:00] 终止时间: [2026-09-18 23:18:01]
导出类型: [全部账单]
导出时间: [2026-09-18 23:18:01]

共232笔记录
收入: 172笔 514.05元
支出: 46笔 2704.20元
中性交易: 14笔 757.31元
----------------------微信支付账单明细列表--------------------
交易时间	交易类型	交易对方	商品	收/支	金额(元)	支付方式	当前状态	交易单号	商户单号	备注
2026-09-18 16:19:07	商户消费	昆明理工大学	住宿费	支出	¥1,200.00	农业银行储蓄卡(1177)	支付成功	4500000459202609188981431909	H1-20252204382_920843	/
2026-09-15 19:06:44	微信红包	墨樊	/	支出	¥50.00	微信零钱	支付成功	4500000459202609188981431910	RED_1001	/
2026-09-10 10:34:47	群收款	魏西(听潮)	活动AA	收入	¥68.50	/	已收钱	4500000459202609188981431911	GRP_2001	/
''';

      final items = BillCsvParser.parse(realWechat);
      expect(items.length, 3);

      expect(items[0].counterparty, '昆明理工大学');
      expect(items[0].description, '住宿费');
      expect(items[0].amountMinor, 120000);
      expect(items[0].direction, FinanceDirection.expense);
      expect(items[0].sourcePaymentMethod, '农业银行储蓄卡(1177)');
      expect(items[0].orderId, '4500000459202609188981431909');

      expect(items[1].category, 'SOCIAL');
      expect(items[1].amountMinor, 5000);

      expect(items[2].direction, FinanceDirection.income);
      expect(items[2].amountMinor, 6850);
    });

    test('parses real user Alipay tab-delimited electronic customer receipt with slash dates', () {
      const realAlipay = '''
------------------------------------------------------------------------------------
导出信息：
姓名：李小辉
支付宝账户：18836191239
起始时间: [2026-06-19 00:00:00] 终止时间: [2026-09-19 00:03:07]
导出交易类型: [全部]
导出时间: [2026-09-19 00:03:07]
共380笔记录
收入: 274笔 215.74元
支出: 95笔 1696.39元
不计收支: 11笔 2006.19元

----------------------支付宝支付科技有限公司 电子客户回单----------------------
交易时间	交易分类	交易对方	对方账号	商品说明	金额(元)	收/支	交易状态	服务费(元)	成功退款(元)	资金状态
2026/9/18 18:52	餐饮美食	淘宝闪购	e50***@ali	不止馄饨(测试店)	18.50	支出	交易成功	0.00	0.00	已支出
2026/9/18 12:30	医疗健康	优德**店	you***@16	维A酸软膏	36.80	支出	交易成功	0.00	0.00	已支出
2026/9/19 00:03	其他	快手科技	ks***@kuaishou	快手提现收益	88.00	不计收支	交易成功	0.00	0.00	已到账
''';

      final items = BillCsvParser.parse(realAlipay);
      expect(items.length, 3);

      // Item 1: Wonton
      expect(items[0].counterparty, '淘宝闪购');
      expect(items[0].description, '不止馄饨(测试店)');
      expect(items[0].amountMinor, 1850);
      expect(items[0].direction, FinanceDirection.expense);
      expect(items[0].category, 'FOOD');
      expect(items[0].transactionTime, DateTime(2026, 9, 18, 18, 52));

      // Item 2: Medical
      expect(items[1].counterparty, '优德**店');
      expect(items[1].amountMinor, 3680);
      expect(items[1].category, 'MEDICAL');
      expect(items[1].expenseNature, ExpenseNature.need);

      // Item 3: Kuaishou withdrawal
      expect(items[2].counterparty, '快手科技');
      expect(items[2].amountMinor, 8800);
      expect(items[2].category, 'PLATFORM_INCOME');
      expect(items[2].direction, FinanceDirection.income);
    });

    test('parses GBK encoded Alipay CSV bytes correctly', () {
      final gbkCsvString = '''
------------------------------------------------------------------------------------
导出信息：
姓名：测试用户
------------------------支付宝支付科技有限公司  电子客户回单------------------------
交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
2026-09-18 18:52:09,餐饮美食,淘宝闪购,e50***@alibaba-inc.com,不止馄饨(恒园一楼店)外卖订单,支出,10.48,账户余额,交易成功,2026091823001185571433193755	,13180600726091834442378316487	,,
2026-09-18 10:00:00,转账红包,蚂蚁森林,service@alipay.com,现金红包-来自蚂蚁森林,收入,0.08,账户余额,交易成功,2026091823001185571433193756	,13180600726091834442378316488	,,
2026-09-17 12:00:00,生活服务,趣智校园,campus@163.com,校园充值,支出,10.00,账户余额,交易成功,2026091723001185571433193757	,13180600726091834442378316489	,,
''';
      final gbkBytes = gbk.encode(gbkCsvString);
      final items = BillCsvParser.parseBytes(gbkBytes, fileName: 'alipay.csv');
      expect(items.length, 3);
      expect(items[0].counterparty, '淘宝闪购');
      expect(items[0].amountMinor, 1048);
      expect(items[0].direction, FinanceDirection.expense);
      expect(items[0].category, 'FOOD');
      expect(items[0].orderId, '2026091823001185571433193755');

      // Ant Forest Red Packet Income
      expect(items[1].counterparty, '蚂蚁森林');
      expect(items[1].amountMinor, 8);
      expect(items[1].direction, FinanceDirection.income);
      expect(items[1].category, 'SOCIAL');

      // Campus service (campus recharge -> 校园一卡通 per user rule)
      expect(items[2].counterparty, '趣智校园');
      expect(items[2].category, 'EDUCATION');
      expect(items[2].subCategory, '校园一卡通');
    });

    test('preserves income direction for activity withdrawal rewards', () {
      const wechatActivityReward = '''
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-09-16 10:00:00,其他,提现成功，参与活动最高领68元,/,收入,0.50,/,已到账,45000000000001,M001,提现成功，参与活动最高领68元
2026-09-15 15:00:00,商户消费,东南大学,东南大学-消费,支出,300.00,农业银行储蓄卡(1177),支付成功,45000000000002,M002,/
2026-09-15 18:00:00,微信红包,曌龑,/,收入,0.29,/,已存入零钱,45000000000003,M003,/
''';
      final items = BillCsvParser.parse(wechatActivityReward);
      expect(items.length, 3);

      // Activity reward should be INCOME, NOT transfer!
      expect(items[0].direction, FinanceDirection.income);
      expect(items[0].category, 'SIDE_INCOME');
      expect(items[0].subCategory, '活动奖励');
      expect(items[0].amountMinor, 50);

      // Southeast University expense
      expect(items[1].direction, FinanceDirection.expense);
      expect(items[1].category, 'EDUCATION');
      expect(items[1].amountMinor, 30000);

      // Red packet income
      expect(items[2].direction, FinanceDirection.income);
      expect(items[2].category, 'SOCIAL');
      expect(items[2].amountMinor, 29);
    });

    test('parses real Alipay CSV and WeChat XLSX files on disk if present', () {
      final aliFile = File(r'd:\appDate\xwechat_files\wxid_1sqa6hldufdr22_e47c\msg\file\2026-09\支付宝交易明细(20260619-20260919) (1).csv');
      if (aliFile.existsSync()) {
        final bytes = aliFile.readAsBytesSync();
        final items = BillCsvParser.parseBytes(bytes, fileName: 'alipay.csv');
        expect(items.length, 375);
      }

      final wxFile = File(r'd:\appDate\xwechat_files\wxid_1sqa6hldufdr22_e47c\msg\file\2026-09\微信支付账单流水文件(20260618-20260918)_20260918231801.xlsx');
      if (wxFile.existsSync()) {
        final bytes = wxFile.readAsBytesSync();
        final items = BillCsvParser.parseBytes(bytes, fileName: 'wechat.xlsx');
        expect(items.length, 232);
      }
    });

    test('classifies Meituan Finance and ordinary recharge correctly', () {
      const wechatFinance = '''
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-08-30 18:27:00,商户消费,美团金融,美团金融,支出,¥3.94,微信零钱,支付成功,45000000000009,M009,美团金融
2026-09-01 10:00:00,普通充值,**辉,充值-普通充值,/,¥500.00,招商银行储蓄卡,充值成功,45000000000010,M010,充值-普通充值
''';
      final items = BillCsvParser.parse(wechatFinance);
      expect(items.length, 2);

      // Meituan Finance must be EXPENSE / FINANCE_EXPENSE
      expect(items[0].counterparty, '美团金融');
      expect(items[0].direction, FinanceDirection.expense);
      expect(items[0].category, 'FINANCE_EXPENSE');
      expect(items[0].subCategory, '信贷还款');
      expect(items[0].amountMinor, 394);

      // Ordinary recharge must be TRANSFER
      expect(items[1].direction, FinanceDirection.transfer);
      expect(items[1].category, 'TRANSFER');
      expect(items[1].subCategory, '储蓄充值');
    });

    test('treats non-bank card recharges and repayments as expense per user rule', () {
      const mixedWechat = '''
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-09-18 12:00:00,商户消费,昆明理工大学,一卡通充值,支出,50.00,微信零钱,支付成功,45000000000004,M004,/
2026-09-17 10:00:00,商户消费,财付通,微信分期还款,支出,120.00,零钱,支付成功,45000000000005,M005,/
2026-09-16 08:00:00,商户消费,蚂蚁金服,花呗账单分期还款,支出,200.00,微信支付,支付成功,45000000000006,M006,/
2026-09-15 09:00:00,零钱充值,中国农业银行,储蓄卡转入零钱,/,100.00,中国农业银行储蓄卡(1177),充值成功,45000000000007,M007,/
2026-09-14 15:00:00,零钱提现,零钱提现,零钱提现到招商银行,/,300.00,零钱,提现成功,45000000000008,M008,/
''';
      final items = BillCsvParser.parse(mixedWechat);
      expect(items.length, 5);

      // Campus card recharge: EXPENSE, EDUCATION / 校园一卡通, NEED
      expect(items[0].direction, FinanceDirection.expense);
      expect(items[0].category, 'EDUCATION');
      expect(items[0].subCategory, '校园一卡通');
      expect(items[0].expenseNature, ExpenseNature.need);

      // WeChat installment repayment: EXPENSE, FINANCE_EXPENSE / 分期还款
      expect(items[1].direction, FinanceDirection.expense);
      expect(items[1].category, 'FINANCE_EXPENSE');
      expect(items[1].subCategory, '分期还款');

      // Huabei repayment: EXPENSE, FINANCE_EXPENSE / 花呗还款
      expect(items[2].direction, FinanceDirection.expense);
      expect(items[2].category, 'FINANCE_EXPENSE');
      expect(items[2].subCategory, '花呗还款');

      // Genuine bank recharge: TRANSFER
      expect(items[3].direction, FinanceDirection.transfer);
      expect(items[3].category, 'TRANSFER');

      // Genuine bank withdrawal: TRANSFER
      expect(items[4].direction, FinanceDirection.transfer);
      expect(items[4].category, 'TRANSFER');
    });

    test('infers breakfast, lunch, dinner, late-night, snacks, and convenience stores accurately', () {
      // 1. Breakfast (08:15)
      final breakfast = FinanceCategoryInferer.infer(
        direction: FinanceDirection.expense,
        counterparty: '美团外卖',
        description: '早餐饮食订单',
        rawType: '商户消费',
        transactionTime: DateTime(2026, 9, 18, 8, 15),
      );
      expect(breakfast.category, 'FOOD');
      expect(breakfast.subCategory, '早餐饮食');
      expect(breakfast.expenseNature, ExpenseNature.need);

      // 2. Lunch (12:30)
      final lunch = FinanceCategoryInferer.infer(
        direction: FinanceDirection.expense,
        counterparty: '饿了么',
        description: '盖浇饭',
        rawType: '商户消费',
        transactionTime: DateTime(2026, 9, 18, 12, 30),
      );
      expect(lunch.category, 'FOOD');
      expect(lunch.subCategory, '外卖午餐');
      expect(lunch.expenseNature, ExpenseNature.need);

      // 3. Dinner (18:45)
      final dinner = FinanceCategoryInferer.infer(
        direction: FinanceDirection.expense,
        counterparty: '美团外卖',
        description: '黄焖鸡米饭',
        rawType: '商户消费',
        transactionTime: DateTime(2026, 9, 18, 18, 45),
      );
      expect(dinner.category, 'FOOD');
      expect(dinner.subCategory, '外卖晚餐');
      expect(dinner.expenseNature, ExpenseNature.need);

      // 4. Late-night snack (23:15)
      final lateNight = FinanceCategoryInferer.infer(
        direction: FinanceDirection.expense,
        counterparty: '美团外卖',
        description: '烧烤炸鸡',
        rawType: '商户消费',
        transactionTime: DateTime(2026, 9, 18, 23, 15),
      );
      expect(lateNight.category, 'FOOD');
      expect(lateNight.subCategory, '夜宵外卖');
      expect(lateNight.expenseNature, ExpenseNature.want);

      // 5. Online food / snacks
      final onlineSnack = FinanceCategoryInferer.infer(
        direction: FinanceDirection.expense,
        counterparty: '淘宝网三只松鼠旗舰店',
        description: '坚果大礼包食品',
        rawType: '商户消费',
        transactionTime: DateTime(2026, 9, 18, 14, 0),
      );
      expect(onlineSnack.category, 'FOOD');
      expect(onlineSnack.subCategory, '零食水果');
      expect(onlineSnack.expenseNature, ExpenseNature.want);

      // 6. Offline Convenience Store
      final convenience = FinanceCategoryInferer.infer(
        direction: FinanceDirection.expense,
        counterparty: '罗森便利店',
        description: '线下消费',
        rawType: '商户消费',
        transactionTime: DateTime(2026, 9, 18, 11, 0),
      );
      expect(convenience.category, 'FOOD');
      expect(convenience.subCategory, '商超便利');
      expect(convenience.expenseNature, ExpenseNature.need);
    });
  });

  group('BillImportService & Deduplication Tests', () {
    late AppDatabase database;
    late BillImportService service;
    late AccountRepository accountRepo;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      service = BillImportService(database);
      accountRepo = AccountRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('deduplicates existing entries and batch imports cleanly', () async {
      await accountRepo.ensureDefaultAccounts();
      final accounts = await accountRepo.listAccounts();
      final wechatAcc = accounts.firstWhere((a) => a.name.contains('微信'));

      final items = [
        ParsedBillItem(
          sourceType: BillSourceType.wechat,
          transactionTime: DateTime(2026, 9, 15, 12, 0),
          direction: FinanceDirection.expense,
          amountMinor: 2500,
          counterparty: '美团外卖',
          description: '快餐便当',
          orderId: 'ORDER_1001',
          sourcePaymentMethod: '微信零钱',
          status: '支付成功',
          category: 'FOOD',
          subCategory: '午晚餐',
          expenseNature: ExpenseNature.need,
          assignedAccountId: wechatAcc.id,
        ),
        ParsedBillItem(
          sourceType: BillSourceType.wechat,
          transactionTime: DateTime(2026, 9, 15, 18, 0),
          direction: FinanceDirection.income,
          amountMinor: 6600,
          counterparty: '微信好友',
          description: '微信红包',
          orderId: 'ORDER_1002',
          sourcePaymentMethod: '微信零钱',
          status: '已收款',
          category: 'SOCIAL_INCOME',
          subCategory: '收微信红包',
          expenseNature: ExpenseNature.want,
          assignedAccountId: wechatAcc.id,
        ),
      ];

      // Initial import
      final res1 = await service.importBatch(items);
      expect(res1.importedCount, 2);
      expect(res1.totalExpenseMinor, 2500);
      expect(res1.totalIncomeMinor, 6600);

      // Verify wechat account balance updated
      final updatedWechat = await accountRepo.getAccount(wechatAcc.id);
      expect(updatedWechat!.balanceMinor, wechatAcc.balanceMinor - 2500 + 6600);

      // Second check: simulate importing the same file again
      await service.checkDuplicates(items);
      expect(items[0].isDuplicate, isTrue);
      expect(items[0].selected, isFalse);
      expect(items[1].isDuplicate, isTrue);
      expect(items[1].selected, isFalse);

      // Re-running batch import should import 0 items
      final res2 = await service.importBatch(items);
      expect(res2.importedCount, 0);
      expect(res2.skippedCount, 2);
    });

    test('exports entries to UTF-8 BOM CSV bytes', () async {
      final exportService = FinanceExportService(database);
      final bytes = await exportService.exportToCsvBytes();
      expect(bytes, isNotEmpty);
      // Verify BOM prefix: 0xEF, 0xBB, 0xBF
      expect(bytes[0], 0xEF);
      expect(bytes[1], 0xBB);
      expect(bytes[2], 0xBF);
    });
  });
}
