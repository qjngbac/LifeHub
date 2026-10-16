import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/finance/data/account_repository.dart';
import 'package:lifehub/features/finance/domain/finance_models.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class AccountsManagementPage extends ConsumerStatefulWidget {
  const AccountsManagementPage({super.key});

  @override
  ConsumerState<AccountsManagementPage> createState() =>
      _AccountsManagementPageState();
}

class _AccountsManagementPageState
    extends ConsumerState<AccountsManagementPage> {
  int _revision = 0;

  void _refresh() => setState(() => _revision++);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accountRepo = AccountRepository(ref.watch(databaseProvider));

    return Scaffold(
      appBar: AppBar(
        title: const Text('资金账户与资产管理'),
        actions: [
          IconButton(
            tooltip: '新增账户',
            icon: const Icon(Icons.add),
            onPressed: () => _openAccountDialog(accountRepo),
          ),
        ],
      ),
      body: FutureBuilder<AccountNetWorthSummary>(
        key: ValueKey('net_worth_$_revision'),
        future: () async {
          await accountRepo.ensureDefaultAccounts();
          return accountRepo.getNetWorthSummary();
        }(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final summary = snapshot.data!;
          final accounts = summary.accounts;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              // Net Worth Summary Card
              Card(
                elevation: 0,
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                      color: colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '总净资产估算',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${summary.accounts.length} 个账户',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '¥${(summary.netWorthMinor / 100).toStringAsFixed(2)}',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: summary.netWorthMinor >= 0
                              ? colorScheme.primary
                              : colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '流动资产 (储蓄/零钱)',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(color: colorScheme.outline),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '¥${(summary.totalAssetsMinor / 100).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '总负债 (信用卡/花呗)',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(color: colorScheme.outline),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '-¥${(summary.totalLiabilitiesMinor / 100).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.error,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '各渠道账户列表',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '点击卡片可校准余额或编辑',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              for (final acc in accounts)
                _AccountCard(
                  account: acc,
                  onEdit: () => _openAccountDialog(accountRepo, existing: acc),
                  onAdjustBalance: () =>
                      _openAdjustBalanceDialog(accountRepo, acc),
                  onDelete: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('删除账户「${acc.name}」？'),
                        content: const Text(
                            '删除账户不会删除历史流水，但后续记账将无法再选该账户。确认删除？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.error),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await accountRepo.delete(acc.id);
                      _refresh();
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openAdjustBalanceDialog(
      AccountRepository repo, FinanceAccountEntry account) async {
    final controller = TextEditingController(
        text: (account.balanceMinor / 100).toStringAsFixed(2));

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => KeyboardSafeFormDialog(
        title: Text('校准「${account.name}」余额'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '如查看到实际微信/支付宝/银行卡结余有偏差，可在此直接输入最新真实余额完成对账对齐：',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: '最新实际余额（元） *',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              final val = double.tryParse(text);
              if (val == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入有效金额')),
                );
                return;
              }
              final newMinor = (val * 100).round();
              await repo.adjustBalance(account.id, newMinor - account.balanceMinor);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('完成校准'),
          ),
        ],
      ),
    );

    if (updated == true) _refresh();
  }

  Future<void> _openAccountDialog(AccountRepository repo,
      {FinanceAccountEntry? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final balanceCtrl = TextEditingController(
        text: existing == null
            ? '0.00'
            : (existing.balanceMinor / 100).toStringAsFixed(2));
    final cardLastCtrl =
        TextEditingController(text: existing?.cardLastFour ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    String accountType = existing?.accountType ?? FinanceAccountType.wallet;
    bool includeInNetWorth = existing?.includeInNetWorth ?? true;
    String colorHex = existing?.color ?? '#4F46E5';

    final colors = [
      '#07C160', // 微信绿
      '#1677FF', // 支付宝蓝
      '#096DD9', // 银行深蓝
      '#FA8C16', // 信用橙
      '#FF4D4F', // 平台红 (快手/抖音)
      '#722ED1', // 紫色
      '#FAAD14', // 现金黄
      '#13C2C2', // 青绿
    ];

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => KeyboardSafeFormDialog(
          title: Text(existing == null ? '新增资金账户' : '编辑账户'),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: existing == null,
                decoration: const InputDecoration(
                  labelText: '账户名称 (如招商储蓄卡、快手收益钱包) *',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: accountType,
                decoration: const InputDecoration(labelText: '账户性质'),
                items: [
                  FinanceAccountType.wallet,
                  FinanceAccountType.debit,
                  FinanceAccountType.credit,
                  FinanceAccountType.platform,
                  FinanceAccountType.cash,
                  FinanceAccountType.other,
                ]
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(FinanceAccountType.label(t)),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => accountType = val);
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: balanceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: '初始余额（元） *',
                  prefixText: '¥ ',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cardLastCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: '卡号末四位 (选填)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              // Color selection row
              Row(
                children: [
                  const Text('标识色彩: ', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                       child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: colors.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (ctx, i) {
                          final c = colors[i];
                          final colorVal =
                              Color(int.parse('0xFF${c.replaceFirst('#', '')}'));
                          final isSelected = colorHex == c;
                          return GestureDetector(
                            onTap: () => setDialogState(() => colorHex = c),
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: colorVal,
                              child: isSelected
                                  ? const Icon(Icons.check,
                                      size: 16, color: Colors.white)
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('计入个人净资产统计'),
                contentPadding: EdgeInsets.zero,
                value: includeInNetWorth,
                onChanged: (val) =>
                    setDialogState(() => includeInNetWorth = val),
              ),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: '备注 (选填)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入账户名称')),
                  );
                  return;
                }
                final balance = double.tryParse(balanceCtrl.text.trim()) ?? 0.0;
                final draft = AccountDraft(
                  name: name,
                  accountType: accountType,
                  balanceMinor: (balance * 100).round(),
                  cardLastFour: cardLastCtrl.text.trim().isNotEmpty
                      ? cardLastCtrl.text.trim()
                      : null,
                  color: colorHex,
                  includeInNetWorth: includeInNetWorth,
                  notes: notesCtrl.text.trim().isNotEmpty
                      ? notesCtrl.text.trim()
                      : null,
                );

                if (existing == null) {
                  await repo.create(draft);
                } else {
                  await repo.update(existing.id, draft);
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) _refresh();
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.onEdit,
    required this.onAdjustBalance,
    required this.onDelete,
  });

  final FinanceAccountEntry account;
  final VoidCallback onEdit;
  final VoidCallback onAdjustBalance;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colorVal = Color(
        int.parse('0xFF${account.color.replaceFirst('#', '').padRight(6, '0')}'));
    final isNegative = account.balanceMinor < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: ListTile(
        onTap: onAdjustBalance,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: colorVal.withValues(alpha: 0.15),
          child: Icon(
            FinanceAccountType.icon(account.accountType),
            color: colorVal,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                account.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (account.cardLastFour?.isNotEmpty == true) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '*${account.cardLastFour!}',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${FinanceAccountType.label(account.accountType)}${account.notes?.isNotEmpty == true ? ' · ${account.notes!}' : ''}',
          style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '¥${(account.balanceMinor / 100).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isNegative ? colorScheme.error : null,
                  ),
                ),
                Text(
                  account.includeInNetWorth ? '计入净资产' : '不计入净资产',
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (val) {
                if (val == 'adjust') onAdjustBalance();
                if (val == 'edit') onEdit();
                if (val == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'adjust',
                  child: Row(
                    children: [
                      Icon(Icons.tune_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('校准余额 / 对账'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('编辑账户'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('删除账户', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
