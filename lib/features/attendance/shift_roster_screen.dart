import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ShiftRosterScreen extends StatefulWidget {
  const ShiftRosterScreen({super.key});

  @override
  State<ShiftRosterScreen> createState() => _ShiftRosterScreenState();
}

class _ShiftRosterScreenState extends State<ShiftRosterScreen> {
  DateTime _date = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  List<Map<String, dynamic>> _assignments = const [];
  List<Map<String, dynamic>> _templates = const [];
  List<Map<String, dynamic>> _employees = const [];
  List<Map<String, dynamic>> _locations = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = AppScope.of(context);
      final canManage = controller.user!.can('shifts.manage');
      final requests = <Future<dynamic>>[
        controller.api.get('shift-templates'),
        controller.api.get('shift-assignments', query: {'date': _dateKey(_date)}),
      ];
      if (canManage) {
        requests.add(controller.api.get('employees'));
        requests.add(controller.api.get('locations'));
      }
      final responses = await Future.wait(requests);
      if (!mounted) return;
      setState(() {
        _templates = asJsonList(asJsonMap(responses[0])['items']);
        _assignments = asJsonList(asJsonMap(responses[1])['items']);
        if (canManage) {
          _employees = asJsonList(asJsonMap(responses[2])['items']);
          _locations = asJsonList(asJsonMap(responses[3])['items']);
        }
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editTemplate([Map<String, dynamic>? template]) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ShiftTemplateDialog(template: template),
    );
    if (values == null || !mounted) return;
    try {
      final api = AppScope.of(context).api;
      if (template == null) {
        await api.post('shift-templates', values);
      } else {
        await api.patch('shift-templates/${template['id']}', values);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(template == null ? 'Shift template added.' : 'Shift template updated.')),
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _deactivateTemplate(Map<String, dynamic> template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate shift template?'),
        content: Text('${stringValue(template['name'])} will no longer be available for new assignments.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deactivate')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await AppScope.of(context).api.delete('shift-templates/${template['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift template deactivated.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _activateTemplate(Map<String, dynamic> template) async {
    try {
      await AppScope.of(context).api.patch('shift-templates/${template['id']}', {'is_active': true});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift template reactivated.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _assignShift() async {
    final activeEmployees = _employees.where((employee) => employee['status'] != 'inactive').toList();
    final activeTemplates = _templates.where((template) => _isActive(template['is_active'])).toList();
    final activeLocations = _locations.where((location) => _isActive(location['is_active'])).toList();
    if (activeEmployees.isEmpty || activeTemplates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an active employee and shift template before assigning a shift.')),
      );
      return;
    }
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ShiftAssignmentDialog(
        employees: activeEmployees,
        templates: activeTemplates,
        locations: activeLocations,
        initialDate: _date,
      ),
    );
    if (values == null || !mounted) return;
    try {
      await AppScope.of(context).api.post('shift-assignments', values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift assigned.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _removeAssignment(Map<String, dynamic> assignment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove shift assignment?'),
        content: Text('${stringValue(assignment['employee_name'])} will be removed from this shift.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await AppScope.of(context).api.delete('shift-assignments/${assignment['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift assignment removed.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.blue),
        ),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _date = DateTime(selected.year, selected.month, selected.day));
    await _load();
  }

  Future<void> _moveDate(int offset) async {
    setState(() => _date = _date.add(Duration(days: offset)));
    await _load();
  }

  Future<void> _goToToday() async {
    final now = DateTime.now();
    setState(() => _date = DateTime(now.year, now.month, now.day));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = AppScope.of(context).user!.can('shifts.manage');
    final visibleTemplates = _templates.where((template) => _isActive(template['is_active'])).toList();
    final allTemplates = _templates;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'Shift roster',
                  subtitle: 'Date-based team schedules and assigned work sites.',
                ),
                _RosterDateBar(
                  date: _date,
                  onPrevious: () => _moveDate(-1),
                  onNext: () => _moveDate(1),
                  onPickDate: _chooseDate,
                  onToday: _goToToday,
                ),
                if (canManage) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _editTemplate(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Shift template'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PrimaryButton(
                          label: 'Assign shift',
                          icon: Icons.assignment_ind_outlined,
                          onPressed: visibleTemplates.isEmpty ? null : _assignShift,
                          expand: true,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_error != null && _assignments.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ErrorNotice(message: _error!, onRetry: _load),
                ],
                const SizedBox(height: 14),
                if (_loading && _assignments.isEmpty)
                  const SizedBox(height: 145, child: LoadingView(label: 'Loading the shift roster…'))
                else if (_error != null && _assignments.isEmpty)
                  ErrorNotice(message: _error!, onRetry: _load)
                else if (_assignments.isEmpty)
                  const AppPanel(
                    child: EmptyNotice(
                      title: 'No shifts assigned for this date',
                      subtitle: 'When a shift is scheduled for your visible team, it will appear here.',
                      icon: Icons.schedule_rounded,
                    ),
                  )
                else
                  AppPanel(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                    child: Column(
                      children: _assignments
                          .map(
                            (assignment) => _ShiftAssignmentRow(
                              assignment: assignment,
                              canManage: canManage,
                              onRemove: () => _removeAssignment(assignment),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                if (canManage) ...[
                  const SizedBox(height: 22),
                  PageHeading(
                    title: 'Shift templates',
                    subtitle: 'Saved time ranges available for date-based assignments.',
                  ),
                  if (allTemplates.isEmpty)
                    const AppPanel(
                      child: EmptyNotice(
                        title: 'No shift templates yet',
                        subtitle: 'Add a template, then assign it to an employee for a date.',
                        icon: Icons.schedule_rounded,
                      ),
                    )
                  else
                    AppPanel(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                      child: Column(
                        children: allTemplates
                            .map((template) {
                              final active = _isActive(template['is_active']);
                              return _ShiftTemplateRow(
                                template: template,
                                isActive: active,
                                onEdit: () => _editTemplate(template),
                                onToggleActive: active
                                    ? () => _deactivateTemplate(template)
                                    : () => _activateTemplate(template),
                              );
                            })
                            .toList(growable: false),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RosterDateBar extends StatelessWidget {
  const _RosterDateBar({
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
    required this.onToday,
  });

  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickDate;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          IconButton(onPressed: onPrevious, tooltip: 'Previous date', icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: TextButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(formatDate(_dateKey(date)), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          IconButton(onPressed: onNext, tooltip: 'Next date', icon: const Icon(Icons.chevron_right_rounded)),
          if (!isToday)
            TextButton(onPressed: onToday, child: const Text('Today')),
        ],
      ),
    );
  }
}

class _ShiftAssignmentRow extends StatelessWidget {
  const _ShiftAssignmentRow({
    required this.assignment,
    required this.canManage,
    required this.onRemove,
  });

  final Map<String, dynamic> assignment;
  final bool canManage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final site = stringValue(assignment['location_name']);
    final start = stringValue(assignment['start_time'], fallback: '—');
    final end = stringValue(assignment['end_time'], fallback: '—');
    final breakMinutes = int.tryParse(stringValue(assignment['break_minutes'])) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.schedule_rounded, color: AppColors.blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stringValue(assignment['employee_name'], fallback: 'Team member')} · ${stringValue(assignment['shift_name'], fallback: 'Shift')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '$start–$end · ${breakMinutes}m break${site.isEmpty ? '' : ' · $site'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (canManage)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove assignment',
              icon: const Icon(Icons.person_remove_alt_1_outlined, size: 19),
            ),
        ],
      ),
    );
  }
}

class _ShiftTemplateRow extends StatelessWidget {
  const _ShiftTemplateRow({
    required this.template,
    required this.isActive,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Map<String, dynamic> template;
  final bool isActive;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final breakMinutes = int.tryParse(stringValue(template['break_minutes'])) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.access_time_rounded, color: AppColors.teal, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stringValue(template['name']), style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('${stringValue(template['start_time'])}–${stringValue(template['end_time'])} · ${breakMinutes}m break', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          StatusBadge(status: isActive ? 'active' : 'inactive'),
          IconButton(onPressed: onEdit, tooltip: 'Edit template', icon: const Icon(Icons.edit_outlined, size: 18)),
          IconButton(
            onPressed: onToggleActive,
            tooltip: isActive ? 'Deactivate template' : 'Reactivate template',
            icon: Icon(isActive ? Icons.do_not_disturb_on_outlined : Icons.restart_alt_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _ShiftTemplateDialog extends StatefulWidget {
  const _ShiftTemplateDialog({this.template});

  final Map<String, dynamic>? template;

  @override
  State<_ShiftTemplateDialog> createState() => _ShiftTemplateDialogState();
}

class _ShiftTemplateDialogState extends State<_ShiftTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _breakMinutes;
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _timeMissing = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: stringValue(widget.template?['name']));
    _breakMinutes = TextEditingController(text: stringValue(widget.template?['break_minutes'], fallback: '0'));
    _start = _parseTime(stringValue(widget.template?['start_time']));
    _end = _parseTime(stringValue(widget.template?['end_time']));
  }

  @override
  void dispose() {
    _name.dispose();
    _breakMinutes.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool start}) async {
    final initial = (start ? _start : _end) ?? TimeOfDay.now();
    final selected = await showTimePicker(context: context, initialTime: initial);
    if (selected != null) {
      setState(() {
        if (start) {
          _start = selected;
        } else {
          _end = selected;
        }
        _timeMissing = false;
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_start == null || _end == null) {
      setState(() => _timeMissing = true);
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'name': _name.text.trim(),
      'start_time': _timeKey(_start!),
      'end_time': _timeKey(_end!),
      'break_minutes': int.tryParse(_breakMinutes.text.trim()) ?? 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(widget.template == null ? 'Add shift template' : 'Edit shift template'),
      content: SizedBox(
        width: 430,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              TextFormField(
                controller: _name,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Shift name'),
                validator: (value) => (value?.trim().isEmpty ?? true) ? 'Enter a shift name' : null,
              ),
              Row(
                children: [
                  Expanded(child: _TimePickerField(label: 'Starts', time: _start, onTap: () => _pickTime(start: true))),
                  const SizedBox(width: 12),
                  Expanded(child: _TimePickerField(label: 'Ends', time: _end, onTap: () => _pickTime(start: false))),
                ],
              ),
              if (_timeMissing)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Choose start and end times.', style: TextStyle(color: Color(0xFFC94D54), fontSize: 11)),
                  ),
                ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _breakMinutes,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Break (minutes)'),
                validator: (value) {
                  final minutes = int.tryParse(value?.trim() ?? '');
                  return minutes == null || minutes > 600 ? 'Enter 0 to 600 minutes' : null;
                },
              ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded, size: 17), label: const Text('Save template')),
      ],
    );
  }
}

class _TimePickerField extends StatelessWidget {
  const _TimePickerField({required this.label, required this.time, required this.onTap});

  final String label;
  final TimeOfDay? time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.access_time_rounded)),
          child: Text(time == null ? 'Select time' : _timeKey(time!)),
        ),
      );
}

class _ShiftAssignmentDialog extends StatefulWidget {
  const _ShiftAssignmentDialog({
    required this.employees,
    required this.templates,
    required this.locations,
    required this.initialDate,
  });

  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> templates;
  final List<Map<String, dynamic>> locations;
  final DateTime initialDate;

  @override
  State<_ShiftAssignmentDialog> createState() => _ShiftAssignmentDialogState();
}

class _ShiftAssignmentDialogState extends State<_ShiftAssignmentDialog> {
  final _formKey = GlobalKey<FormState>();
  int? _employeeId;
  int? _shiftId;
  int? _locationId;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    if (widget.employees.isNotEmpty) _employeeId = int.tryParse(stringValue(widget.employees.first['id']));
    if (widget.templates.isNotEmpty) _shiftId = int.tryParse(stringValue(widget.templates.first['id']));
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null) {
      setState(() => _date = selected);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_employeeId == null || _shiftId == null) return;
    Navigator.pop(context, <String, dynamic>{
      'employee_id': _employeeId,
      'shift_id': _shiftId,
      'work_date': _dateKey(_date),
      'work_location_id': _locationId,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text('Assign shift'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: _employeeId,
                  decoration: const InputDecoration(labelText: 'Employee'),
                  items: widget.employees.map((employee) => DropdownMenuItem<int>(
                    value: int.tryParse(stringValue(employee['id'])),
                    child: Text('${stringValue(employee['full_name'], fallback: 'Team member')} · ${stringValue(employee['employee_code'])}', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (value) => setState(() => _employeeId = value),
                  validator: (value) => value == null ? 'Choose an employee' : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: _shiftId,
                  decoration: const InputDecoration(labelText: 'Shift template'),
                  items: widget.templates.map((template) => DropdownMenuItem<int>(
                    value: int.tryParse(stringValue(template['id'])),
                    child: Text('${stringValue(template['name'])} · ${stringValue(template['start_time'])}–${stringValue(template['end_time'])}', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (value) => setState(() => _shiftId = value),
                  validator: (value) => value == null ? 'Choose a shift template' : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  value: _locationId,
                  decoration: const InputDecoration(labelText: 'Work location (optional)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No specific location')),
                    ...widget.locations.map((location) => DropdownMenuItem<int?>(
                      value: int.tryParse(stringValue(location['id'])),
                      child: Text(stringValue(location['name']), overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (value) => setState(() => _locationId = value),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Work date',
                      suffixIcon: Icon(Icons.calendar_month_rounded),
                    ),
                    child: Text(formatDate(_dateKey(_date))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.assignment_turned_in_outlined, size: 17), label: const Text('Assign')),
      ],
    );
  }
}

TimeOfDay? _parseTime(String raw) {
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

String _timeKey(TimeOfDay time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

bool _isActive(Object? value) => value == true || value == 1;
