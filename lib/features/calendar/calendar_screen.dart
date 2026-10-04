import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<Map<String, dynamic>> _holidays = const [];
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
      final response = await AppScope.of(context).api.get('holidays');
      if (!mounted) return;
      setState(() => _holidays = asJsonList(asJsonMap(response)['items']));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editHoliday([Map<String, dynamic>? holiday]) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _HolidayFormDialog(holiday: holiday),
    );
    if (values == null || !mounted) return;
    try {
      final api = AppScope.of(context).api;
      if (holiday == null) {
        await api.post('holidays', values);
      } else {
        await api.patch('holidays/${holiday['id']}', values);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(holiday == null ? 'Holiday added.' : 'Holiday updated.')),
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _removeHoliday(Map<String, dynamic> holiday) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove holiday?'),
        content: Text('${stringValue(holiday['name'])} will no longer appear in the company calendar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    try {
      await AppScope.of(context).api.delete('holidays/${holiday['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Holiday removed.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = AppScope.of(context).user!.can('calendar.manage');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeading(
                    title: 'Holiday calendar',
                    subtitle: 'Company holidays managed by your HR team.',
                    trailing: canManage
                        ? PrimaryButton(
                            label: 'Add holiday',
                            icon: Icons.add_rounded,
                            onPressed: () => _editHoliday(),
                          )
                        : null,
                  ),
                  if (_error != null && _holidays.isNotEmpty) ...[
                    ErrorNotice(message: _error!, onRetry: _load),
                    const SizedBox(height: 14),
                  ],
                  if (_loading && _holidays.isEmpty)
                    const SizedBox(height: 170, child: LoadingView(label: 'Loading holidays…'))
                  else if (_error != null && _holidays.isEmpty)
                    ErrorNotice(message: _error!, onRetry: _load)
                  else if (_holidays.isEmpty)
                    AppPanel(
                      child: EmptyNotice(
                        title: 'No holidays scheduled',
                        subtitle: canManage
                            ? 'Add the company holiday dates so the team can see what is coming up.'
                            : 'Your HR team has not added any company holidays yet.',
                        icon: Icons.event_available_rounded,
                      ),
                    )
                  else
                    AppPanel(
                      padding: const EdgeInsets.fromLTRB(18, 17, 18, 8),
                      child: Column(
                        children: _holidays
                            .map(
                              (holiday) => _HolidayRow(
                                holiday: holiday,
                                canManage: canManage,
                                onEdit: () => _editHoliday(holiday),
                                onRemove: () => _removeHoliday(holiday),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HolidayRow extends StatelessWidget {
  const _HolidayRow({
    required this.holiday,
    required this.canManage,
    required this.onEdit,
    required this.onRemove,
  });

  final Map<String, dynamic> holiday;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.softBlue,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.event_rounded, color: AppColors.blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stringValue(holiday['name'], fallback: 'Holiday'),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatDate(holiday['holiday_date'])}${stringValue(holiday['description']).isEmpty ? '' : ' · ${stringValue(holiday['description'])}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (canManage) ...[
            const SizedBox(width: 6),
            IconButton(
              onPressed: onEdit,
              tooltip: 'Edit holiday',
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove holiday',
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}

class _HolidayFormDialog extends StatefulWidget {
  const _HolidayFormDialog({this.holiday});

  final Map<String, dynamic>? holiday;

  @override
  State<_HolidayFormDialog> createState() => _HolidayFormDialogState();
}

class _HolidayFormDialogState extends State<_HolidayFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  DateTime? _date;
  bool _dateMissing = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: stringValue(widget.holiday?['name']));
    _description = TextEditingController(text: stringValue(widget.holiday?['description']));
    _date = DateTime.tryParse(stringValue(widget.holiday?['holiday_date']));
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final initial = _date ?? today;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.blue),
        ),
        child: child!,
      ),
    );
    if (selected != null) {
      setState(() {
        _date = selected;
        _dateMissing = false;
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      setState(() => _dateMissing = true);
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'name': _name.text.trim(),
      'holiday_date': '${_date!.year.toString().padLeft(4, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
      'description': _description.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        widget.holiday == null ? 'Add company holiday' : 'Edit company holiday',
        style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800),
      ),
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
                  decoration: const InputDecoration(labelText: 'Holiday name'),
                  validator: (value) => (value?.trim().isEmpty ?? true) ? 'Enter a holiday name' : null,
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date',
                      errorText: _dateMissing ? 'Choose a holiday date' : null,
                      suffixIcon: const Icon(Icons.calendar_month_rounded),
                    ),
                    child: Text(_date == null ? 'Select a date' : formatDate(_date!.toIso8601String())),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _description,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description (optional)'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check_rounded, size: 17),
          label: const Text('Save holiday'),
        ),
      ],
    );
  }
}
