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
  final Map<int, TextEditingController> _allowanceControllers = {};
  List<Map<String, dynamic>> _leaveTypes = const [];
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

  @override
  void dispose() {
    _carryoverLimit.dispose();
    for (final controller in _allowanceControllers.values) {
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
      final types = asJsonList(policy['leave_type_allowances']);
      for (final controller in _allowanceControllers.values) {
        controller.dispose();
      }
      _allowanceControllers
        ..clear()
        ..addEntries(types.map((type) {
          final id = int.tryParse(stringValue(type['id'])) ?? 0;
          return MapEntry(id, TextEditingController(text: stringValue(type['annual_allowance_days'], fallback: '0')));
        }));
      setState(() {
        _leaveTypes = types;
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
    final allowances = <Map<String, dynamic>>[];
    for (final type in _leaveTypes) {
      final id = int.tryParse(stringValue(type['id']));
      final allowance = int.tryParse(_allowanceControllers[id]?.text.trim() ?? '');
      if (id != null && allowance != null) {
        allowances.add({'id': id, 'annual_allowance_days': allowance});
      }
    }
    try {
      await AppScope.of(context).api.patch('leave-policy', {
        'period_start_month': _periodStartMonth,
        'count_weekends': _countWeekends,
        'prorate_new_hires': _prorateNewHires,
        'carryover_enabled': _carryoverEnabled,
        'carryover_limit_days': int.tryParse(_carryoverLimit.text.trim()) ?? 0,
        'leave_type_allowances': allowances,
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
                  if (_loading && _leaveTypes.isEmpty)
                    const SizedBox(height: 180, child: LoadingView(label: 'Loading leave policy…'))
                  else if (_error != null && _leaveTypes.isEmpty)
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
                            title: 'Annual allowances',
                            subtitle: 'Set the annual days available for each active leave type.',
                          ),
                          const SizedBox(height: 12),
                          if (_leaveTypes.isEmpty)
                            const EmptyNotice(
                              title: 'No active leave types',
                              subtitle: 'An administrator can add leave types before configuring allowances.',
                              icon: Icons.event_note_outlined,
                            )
                          else
                            ..._leaveTypes.map((type) => _AllowanceEditor(
                                  type: type,
                                  controller: _allowanceControllers[int.tryParse(stringValue(type['id']))],
                                )),
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

class _AllowanceEditor extends StatelessWidget {
  const _AllowanceEditor({required this.type, required this.controller});

  final Map<String, dynamic> type;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stringValue(type['name'], fallback: 'Leave type'), style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(type['is_paid'] == true ? 'Paid leave' : 'Unpaid leave', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 15),
            SizedBox(
              width: 118,
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.end,
                decoration: const InputDecoration(labelText: 'Days / year', counterText: ''),
                maxLength: 4,
                validator: (value) {
                  final days = int.tryParse(value?.trim() ?? '');
                  return days == null || days > 3660 ? '0–3660' : null;
                },
              ),
            ),
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
