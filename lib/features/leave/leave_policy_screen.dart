import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class LeavePolicyScreen extends StatefulWidget {
  const LeavePolicyScreen({super.key});

  @override
  State<LeavePolicyScreen> createState() => _LeavePolicyScreenState();
}

class _LeavePolicyScreenState extends State<LeavePolicyScreen> {
  static const _months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final _formKey = GlobalKey<FormState>();
  final _carryoverLimit = TextEditingController();
  final Map<int, TextEditingController> _officialAllowanceControllers = {};
  final Map<int, bool> _officialApplicable = {};
  final Map<int, String> _officialAccrualMethod = {};
  final Map<int, bool> _officialMonthlyReset = {};
  final Map<int, bool> _officialAttendanceBased = {};
  final Map<int, TextEditingController> _yellowAllowanceControllers = {};
  final Map<int, bool> _yellowApplicable = {};
  final Map<int, String> _yellowAccrualMethod = {};
  List<Map<String, dynamic>> _officialStaffTypes = const [];
  List<Map<String, dynamic>> _yellowCardTypes = const [];
  int _periodStartMonth = 1;
  bool _countWeekends = true;
  bool _prorateNewHires = false;
  bool _carryoverEnabled = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  String _displayAllowance(Map<String, dynamic> type) {
    final annual = double.tryParse(stringValue(type['annual_allowance_days'])) ?? 0;
    final value = stringValue(type['accrual_method']) == 'monthly' ? annual / 12 : annual;
    return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  }

  @override
  void dispose() {
    _carryoverLimit.dispose();
    for (final controller in _officialAllowanceControllers.values) {
      controller.dispose();
    }
    for (final controller in _yellowAllowanceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await AppScope.of(context).api.get('leave-policy');
      if (!mounted) return;
      final policy = asJsonMap(response);
      final categoryTypes = asJsonList(policy['category_leave_type_allowances']);
      final officialTypes = categoryTypes
          .where((type) => stringValue(type['employment_type']) == 'Official Staff')
          .toList();
      final yellowTypes = categoryTypes
          .where((type) => stringValue(type['employment_type']) == 'Yellow Card')
          .toList();
      for (final controller in _officialAllowanceControllers.values) {
        controller.dispose();
      }
      for (final controller in _yellowAllowanceControllers.values) {
        controller.dispose();
      }
      _officialAllowanceControllers
        ..clear()
        ..addEntries(officialTypes.map((type) {
          final id = int.tryParse(stringValue(type['id'])) ?? 0;
          return MapEntry(id, TextEditingController(text: _displayAllowance(type)));
        }));
      _officialApplicable
        ..clear()
        ..addEntries(officialTypes.map((type) => MapEntry(
              int.tryParse(stringValue(type['id'])) ?? 0,
              _asBool(type['is_applicable']),
            )));
      _officialAccrualMethod
        ..clear()
        ..addEntries(officialTypes.map((type) => MapEntry(
              int.tryParse(stringValue(type['id'])) ?? 0,
              stringValue(type['accrual_method'], fallback: 'annual'),
            )));
      _officialMonthlyReset
        ..clear()
        ..addEntries(officialTypes.map((type) => MapEntry(
              int.tryParse(stringValue(type['id'])) ?? 0,
              _asBool(type['monthly_reset']),
            )));
      _officialAttendanceBased
        ..clear()
        ..addEntries(officialTypes.map((type) => MapEntry(
              int.tryParse(stringValue(type['id'])) ?? 0,
              _asBool(type['attendance_based']),
            )));
      _yellowAllowanceControllers
        ..clear()
        ..addEntries(yellowTypes.map((type) {
          final id = int.tryParse(stringValue(type['id'])) ?? 0;
          return MapEntry(id, TextEditingController(text: stringValue(type['annual_allowance_days'], fallback: '0')));
        }));
      _yellowApplicable
        ..clear()
        ..addEntries(yellowTypes.map((type) => MapEntry(
              int.tryParse(stringValue(type['id'])) ?? 0,
              _asBool(type['is_applicable']),
            )));
      _yellowAccrualMethod
        ..clear()
        ..addEntries(yellowTypes.map((type) => MapEntry(
              int.tryParse(stringValue(type['id'])) ?? 0,
              stringValue(type['accrual_method'], fallback: 'annual'),
            )));
      setState(() {
        _officialStaffTypes = officialTypes;
        _yellowCardTypes = yellowTypes;
        _periodStartMonth = int.tryParse(stringValue(policy['period_start_month'])) ?? 1;
        _countWeekends = _asBool(policy['count_weekends'], fallback: true);
        _prorateNewHires = _asBool(policy['prorate_new_hires']);
        _carryoverEnabled = _asBool(policy['carryover_enabled']);
        _carryoverLimit.text = stringValue(policy['carryover_limit_days'], fallback: '0');
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final categoryAllowances = <Map<String, dynamic>>[];
    for (final type in _officialStaffTypes) {
      final id = int.tryParse(stringValue(type['id']));
      final inputAllowance = double.tryParse(_officialAllowanceControllers[id]?.text.trim() ?? '');
      if (id != null && inputAllowance != null) {
        final accrualMethod = _officialAccrualMethod[id] ?? 'annual';
        final attendanceBased = _officialAttendanceBased[id] ?? false;
        categoryAllowances.add({
          'employment_type': 'Official Staff',
          'id': id,
          'annual_allowance_days': attendanceBased ? 0 : accrualMethod == 'monthly' ? inputAllowance * 12 : inputAllowance,
          'is_applicable': _officialApplicable[id] ?? false,
          'accrual_method': accrualMethod,
          'monthly_reset': accrualMethod == 'monthly' && (_officialMonthlyReset[id] ?? false),
          'attendance_based': attendanceBased,
        });
      }
    }
    for (final type in _yellowCardTypes) {
      final id = int.tryParse(stringValue(type['id']));
      final allowance = double.tryParse(_yellowAllowanceControllers[id]?.text.trim() ?? '');
      if (id != null && allowance != null) {
        categoryAllowances.add({
          'employment_type': 'Yellow Card',
          'id': id,
          'annual_allowance_days': allowance,
          'is_applicable': _yellowApplicable[id] ?? false,
          'accrual_method': _yellowAccrualMethod[id] ?? 'annual',
          'monthly_reset': false,
          'attendance_based': false,
        });
      }
    }
    try {
      await AppScope.of(context).api.patch('leave-policy', {
        'period_start_month': _periodStartMonth,
        'count_weekends': _countWeekends,
        'prorate_new_hires': _prorateNewHires,
        'carryover_enabled': _carryoverEnabled,
        'carryover_limit_days': int.tryParse(_carryoverLimit.text.trim()) ?? 0,
        'category_leave_type_allowances': categoryAllowances,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave policy saved.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeading(
                    title: 'Leave policy',
                    subtitle: 'Configure the leave period and balance rules used across employee dashboards.',
                    trailing: IconButton.filledTonal(
                      onPressed: _loading ? null : _load,
                      tooltip: 'Refresh policy',
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                  if (_error != null) ...[
                    ErrorNotice(message: _error!, onRetry: _load),
                    const SizedBox(height: 14),
                  ],
                  if (_loading && _officialStaffTypes.isEmpty && _yellowCardTypes.isEmpty)
                    const SizedBox(height: 180, child: LoadingView(label: 'Loading leave policy…'))
                  else if (_error != null && _officialStaffTypes.isEmpty && _yellowCardTypes.isEmpty)
                    ErrorNotice(message: _error!, onRetry: _load)
                  else ...[
                    AppPanel(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _PolicySectionHeading(
                            title: 'Leave period',
                            subtitle: 'The period starts on the first day of the selected month and renews annually.',
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                            value: _periodStartMonth,
                            decoration: const InputDecoration(labelText: 'Leave period starts in'),
                            items: List.generate(
                              _months.length,
                              (index) => DropdownMenuItem(value: index + 1, child: Text(_months[index])),
                            ),
                            onChanged: (value) {
                              if (value != null) setState(() => _periodStartMonth = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          _PolicyToggle(
                            title: 'Count weekends as leave days',
                            subtitle: 'When off, Saturdays and Sundays are not deducted from approved leave.',
                            value: _countWeekends,
                            onChanged: (value) => setState(() => _countWeekends = value),
                          ),
                          const Divider(height: 20),
                          _PolicyToggle(
                            title: 'Prorate new-hire allowance',
                            subtitle: 'Calculate an allowance proportionally from the employee start date within the leave period.',
                            value: _prorateNewHires,
                            onChanged: (value) => setState(() => _prorateNewHires = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppPanel(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _PolicySectionHeading(
                            title: 'Carry-over',
                            subtitle: 'Unused allowance from the immediately previous period can be carried forward once.',
                          ),
                          const SizedBox(height: 10),
                          _PolicyToggle(
                            title: 'Allow carry-over',
                            subtitle: 'Adds eligible unused days from the prior period to this period’s balance.',
                            value: _carryoverEnabled,
                            onChanged: (value) => setState(() => _carryoverEnabled = value),
                          ),
                          if (_carryoverEnabled) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _carryoverLimit,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(
                                labelText: 'Maximum carry-over days',
                                helperText: 'Limit applied per leave type (0–365).',
                              ),
                              validator: (value) {
                                final days = int.tryParse(value?.trim() ?? '');
                                return days == null || days > 365 ? 'Enter a whole number from 0 to 365.' : null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppPanel(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _PolicySectionHeading(
                            title: 'Official Staff leave rules',
                            subtitle: 'Default: EL 14/year, SL 14/year, CL 7/year, Short Leave 2 days/month with no monthly carry-over, and Compensatory Leave earned for completed attendance on a scheduled weekly off. Each rule can be configured below.',
                          ),
                          const SizedBox(height: 12),
                          if (_officialStaffTypes.isEmpty)
                            const EmptyNotice(
                              title: 'No Official Staff leave rules found',
                              subtitle: 'Refresh the policy or add active leave types before configuring them.',
                              icon: Icons.event_note_outlined,
                            )
                          else
                            ..._officialStaffTypes.map((type) {
                              final id = int.tryParse(stringValue(type['id'])) ?? 0;
                              return _OfficialStaffAllowanceEditor(
                                type: type,
                                controller: _officialAllowanceControllers[id],
                                applicable: _officialApplicable[id] ?? false,
                                accrualMethod: _officialAccrualMethod[id] ?? 'annual',
                                monthlyReset: _officialMonthlyReset[id] ?? false,
                                attendanceBased: _officialAttendanceBased[id] ?? false,
                                onApplicableChanged: (value) => setState(() => _officialApplicable[id] = value),
                                onAccrualMethodChanged: (value) {
                                  if (value != null) setState(() => _officialAccrualMethod[id] = value);
                                },
                                onMonthlyResetChanged: (value) => setState(() => _officialMonthlyReset[id] = value),
                              );
                            }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppPanel(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _PolicySectionHeading(
                            title: 'Yellow Card Staff (15 EL Only)',
                            subtitle: 'Yellow Card staff members strictly receive 15 Earned Leaves (EL) per year, accrued monthly at 1.25 days per elapsed month. Casual Leaves (CL), Sick Leaves (SL), Optional Holidays, and Short Leaves are not applicable.',
                          ),
                          const SizedBox(height: 12),
                          if (_yellowCardTypes.isEmpty)
                            const EmptyNotice(
                              title: 'No category leave rules found',
                              subtitle: 'Refresh the policy after adding active leave types.',
                              icon: Icons.event_busy_outlined,
                            )
                          else
                            ..._yellowCardTypes.map((type) {
                              final id = int.tryParse(stringValue(type['id'])) ?? 0;
                              return _YellowCardAllowanceEditor(
                                type: type,
                                controller: _yellowAllowanceControllers[id],
                                applicable: _yellowApplicable[id] ?? false,
                                accrualMethod: _yellowAccrualMethod[id] ?? 'annual',
                                onApplicableChanged: (value) => setState(() => _yellowApplicable[id] = value),
                                onAccrualMethodChanged: (value) {
                                  if (value != null) setState(() => _yellowAccrualMethod[id] = value);
                                },
                              );
                            }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.softBlue,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: AppColors.blue, size: 19),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Saved rules are applied to balance calculations immediately. Carry-over is limited to the previous period and the configured cap.',
                              style: TextStyle(color: AppColors.ink, fontSize: 12, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: 'Save leave policy',
                      icon: Icons.check_rounded,
                      busy: _saving,
                      onPressed: _save,
                      expand: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PolicySectionHeading extends StatelessWidget {
  const _PolicySectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
        ],
      );
}

class _PolicyToggle extends StatelessWidget {
  const _PolicyToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      );
}

class _OfficialStaffAllowanceEditor extends StatelessWidget {
  const _OfficialStaffAllowanceEditor({
    required this.type,
    required this.controller,
    required this.applicable,
    required this.accrualMethod,
    required this.monthlyReset,
    required this.attendanceBased,
    required this.onApplicableChanged,
    required this.onAccrualMethodChanged,
    required this.onMonthlyResetChanged,
  });

  final Map<String, dynamic> type;
  final TextEditingController? controller;
  final bool applicable;
  final String accrualMethod;
  final bool monthlyReset;
  final bool attendanceBased;
  final ValueChanged<bool> onApplicableChanged;
  final ValueChanged<String?> onAccrualMethodChanged;
  final ValueChanged<bool> onMonthlyResetChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stringValue(type['name'], fallback: 'Leave type'), style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                !applicable ? 'Not applicable to Official Staff' : attendanceBased ? 'Earned from completed weekly-off attendance' : 'Applicable to Official Staff',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ])),
            Switch.adaptive(value: applicable, onChanged: onApplicableChanged),
          ]),
          if (applicable && attendanceBased)
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text('One day is credited after a completed attendance record on a scheduled weekly off.', style: TextStyle(color: AppColors.blue, fontSize: 11, height: 1.4)),
            ),
          if (applicable && !attendanceBased) ...[
            const SizedBox(height: 7),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: InputDecoration(labelText: accrualMethod == 'monthly' ? 'Days / month' : 'Days / year'),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');
                    final maximum = accrualMethod == 'monthly' ? 305 : 3660;
                    return amount == null || amount < 0 || amount > maximum ? 'Enter 0–$maximum' : null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: accrualMethod,
                  decoration: const InputDecoration(labelText: 'Accrual'),
                  items: const [
                    DropdownMenuItem(value: 'annual', child: Text('Per year')),
                    DropdownMenuItem(value: 'monthly', child: Text('Per month')),
                  ],
                  onChanged: onAccrualMethodChanged,
                ),
              ),
            ]),
            if (accrualMethod == 'monthly')
              _PolicyToggle(
                title: 'Reset unused balance each month',
                subtitle: 'Unused monthly allowance does not roll into the next month.',
                value: monthlyReset,
                onChanged: onMonthlyResetChanged,
              ),
          ],
        ]),
      );
}

class _YellowCardAllowanceEditor extends StatelessWidget {
  const _YellowCardAllowanceEditor({
    required this.type,
    required this.controller,
    required this.applicable,
    required this.accrualMethod,
    required this.onApplicableChanged,
    required this.onAccrualMethodChanged,
  });

  final Map<String, dynamic> type;
  final TextEditingController? controller;
  final bool applicable;
  final String accrualMethod;
  final ValueChanged<bool> onApplicableChanged;
  final ValueChanged<String?> onAccrualMethodChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stringValue(type['name'], fallback: 'Leave type'), style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(applicable ? 'Applicable to Yellow Card staff' : 'Not applicable to Yellow Card staff', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    ],
                  ),
                ),
                Switch.adaptive(value: applicable, onChanged: onApplicableChanged),
              ],
            ),
            if (applicable) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      enabled: applicable,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: const InputDecoration(labelText: 'Days / year'),
                      validator: (value) {
                        final days = double.tryParse(value?.trim() ?? '');
                        return days == null || days < 0 || days > 3660 ? 'Enter 0–3660 days.' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: accrualMethod,
                      decoration: const InputDecoration(labelText: 'Accrual'),
                      items: const [
                        DropdownMenuItem(value: 'annual', child: Text('Annual')),
                        DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                      ],
                      onChanged: onAccrualMethodChanged,
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 20),
          ],
        ),
      );
}

bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}
