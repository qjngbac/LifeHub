import 'package:flutter/material.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/life_records/data/lunar_date_helper.dart';
import 'package:lifehub/features/life_records/presentation/lunar_date_picker.dart';

/// 纪念日与倒数日独立创建/编辑页面
class AnniversaryFormPage extends StatefulWidget {
  const AnniversaryFormPage({
    super.key,
    this.current,
    this.relationshipId,
    this.initialDate,
  });

  final AnniversaryEntry? current;
  final String? relationshipId;
  final DateTime? initialDate;

  @override
  State<AnniversaryFormPage> createState() => _AnniversaryFormPageState();
}

class _AnniversaryFormPageState extends State<AnniversaryFormPage> {
  late final TextEditingController _titleController;
  late DateTime _date;
  late String _category;
  late bool _repeat;
  late bool _showInToday;

  late bool _isLunar;
  late int _lunarYear;
  late int _lunarMonth;
  late int _lunarDay;
  late bool _isLeapMonth;

  static const _categoryOptions = [
    ('LIFE', '生活', Icons.event_note_outlined),
    ('RELATIONSHIP', '恋爱/纪念', Icons.favorite_rounded),
    ('BIRTHDAY', '生日', Icons.cake_outlined),
    ('EXAM', '考试/学业', Icons.school_outlined),
    ('WORK', '工作/事业', Icons.work_outline),
    ('TRAVEL', '旅行/出游', Icons.flight_takeoff_outlined),
    ('HOLIDAY', '节庆/假日', Icons.celebration_outlined),
  ];

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _titleController = TextEditingController(text: current?.title ?? '');
    _date = current == null
        ? (widget.initialDate ?? DateTime.now())
        : DateKeys.fromLocalDateKey(current.date);
    _category = current?.category ??
        (widget.relationshipId != null ? 'RELATIONSHIP' : 'LIFE');
    _repeat = current?.repeatYearly ?? true;
    _showInToday = current?.showInToday ?? true;

    final currentLunar = LunarInfo.fromMetadata(current?.metadata);
    _isLunar = currentLunar.isLunar;
    _lunarYear = currentLunar.lunarYear ??
        (current != null
            ? DateKeys.fromLocalDateKey(current.date).year
            : DateTime.now().year);
    _lunarMonth = currentLunar.lunarMonth ?? 8;
    _lunarDay = currentLunar.lunarDay ?? 15;
    _isLeapMonth = currentLunar.isLeapMonth;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请输入事项名称')));
      return;
    }

    final draft = AnniversaryDraft(
      title: title,
      date: _isLunar
          ? LunarDateHelper.lunarToSolar(
              year: _lunarYear,
              month: _lunarMonth,
              day: _lunarDay,
              isLeapMonth: _isLeapMonth,
            )
          : _date,
      repeatYearly: _repeat,
      relationshipId: widget.relationshipId ?? widget.current?.relationshipId,
      category: _category,
      showInToday: _showInToday,
      isLunar: _isLunar,
      lunarYear: _isLunar ? _lunarYear : null,
      lunarMonth: _isLunar ? _lunarMonth : null,
      lunarDay: _isLunar ? _lunarDay : null,
      isLeapMonth: _isLunar ? _isLeapMonth : false,
    );

    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.current == null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    final DateTime effectiveSolarTarget;
    final int diffDays;
    if (_isLunar) {
      final nextSolar = LunarDateHelper.nextLunarOccurrence(
        month: _lunarMonth,
        day: _lunarDay,
        isLeapMonth: _isLeapMonth,
        from: now,
        repeatYearly: _repeat,
        originalYear: _lunarYear,
      );
      effectiveSolarTarget = nextSolar;
      diffDays = nextSolar.difference(today).inDays;
    } else {
      final target = DateTime(_date.year, _date.month, _date.day);
      if (_repeat) {
        final maxDay = DateTime(today.year, _date.month + 1, 0).day;
        var cand =
            DateTime(today.year, _date.month, _date.day.clamp(1, maxDay));
        if (cand.isBefore(today)) {
          final nextMaxDay =
              DateTime(today.year + 1, _date.month + 1, 0).day;
          cand = DateTime(
              today.year + 1, _date.month, _date.day.clamp(1, nextMaxDay));
        }
        effectiveSolarTarget = cand;
        diffDays = cand.difference(today).inDays;
      } else {
        effectiveSolarTarget = target;
        diffDays = target.difference(today).inDays;
      }
    }
    final weekday = weekdays[effectiveSolarTarget.weekday - 1];

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '添加纪念日 / 倒数日' : '编辑纪念日 / 倒数日'),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              '保存',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 事项名称
            TextFormField(
              controller: _titleController,
              autofocus: isNew,
              decoration: InputDecoration(
                labelText: '事项名称',
                hintText: '例如：考研、恋爱一周年、妈妈生日',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.bookmark_border_outlined),
              ),
            ),
            const SizedBox(height: 18),

            // 分类选择
            Text(
              '事项分类',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categoryOptions.map((opt) {
                final isSelected = _category.toUpperCase() == opt.$1;
                return ChoiceChip(
                  showCheckmark: false,
                  selected: isSelected,
                  avatar: Icon(
                    opt.$3,
                    size: 16,
                    color: isSelected
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(opt.$2),
                  selectedColor: theme.colorScheme.secondaryContainer,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurface,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? theme.colorScheme.secondary.withValues(alpha: 0.35)
                        : theme.colorScheme.outlineVariant,
                    width: 0.8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _category = opt.$1);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 历法选择
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '历法类型',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('公历 (阳历)', style: TextStyle(fontSize: 13)),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('农历 (阴历)', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                  selected: {_isLunar},
                  onSelectionChanged: (set) {
                    final selected = set.first;
                    setState(() {
                      _isLunar = selected;
                      if (_isLunar) {
                        final l = LunarDateHelper.solarToLunar(_date);
                        _lunarYear = l.getYear();
                        _lunarMonth = l.getMonth().abs();
                        _isLeapMonth = l.getMonth() < 0;
                        _lunarDay = l.getDay();
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 日期输入
            if (!_isLunar) ...[
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Icon(
                    Icons.calendar_today_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    '${_date.year}年${_date.month}月${_date.day}日',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '对应农历：${LunarDateHelper.getLunarSummary(_date)}',
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200),
                    );
                    if (picked != null) {
                      setState(() => _date = picked);
                    }
                  },
                ),
              ),
            ] else ...[
              LunarDatePickerWidget(
                year: _lunarYear,
                month: _lunarMonth,
                day: _lunarDay,
                isLeapMonth: _isLeapMonth,
                onChanged: (newY, newM, newD, newLeap) {
                  setState(() {
                    _lunarYear = newY;
                    _lunarMonth = newM;
                    _lunarDay = newD;
                    _isLeapMonth = newLeap;
                  });
                },
              ),
            ],
            const SizedBox(height: 14),

            // 实时状态看板
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    diffDays >= 0 ? Icons.timer_outlined : Icons.history,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diffDays > 0
                              ? '未来倒数 · 还有 $diffDays 天'
                              : diffDays == 0
                                  ? '就在今天 · 今日到来 🎉'
                                  : '珍贵回忆 · 已过 ${-diffDays} 天',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isLunar
                              ? '农历 ${_isLeapMonth ? "闰" : ""}${LunarInfo.monthNames[_lunarMonth - 1]}${LunarInfo.dayNames[_lunarDay - 1]} · 对应公历 ${effectiveSolarTarget.year}年${effectiveSolarTarget.month}月${effectiveSolarTarget.day}日 星期$weekday'
                              : '${effectiveSolarTarget.year}年${effectiveSolarTarget.month}月${effectiveSolarTarget.day}日 星期$weekday',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 重复与通知配置
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant
                      .withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    title: const Text('每年重复（周年/生日）'),
                    subtitle: Text(
                      _repeat
                          ? (_isLunar
                              ? '每年同一农历日循环倒数（对应公历自动顺延）'
                              : '每年同一公历日循环倒数')
                          : '单次重要时间节点',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    value: _repeat,
                    onChanged: (value) => setState(() => _repeat = value),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                    title: const Text('在今天看板显示'),
                    subtitle: Text(
                      '临近或当天在首页高亮展示',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    value: _showInToday,
                    onChanged: (value) => setState(() => _showInToday = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 底部保存按钮
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('保存', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
