import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _types = const [];
  List<Map<String, dynamic>> _balances = const [];
  List<Map<String, dynamic>> _holidays = const [];
  Map<String, dynamic> _period = const {};
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';
  int? _selectedTypeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<dynamic> _optionalGet(String path) async {
    try {
      return await AppScope.of(context).api.get(path);
    } on ApiException {
      return const <String, dynamic>{};
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = AppScope.of(context).user!;
      final api = AppScope.of(context).api;
      final statusQuery = _statusFilter == 'all' ? null : <String, String>{'status': _statusFilter};
      final responses = await Future.wait<dynamic>([
        api.get('leave-requests', query: statusQuery),
        api.get('leave-types'),
        user.can('dashboard.read') ? _optionalGet('dashboard') : Future<dynamic>.value(const <String, dynamic>{}),
        user.can('calendar.read') ? _optionalGet('holidays') : Future<dynamic>.value(const <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final dashboard = asJsonMap(responses[2]);
      final types = asJsonList(asJsonMap(responses[1])['items']);
      final balances = asJsonList(dashboard['my_leave_balances']);
      final selectedStillAvailable = _selectedTypeId != null &&
          balances.any((balance) => int.tryParse(stringValue(balance['leave_type_id'])) == _selectedTypeId);
      setState(() {
        _requests = asJsonList(asJsonMap(responses[0])['items']);
        _types = types;
        _balances = balances;
        _period = asJsonMap(dashboard['leave_balance_period']);
        _holidays = asJsonList(asJsonMap(responses[3])['items']);
        if (!selectedStillAvailable) {
          _selectedTypeId = int.tryParse(stringValue(types.isEmpty ? null : types.first['id']));
        }
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newRequest() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _LeaveFormDialog(types: _types, initialTypeId: _selectedTypeId),
    );
    if (values == null || !mounted) return;
    try {
      await AppScope.of(context).api.post('leave-requests', values);
      if (!mounted) return;
      setState(() => _statusFilter = 'all');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave request submitted for approval.')),
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _adjustBalance() async {
    final api = AppScope.of(context).api;
    try {
      final response = await api.get('employees');
      if (!mounted) return;
      final employees = asJsonList(asJsonMap(response)['items']);
      if (employees.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No employee records are available for adjustment.')),
        );
        return;
      }
      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _BalanceAdjustmentDialog(
          employees: employees,
          types: _types,
          initialTypeId: _selectedTypeId,
        ),
      );
      if (values == null || !mounted) return;
      await api.post('leave-balance-adjustments', values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave balance adjustment saved.')),
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _selectStatus(String status) async {
    if (_statusFilter == status) return;
    setState(() => _statusFilter = status);
    await _load();
  }

  Map<String, dynamic>? get _selectedBalance {
    for (final balance in _balances) {
      if (int.tryParse(stringValue(balance['leave_type_id'])) == _selectedTypeId) return balance;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedType {
    for (final type in _types) {
      if (int.tryParse(stringValue(type['id'])) == _selectedTypeId) return type;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    final canCreate = user.can('leave.create');
    final canAdjust = user.can('leave.balance.manage');
    final balance = _selectedBalance;
    final selectedType = _selectedType;
    final holidays = _holidays
        .where((holiday) => stringValue(holiday['holiday_date']).compareTo(_todayString()) >= 0)
        .toList()
      ..sort((a, b) => stringValue(a['holiday_date']).compareTo(stringValue(b['holiday_date'])));
    final visibleRequests = _requests.where((request) {
      return _selectedTypeId == null ||
          int.tryParse(stringValue(request['leave_type_id'])) == _selectedTypeId;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1210),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'Leaves',
                  subtitle: 'Balances, requests and upcoming holidays in one place.',
                  trailing: canCreate
                      ? PrimaryButton(
                          label: 'Apply for leave',
                          icon: Icons.add_rounded,
                          onPressed: _newRequest,
                        )
                      : null,
                ),
                if (_error != null) ...[
                  ErrorNotice(message: _error!, onRetry: _load),
                  const SizedBox(height: 14),
                ],
                if (_types.isNotEmpty) ...[
                  _CategoryPicker(
                    types: _types,
                    selectedId: _selectedTypeId,
                    onSelected: (id) => setState(() => _selectedTypeId = id),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_loading && _balances.isEmpty)
                  const AppPanel(
                    child: SizedBox(height: 135, child: LoadingView(label: 'Loading leave balance…')),
                  )
                else if (balance != null)
                  _LeaveBalanceCard(
                    balance: balance,
                    type: selectedType,
                    period: _period,
                    canAdjust: canAdjust,
                    onAdjust: _adjustBalance,
                  )
                else if (_types.isNotEmpty)
                  const AppPanel(
                    child: EmptyNotice(
                      title: 'Balance not linked',
                      subtitle: 'Your employee profile is not linked to a leave balance yet. HR can verify your account mapping.',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  )
                else
                  const AppPanel(
                    child: EmptyNotice(
                      title: 'No leave categories yet',
                      subtitle: 'Active leave categories and their policy rules will appear here.',
                      icon: Icons.event_note_outlined,
                    ),
                  ),
                if (_balances.isNotEmpty) ...[
                  const SizedBox(height: 13),
                  _BalanceStats(balance: balance ?? const <String, dynamic>{}),
                ],
                if (holidays.isNotEmpty) ...[
                  const SizedBox(height: 23),
                  _UpcomingHolidays(holidays: holidays.take(3).toList()),
                ],
                const SizedBox(height: 24),
                PageHeading(
                  title: 'Request history',
                  subtitle: 'Track decisions and review your leave applications.',
                  trailing: Text(
                    '${visibleRequests.length} ${visibleRequests.length == 1 ? 'request' : 'requests'}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusFilter(selected: _statusFilter, onSelected: _selectStatus),
                const SizedBox(height: 12),
                if (_loading && _requests.isEmpty)
                  const AppPanel(child: SizedBox(height: 140, child: LoadingView(label: 'Loading requests…')))
                else if (visibleRequests.isEmpty)
                  AppPanel(
                    child: EmptyNotice(
                      title: _statusFilter == 'all' ? 'No leave requests yet' : 'No $_statusFilter requests',
                      subtitle: 'New applications and their approval status will show here.',
                      icon: Icons.event_available_outlined,
                    ),
                  )
                else
                  AppPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 7),
                    child: Column(
                      children: [
                        for (var index = 0; index < visibleRequests.length; index++) ...[
                          _LeaveRequestRow(
                            request: visibleRequests[index],
                            showEmployee: user.canAny(const ['leave.read', 'leave.read.team', 'leave.manage']),
                          ),
                          if (index < visibleRequests.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.types, required this.selectedId, required this.onSelected});
  final List<Map<String, dynamic>> types;
  final int? selectedId;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(right: 13),
              child: Text('CATEGORY', style: TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
            for (final type in types) ...[
              ChoiceChip(
                label: Text(stringValue(type['name'], fallback: 'Leave')),
                selected: int.tryParse(stringValue(type['id'])) == selectedId,
                onSelected: (_) => onSelected(int.tryParse(stringValue(type['id']))),
                selectedColor: AppColors.softBlue,
                labelStyle: TextStyle(
                  color: int.tryParse(stringValue(type['id'])) == selectedId ? AppColors.blue : AppColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                side: BorderSide(color: int.tryParse(stringValue(type['id'])) == selectedId ? AppColors.blue.withValues(alpha: .28) : AppColors.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _LeaveBalanceCard extends StatelessWidget {
  const _LeaveBalanceCard({
    required this.balance,
    required this.type,
    required this.period,
    required this.canAdjust,
    required this.onAdjust,
  });
  final Map<String, dynamic> balance;
  final Map<String, dynamic>? type;
  final Map<String, dynamic> period;
  final bool canAdjust;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final available = _number(balance['remaining_days']);
    final allowance = _number(balance['allowance_days']);
    final progress = allowance <= 0 ? 0.0 : (available / allowance).clamp(0.0, 1.0).toDouble();
    final paid = type?['is_paid'] == true || type?['is_paid'] == 1;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, Color(0xFF153D64), Color(0xFF087A7C)],
        ),
        boxShadow: const [BoxShadow(color: Color(0x18152B43), blurRadius: 22, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(stringValue(balance['leave_type'], fallback: 'Leave balance'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 6),
                  Text(stringValue(period['label'], fallback: 'Current leave period'), style: const TextStyle(color: Color(0xFFB9CDD9), fontSize: 11)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
                child: Text(paid ? 'PAID' : 'UNPAID', style: const TextStyle(color: Color(0xFFD6F7EC), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .8)),
              ),
            ],
          ),
          const SizedBox(height: 21),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_days(available), style: const TextStyle(color: Colors.white, fontSize: 43, height: 1, fontWeight: FontWeight.w800, letterSpacing: -1.5)),
            const Padding(padding: EdgeInsets.only(left: 8, bottom: 5), child: Text('days available', style: TextStyle(color: Color(0xFFC4D5E0), fontSize: 12))),
            const Spacer(),
            if (canAdjust)
              TextButton.icon(
                onPressed: onAdjust,
                style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white.withValues(alpha: .12)),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Adjust', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: .16),
              color: const Color(0xFF64DEC4),
            ),
          ),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(child: Text('${_days(available)} of ${_days(allowance)} days remaining', style: const TextStyle(color: Color(0xFFC4D5E0), fontSize: 10))),
            Text('${formatDate(period['start_date'])} – ${formatDate(period['end_date'])}', style: const TextStyle(color: Color(0xFFC4D5E0), fontSize: 10)),
          ]),
          if (stringValue(period['policy_summary']).isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFF9AE9D7), size: 16),
              const SizedBox(width: 7),
              Expanded(child: Text(stringValue(period['policy_summary']), style: const TextStyle(color: Color(0xFFD3E2E8), fontSize: 10, height: 1.4))),
            ]),
          ],
        ],
      ),
    );
  }
}

class _BalanceStats extends StatelessWidget {
  const _BalanceStats({required this.balance});
  final Map<String, dynamic> balance;

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String, String, IconData, Color)>[
      ('Accrued', _days(_number(balance['accrued_days'], fallback: _number(balance['base_allowance_days']))), 'Granted this period', Icons.savings_outlined, AppColors.blue),
      ('Used', _days(_number(balance['used_days'])), 'Approved leave days', Icons.event_busy_outlined, const Color(0xFFAE751C)),
      ('Remaining', _days(_number(balance['remaining_days'])), 'Available to request', Icons.event_available_outlined, AppColors.success),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final stat in stats)
            SizedBox(
              width: constraints.maxWidth >= 760 ? (constraints.maxWidth - 20) / 3 : width,
              child: StatCard(title: stat.$1, value: stat.$2, footnote: stat.$3, icon: stat.$4, tint: stat.$5),
            ),
        ],
      );
    });
  }
}

class _UpcomingHolidays extends StatelessWidget {
  const _UpcomingHolidays({required this.holidays});
  final List<Map<String, dynamic>> holidays;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHeading(title: 'Upcoming holidays', subtitle: 'Company holidays close to your current leave period.'),
      AppPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Column(children: [
          for (var index = 0; index < holidays.length; index++) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.celebration_outlined, color: AppColors.blue, size: 19)),
              title: Text(stringValue(holidays[index]['name'], fallback: 'Company holiday'), style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)),
              subtitle: Text(formatDate(holidays[index]['holiday_date']), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 18),
              dense: true,
            ),
            if (index < holidays.length - 1) const Divider(height: 1),
          ],
        ]),
      ),
    ]);
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = ['all', 'pending', 'approved', 'rejected'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final filter in filters) ...[
          ChoiceChip(
            label: Text(filter == 'all' ? 'All requests' : _titleCase(filter)),
            selected: selected == filter,
            onSelected: (_) => onSelected(filter),
            selectedColor: AppColors.softBlue,
            labelStyle: TextStyle(color: selected == filter ? AppColors.blue : AppColors.ink, fontSize: 11, fontWeight: FontWeight.w700),
            side: BorderSide(color: selected == filter ? AppColors.blue.withValues(alpha: .28) : AppColors.line),
          ),
          const SizedBox(width: 8),
        ],
      ]),
    );
  }
}

class _LeaveRequestRow extends StatelessWidget {
  const _LeaveRequestRow({required this.request, required this.showEmployee});
  final Map<String, dynamic> request;
  final bool showEmployee;

  @override
  Widget build(BuildContext context) {
    final range = '${formatDate(request['start_date'])} – ${formatDate(request['end_date'])}';
    final days = _inclusiveDays(request['start_date'], request['end_date']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.event_note_rounded, color: AppColors.blue, size: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stringValue(request['leave_type'], fallback: 'Leave request'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(showEmployee ? '${stringValue(request['employee_name'])} · $range' : range, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            if (stringValue(request['reason']).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(stringValue(request['reason']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          StatusBadge(status: stringValue(request['status'], fallback: 'pending')),
          const SizedBox(height: 5),
          Text('$days ${days == 1 ? 'day' : 'days'}', style: const TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class _LeaveFormDialog extends StatefulWidget {
  const _LeaveFormDialog({required this.types, this.initialTypeId});
  final List<Map<String, dynamic>> types;
  final int? initialTypeId;

  @override
  State<_LeaveFormDialog> createState() => _LeaveFormDialogState();
}

class _LeaveFormDialogState extends State<_LeaveFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  int? _typeId;
  DateTime? _start;
  DateTime? _end;
  bool _datesInvalid = false;

  @override
  void initState() {
    super.initState();
    _typeId = widget.initialTypeId ??
        (widget.types.isEmpty ? null : int.tryParse(stringValue(widget.types.first['id'])));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final initial = DateUtils.dateOnly((start ? _start : _end) ?? _start ?? today);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: DateTime(today.year + 3),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.blue)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _start = picked;
          if (_end != null && _end!.isBefore(picked)) _end = picked;
        } else {
          _end = picked;
        }
        _datesInvalid = false;
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_start == null || _end == null || _typeId == null) {
      setState(() => _datesInvalid = true);
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'leave_type_id': _typeId,
      'start_date': _dateString(_start!),
      'end_date': _dateString(_end!),
      'reason': _reason.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
      title: const Text('Apply for leave', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 450,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: _typeId,
              decoration: const InputDecoration(labelText: 'Leave category'),
              items: widget.types.map((type) => DropdownMenuItem(value: int.tryParse(stringValue(type['id'])), child: Text(stringValue(type['name'])))).toList(),
              onChanged: (value) => setState(() => _typeId = value),
              validator: (value) => value == null ? 'Choose a leave category' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _DatePickerField(label: 'From', value: _start, onTap: () => _pickDate(start: true))),
              const SizedBox(width: 12),
              Expanded(child: _DatePickerField(label: 'To', value: _end, onTap: () => _pickDate(start: false))),
            ]),
            if (_datesInvalid) const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(top: 6), child: Text('Choose a start and end date.', style: TextStyle(color: Color(0xFFC94D54), fontSize: 11)))),
            const SizedBox(height: 12),
            TextFormField(controller: _reason, minLines: 3, maxLines: 4, decoration: const InputDecoration(labelText: 'Reason', hintText: 'Add a little context for your approver'), validator: (value) => (value?.trim().isEmpty ?? true) ? 'A reason is required' : null),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(onPressed: widget.types.isEmpty ? null : _submit, icon: const Icon(Icons.send_rounded, size: 17), label: const Text('Submit request')),
      ],
    );
  }
}

class _BalanceAdjustmentDialog extends StatefulWidget {
  const _BalanceAdjustmentDialog({required this.employees, required this.types, this.initialTypeId});
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> types;
  final int? initialTypeId;

  @override
  State<_BalanceAdjustmentDialog> createState() => _BalanceAdjustmentDialogState();
}

class _BalanceAdjustmentDialogState extends State<_BalanceAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _days = TextEditingController();
  final _reason = TextEditingController();
  int? _employeeId;
  int? _typeId;

  @override
  void initState() {
    super.initState();
    _employeeId = int.tryParse(stringValue(widget.employees.isEmpty ? null : widget.employees.first['id']));
    _typeId = widget.initialTypeId ?? (widget.types.isEmpty ? null : int.tryParse(stringValue(widget.types.first['id'])));
  }

  @override
  void dispose() {
    _days.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate() || _employeeId == null || _typeId == null) return;
    Navigator.pop(context, <String, dynamic>{
      'employee_id': _employeeId,
      'leave_type_id': _typeId,
      'days': double.parse(_days.text.trim()),
      'reason': _reason.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text('Adjust leave balance', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 450,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: _employeeId,
              decoration: const InputDecoration(labelText: 'Employee'),
              items: widget.employees.map((employee) => DropdownMenuItem(value: int.tryParse(stringValue(employee['id'])), child: Text('${stringValue(employee['full_name'])} · ${stringValue(employee['employee_code'])}'))).toList(),
              onChanged: (value) => setState(() => _employeeId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _typeId,
              decoration: const InputDecoration(labelText: 'Leave category'),
              items: widget.types.map((type) => DropdownMenuItem(value: int.tryParse(stringValue(type['id'])), child: Text(stringValue(type['name'])))).toList(),
              onChanged: (value) => setState(() => _typeId = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _days,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Days to add or subtract', hintText: 'For example: 2 or -1'),
              validator: (value) {
                final days = double.tryParse(value?.trim() ?? '');
                if (days == null || days == 0 || days.abs() > 365) return 'Enter a non-zero amount up to 365 days';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _reason, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason'), validator: (value) => (value?.trim().isEmpty ?? true) ? 'Reason is required' : null),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(onPressed: widget.employees.isEmpty || widget.types.isEmpty ? null : _submit, icon: const Icon(Icons.check_rounded, size: 17), label: const Text('Save adjustment')),
      ],
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_month_outlined, size: 19)),
        child: Text(value == null ? 'Select date' : _dateString(value!), style: TextStyle(color: value == null ? AppColors.muted : AppColors.ink, fontSize: 12)),
      ),
    );
  }
}

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _todayString() => _dateString(DateTime.now());

int _inclusiveDays(Object? startValue, Object? endValue) {
  final start = DateTime.tryParse(stringValue(startValue));
  final end = DateTime.tryParse(stringValue(endValue));
  if (start == null || end == null) return 1;
  return end.difference(start).inDays + 1;
}

double _number(Object? value, {double fallback = 0}) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? fallback;

String _days(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

String _titleCase(String value) => value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
