import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class UserMerchantRule {
  final String counterparty;
  final String category;
  final String? subCategory;
  final String? expenseNature;

  const UserMerchantRule({
    required this.counterparty,
    required this.category,
    this.subCategory,
    this.expenseNature,
  });

  Map<String, dynamic> toJson() => {
        'counterparty': counterparty,
        'category': category,
        if (subCategory != null) 'subCategory': subCategory,
        if (expenseNature != null) 'expenseNature': expenseNature,
      };

  factory UserMerchantRule.fromJson(Map<String, dynamic> json) =>
      UserMerchantRule(
        counterparty: json['counterparty'] as String,
        category: json['category'] as String,
        subCategory: json['subCategory'] as String?,
        expenseNature: json['expenseNature'] as String?,
      );
}

class FinancePreferences {
  final SharedPreferences _preferences;

  FinancePreferences(this._preferences);

  static const _monthlyBudgetPrefix = 'finance.budget.';
  static const _defaultMonthlyBudget = 'finance.budget.default';
  static const _merchantRulesKey = 'finance.merchant_rules';

  /// Get monthly budget in minor units (cents/分). Returns null if not set.
  int? getMonthlyBudget(int year, int month) {
    final key = '$_monthlyBudgetPrefix${year}_${month.toString().padLeft(2, '0')}';
    if (_preferences.containsKey(key)) {
      return _preferences.getInt(key);
    }
    // Fallback to default monthly budget if any
    if (_preferences.containsKey(_defaultMonthlyBudget)) {
      return _preferences.getInt(_defaultMonthlyBudget);
    }
    return null;
  }

  /// Set monthly budget in minor units. If [budgetMinor] is null or <= 0, removes the budget.
  Future<void> setMonthlyBudget(int year, int month, int? budgetMinor) async {
    final key = '$_monthlyBudgetPrefix${year}_${month.toString().padLeft(2, '0')}';
    if (budgetMinor == null || budgetMinor <= 0) {
      await _preferences.remove(key);
    } else {
      await _preferences.setInt(key, budgetMinor);
    }
  }

  /// Get all learned merchant rules
  Map<String, UserMerchantRule> getMerchantRules() {
    final raw = _preferences.getString(_merchantRulesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(
          key,
          UserMerchantRule.fromJson(value as Map<String, dynamic>),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  /// Save or update a learned merchant rule
  Future<void> saveMerchantRule(
    String counterparty, {
    required String category,
    String? subCategory,
    String? expenseNature,
  }) async {
    final trimmed = counterparty.trim();
    if (trimmed.isEmpty) return;
    final rules = getMerchantRules();
    rules[trimmed] = UserMerchantRule(
      counterparty: trimmed,
      category: category,
      subCategory: subCategory,
      expenseNature: expenseNature,
    );
    final encoded = jsonEncode(rules.map((k, v) => MapEntry(k, v.toJson())));
    await _preferences.setString(_merchantRulesKey, encoded);
  }

  /// Remove a merchant rule
  Future<void> removeMerchantRule(String counterparty) async {
    final trimmed = counterparty.trim();
    final rules = getMerchantRules();
    if (rules.remove(trimmed) != null) {
      final encoded = jsonEncode(rules.map((k, v) => MapEntry(k, v.toJson())));
      await _preferences.setString(_merchantRulesKey, encoded);
    }
  }
}
