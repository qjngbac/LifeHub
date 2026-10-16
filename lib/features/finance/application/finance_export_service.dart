import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/finance/data/account_repository.dart';
import 'package:lifehub/features/finance/data/finance_repository.dart';

class FinanceExportService {
  FinanceExportService(this._database);
  final AppDatabase _database;

  /// Generates CSV string with UTF-8 BOM.
  Future<Uint8List> exportToCsvBytes({DateTime? month}) async {
    final financeRepo = FinanceRepository(_database);
    final accountRepo = AccountRepository(_database);

    final entries = month != null
        ? await financeRepo.list(
            start: DateTime(month.year, month.month),
            end: DateTime(month.year, month.month + 1),
          )
        : await financeRepo.list();
    final accounts = await accountRepo.listAccounts();
    final accountMap = {for (final a in accounts) a.id: a.name};

    final rows = <List<dynamic>>[];

    // CSV Header
    rows.add([
      '记账日期',
      '收支类型',
      '金额(元)',
      '主分类',
      '细分子类',
      '资金账户',
      '消费性质',
      '待报销状态',
      '标签',
      '备注说明',
    ]);

    for (final e in entries) {
      final dateStr = DateFormat('yyyy-MM-dd HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(e.occurredAt));

      String typeStr = '支出';
      if (e.direction == FinanceDirection.income) {
        typeStr = '收入';
      } else if (e.direction == FinanceDirection.transfer) {
        typeStr = '转账/提现';
      }

      final amountStr = (e.amountMinor / 100).toStringAsFixed(2);
      final accountName = e.accountId != null
          ? accountMap[e.accountId] ?? '未知账户'
          : '默认账户';

      String natureStr = e.expenseNature == ExpenseNature.need ? '刚需必需' : '改善可选';
      String reimburseStr = '-';
      if (e.isReimbursable) {
        reimburseStr = e.reimburseStatus == 'REIMBURSED' ? '已收回报销' : '待报销垫付';
      }

      String tagsStr = '';
      if (e.tagsJson != null && e.tagsJson!.isNotEmpty) {
        try {
          final list = (jsonDecode(e.tagsJson!) as List).map((x) => x.toString());
          tagsStr = list.join('; ');
        } catch (_) {}
      }

      rows.add([
        dateStr,
        typeStr,
        amountStr,
        e.category,
        e.subCategory ?? '',
        accountName,
        natureStr,
        reimburseStr,
        tagsStr,
        e.note ?? '',
      ]);
    }

    final csvString = csv.encode(rows);
    // Add UTF-8 BOM (\uFEFF) so Excel opens without mojibake
    final bom = [0xEF, 0xBB, 0xBF];
    final contentBytes = utf8.encode(csvString);
    return Uint8List.fromList([...bom, ...contentBytes]);
  }
}
