import 'package:flutter/material.dart';

abstract final class FinanceDirection {
  static const income = 'INCOME';
  static const expense = 'EXPENSE';
  static const transfer = 'TRANSFER';
}

abstract final class ExpenseNature {
  static const need = 'NEED'; // 刚需必需
  static const want = 'WANT'; // 弹性可选
}

abstract final class FinanceAccountType {
  static const wallet = 'WALLET'; // 微信钱包、支付宝
  static const debit = 'DEBIT'; // 借记卡/储蓄卡
  static const credit = 'CREDIT'; // 信用卡、花呗、白条
  static const platform = 'PLATFORM'; // 平台账户（快手、抖音、拼多多等收益钱包）
  static const cash = 'CASH'; // 现金
  static const other = 'OTHER'; // 其他

  static String label(String type) {
    switch (type) {
      case wallet:
        return '电子钱包';
      case debit:
        return '储蓄卡';
      case credit:
        return '信用卡/信用贷';
      case platform:
        return '收益平台/零钱';
      case cash:
        return '现金';
      default:
        return '其他账户';
    }
  }

  static IconData icon(String type) {
    switch (type) {
      case wallet:
        return Icons.account_balance_wallet_outlined;
      case debit:
        return Icons.credit_card_outlined;
      case credit:
        return Icons.credit_score_outlined;
      case platform:
        return Icons.monetization_on_outlined;
      case cash:
        return Icons.payments_outlined;
      default:
        return Icons.savings_outlined;
    }
  }
}

class CategoryDef {
  const CategoryDef({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.subcategories,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final List<String> subcategories;
}

class FinanceCategoryCatalog {
  static const List<CategoryDef> expenseCategories = [
    CategoryDef(
      id: 'FOOD',
      name: '餐饮食品',
      icon: Icons.restaurant,
      color: Colors.orange,
      subcategories: [
        '外卖午餐',
        '外卖晚餐',
        '早餐饮食',
        '外卖便当',
        '夜宵外卖',
        '商超便利',
        '零食水果',
        '咖啡奶茶',
        '朋友聚餐',
        '买菜做饭',
      ],
    ),
    CategoryDef(
      id: 'TRANSPORT',
      name: '交通出行',
      icon: Icons.directions_subway,
      color: Colors.blue,
      subcategories: ['公共交通', '打车出行', '加油充电', '停车过路', '车辆维保', '高铁机票'],
    ),
    CategoryDef(
      id: 'HOUSING',
      name: '居家日常',
      icon: Icons.home_outlined,
      color: Colors.brown,
      subcategories: ['房租房贷', '水电燃气', '物业宽带', '日用耗材', '家居维修'],
    ),
    CategoryDef(
      id: 'SHOPPING',
      name: '购物消费',
      icon: Icons.shopping_bag_outlined,
      color: Colors.purple,
      subcategories: ['服饰鞋包', '数码电器', '美妆个护', '日用百货', '运动户外'],
    ),
    CategoryDef(
      id: 'SOCIAL',
      name: '人情社交',
      icon: Icons.card_giftcard,
      color: Colors.red,
      subcategories: ['微信红包', '亲友转账', '请客聚会', '人情随礼', '孝敬父母', '送礼赞助', '公益慈善'],
    ),
    CategoryDef(
      id: 'ENTERTAINMENT',
      name: '休闲娱乐',
      icon: Icons.sports_esports_outlined,
      color: Colors.pink,
      subcategories: ['游戏充值', '电影演出', '旅游度假', '运动健身', '洗浴按摩'],
    ),
    CategoryDef(
      id: 'MEDICAL',
      name: '医疗健康',
      icon: Icons.local_hospital_outlined,
      color: Colors.teal,
      subcategories: ['药品购买', '门诊检查', '疫苗体检', '保健补品'],
    ),
    CategoryDef(
      id: 'EDUCATION',
      name: '教育校园',
      icon: Icons.school_outlined,
      color: Colors.indigo,
      subcategories: ['校园一卡通', '校园生活', '学杂住宿', '书籍资料', '培训课程', '考试认证'],
    ),
    CategoryDef(
      id: 'FINANCE_EXPENSE',
      name: '金融还款',
      icon: Icons.credit_score_outlined,
      color: Colors.deepPurple,
      subcategories: ['月付还款', '信用卡还款', '花呗还款', '信贷还款', '分期还款'],
    ),
    CategoryDef(
      id: 'STUDY',
      name: '学习进修',
      icon: Icons.auto_stories_outlined,
      color: Colors.indigoAccent,
      subcategories: ['书籍资料', '培训课程', '考试认证'],
    ),
    CategoryDef(
      id: 'OTHER',
      name: '其他支出',
      icon: Icons.category_outlined,
      color: Colors.blueGrey,
      subcategories: ['意外开销', '手续费', '日常杂项', '未分类'],
    ),
  ];

  static const List<CategoryDef> incomeCategories = [
    CategoryDef(
      id: 'SIDE_INCOME',
      name: '活动与副业',
      icon: Icons.volunteer_activism_outlined,
      color: Colors.amber,
      subcategories: ['活动奖励', '平台收益', '副业兼职', '问卷奖励'],
    ),
    CategoryDef(
      id: 'PLATFORM_INCOME',
      name: '平台收益/提现',
      icon: Icons.live_tv_outlined,
      color: Colors.deepOrange,
      subcategories: ['快手提现', '抖音收益', '自媒体收入', '直播打赏', '电商返利'],
    ),
    CategoryDef(
      id: 'SALARY',
      name: '薪酬收入',
      icon: Icons.work_outline,
      color: Colors.green,
      subcategories: ['工资入账', '年终奖金', '绩效津贴'],
    ),
    CategoryDef(
      id: 'BONUS',
      name: '兼职外快',
      icon: Icons.card_giftcard,
      color: Colors.orange,
      subcategories: ['副业外包', '劳务报酬', '设计开发'],
    ),
    CategoryDef(
      id: 'SOCIAL_INCOME',
      name: '人情/红包收入',
      icon: Icons.redeem,
      color: Colors.redAccent,
      subcategories: ['收微信红包', '亲友转账收款', '人情还礼'],
    ),
    CategoryDef(
      id: 'INVESTMENT_INCOME',
      name: '理财收益',
      icon: Icons.trending_up,
      color: Colors.teal,
      subcategories: ['理财收益', '基金分红', '利息入账', '转卖闲置'],
    ),
    CategoryDef(
      id: 'INVESTMENT',
      name: '理财投资',
      icon: Icons.trending_up,
      color: Colors.teal,
      subcategories: ['基金理财', '股息利息', '转卖闲置'],
    ),
    CategoryDef(
      id: 'OTHER_INCOME',
      name: '其他收入',
      icon: Icons.attach_money,
      color: Colors.lightGreen,
      subcategories: ['报销入账', '退款返还', '其他到账'],
    ),
  ];

  static const List<String> transferSubcategories = [
    '平台收益提现', // 快手/抖音 -> 银行卡/微信
    '储蓄充值', // 银行卡 -> 微信零钱/支付宝
    '零钱提现', // 微信/支付宝 -> 银行卡
    '信用卡还款', // 银行卡/微信 -> 信用卡/花呗
    '借款/还款', // 个人借贷往来
    '内部自转', // 其他账户互转
  ];

  static const List<String> commonSceneTags = [
    '本地日常',
    '异地消费',
    '差旅出差',
    '旅游度假',
    '老家探亲',
    '公司垫付',
    'AA聚会',
    '冲动消费',
  ];

  static String label(String id) {
    if (id == 'TRANSFER') return '账户转账';
    if (id == 'SIDE_INCOME') return '活动与副业';
    if (id == 'INVESTMENT_INCOME') return '理财收益';
    if (id == 'PLATFORM_INCOME') return '平台收益/提现';
    if (id == 'OTHER_INCOME') return '其他收入';
    if (id == 'FINANCE_EXPENSE') return '金融还款';
    for (final c in expenseCategories) {
      if (c.id == id) return c.name;
    }
    for (final c in incomeCategories) {
      if (c.id == id) return c.name;
    }
    return id;
  }

  static CategoryDef getExpense(String id) {
    return expenseCategories.firstWhere(
      (c) => c.id == id,
      orElse: () => expenseCategories.last,
    );
  }

  static CategoryDef getIncome(String id) {
    return incomeCategories.firstWhere(
      (c) => c.id == id,
      orElse: () {
        for (final c in expenseCategories) {
          if (c.id == id) return c;
        }
        return incomeCategories.last;
      },
    );
  }

  static CategoryDef getDef(String id, [String? direction]) {
    if (direction == FinanceDirection.income) {
      for (final c in incomeCategories) {
        if (c.id == id) return c;
      }
      for (final c in expenseCategories) {
        if (c.id == id) return c;
      }
      return incomeCategories.last;
    }
    if (direction == FinanceDirection.transfer || id == 'TRANSFER') {
      return const CategoryDef(
        id: 'TRANSFER',
        name: '账户转账',
        icon: Icons.swap_horiz_rounded,
        color: Colors.purple,
        subcategories: transferSubcategories,
      );
    }
    for (final c in expenseCategories) {
      if (c.id == id) return c;
    }
    for (final c in incomeCategories) {
      if (c.id == id) return c;
    }
    return expenseCategories.last;
  }

  static String getCategoryName(String id, String direction) {
    return getDef(id, direction).name;
  }

  static IconData getCategoryIcon(String id, String direction) {
    return getDef(id, direction).icon;
  }
}

class FinanceDraft {
  const FinanceDraft({
    required this.direction,
    required this.amountMinor,
    required this.occurredAt,
    this.currency = 'CNY',
    this.category = 'OTHER',
    this.subCategory,
    this.accountId,
    this.targetAccountId,
    this.expenseNature = ExpenseNature.need,
    this.isReimbursable = false,
    this.reimburseStatus,
    this.tags = const [],
    this.relatedEntryId,
    this.note,
    this.sensitive = false,
  });

  final String direction;
  final int amountMinor;
  final String currency;
  final String category;
  final String? subCategory;
  final String? accountId;
  final String? targetAccountId;
  final String expenseNature;
  final bool isReimbursable;
  final String? reimburseStatus;
  final List<String> tags;
  final String? relatedEntryId;
  final DateTime occurredAt;
  final String? note;
  final bool sensitive;
}

class AccountDraft {
  const AccountDraft({
    required this.name,
    required this.accountType,
    this.balanceMinor = 0,
    this.currency = 'CNY',
    this.cardLastFour,
    this.color = '#4F46E5',
    this.iconName,
    this.includeInNetWorth = true,
    this.billingDay,
    this.repaymentDay,
    this.creditLimitMinor,
    this.notes,
  });

  final String name;
  final String accountType;
  final int balanceMinor;
  final String currency;
  final String? cardLastFour;
  final String color;
  final String? iconName;
  final bool includeInNetWorth;
  final int? billingDay;
  final int? repaymentDay;
  final int? creditLimitMinor;
  final String? notes;
}

class RichFinanceSummary {
  const RichFinanceSummary({
    required this.incomeMinor,
    required this.expenseMinor,
    required this.transferCount,
    required this.needMinor,
    required this.wantMinor,
    required this.pendingReimburseMinor,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.expenseBySubCategory,
    required this.dailyExpense,
    required this.tagBreakdown,
  });

  final int incomeMinor;
  final int expenseMinor;
  final int transferCount;
  final int needMinor;
  final int wantMinor;
  final int pendingReimburseMinor;
  final Map<String, int> expenseByCategory;
  final Map<String, int> incomeByCategory;
  final Map<String, int> expenseBySubCategory;
  final Map<int, int> dailyExpense; // day -> amountMinor
  final Map<String, int> tagBreakdown; // tag -> amountMinor

  int get netMinor => incomeMinor - expenseMinor;
  double get needRatio =>
      expenseMinor > 0 ? (needMinor / expenseMinor).clamp(0.0, 1.0) : 0.0;
  double get wantRatio =>
      expenseMinor > 0 ? (wantMinor / expenseMinor).clamp(0.0, 1.0) : 0.0;
}
