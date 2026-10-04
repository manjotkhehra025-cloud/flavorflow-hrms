import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _employees = const [];
  bool _loading = true;
  String? _error;
  String? _savingMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _searchController.text.trim();
      final response = await AppScope.of(context).api.get(
        'employees',
        query: query.isEmpty ? null : {'q': query},
      );
      if (!mounted) return;
      setState(() => _employees = asJsonList(asJsonMap(response)['items']));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editEmployee([Map<String, dynamic>? employee]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EmployeeFormDialog(employee: employee, employees: _employees),
    );
    if (result == null || !mounted) return;
    try {
      setState(() => _savingMessage = employee == null ? 'Adding employee…' : 'Saving employee…');
      final api = AppScope.of(context).api;
      if (employee == null) {
        await api.post('employees', result);
      } else {
        await api.patch('employees/${employee['id']}', result);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(employee == null ? 'Employee added.' : 'Employee updated.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _savingMessage = null);
    }
  }

  Future<void> _deactivateEmployee(Map<String, dynamic> employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Deactivate employee?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('${stringValue(employee['full_name'])} will be marked inactive. Attendance history will be retained.', style: const TextStyle(color: AppColors.muted, height: 1.45)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC94D54)), child: const Text('Deactivate'))],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppScope.of(context).api.delete('employees/${employee['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee deactivated.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _showProfile(Map<String, dynamic> employee) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(children: [PersonAvatar(name: stringValue(employee['full_name']), size: 46), const SizedBox(width: 13), Expanded(child: Text(stringValue(employee['full_name']), style: const TextStyle(fontWeight: FontWeight.w800)))]),
        content: SizedBox(
          width: 410,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileLine(label: 'Employee ID', value: stringValue(employee['employee_code'])),
              _ProfileLine(label: 'Role', value: stringValue(employee['title'])),
              _ProfileLine(label: 'Department', value: stringValue(employee['department'])),
              _ProfileLine(label: 'Email', value: stringValue(employee['email'])),
              _ProfileLine(label: 'Start date', value: formatDate(employee['start_date'])),
              _ProfileLine(label: 'Status', value: stringValue(employee['status'])),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          if (AppScope.of(context).user!.can('employees.delete'))
            TextButton.icon(onPressed: () { Navigator.pop(context); _deactivateEmployee(employee); }, icon: const Icon(Icons.person_off_outlined, size: 17), label: const Text('Deactivate')),
          if (AppScope.of(context).user!.can('employees.update'))
            ElevatedButton.icon(onPressed: () { Navigator.pop(context); _editEmployee(employee); }, icon: const Icon(Icons.edit_outlined, size: 17), label: const Text('Edit profile')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    final canCreate = user.can('employees.create');
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'Employees',
                  subtitle: 'Your people directory, all in one place.',
                  trailing: canCreate ? PrimaryButton(label: 'Add employee', icon: Icons.person_add_alt_1_rounded, onPressed: () => _editEmployee()) : null,
                ),
                AppPanel(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: AppColors.muted, size: 21),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _load(),
                          decoration: const InputDecoration(hintText: 'Search name, team, role, or employee ID', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.zero),
                        ),
                      ),
                      IconButton(onPressed: _load, tooltip: 'Search employees', icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.blue)),
                    ],
                  ),
                ),
                if (_savingMessage != null) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: null, borderRadius: BorderRadius.circular(8)),
                ],
                const SizedBox(height: 17),
                if (_loading && _employees.isEmpty)
                  const SizedBox(height: 210, child: LoadingView(label: 'Loading employee directory…'))
                else if (_error != null && _employees.isEmpty)
                  ErrorNotice(message: _error!, onRetry: _load)
                else if (_employees.isEmpty)
                  const AppPanel(child: EmptyNotice(title: 'No employees found', subtitle: 'Try another search or add a new employee.', icon: Icons.groups_2_outlined))
                else
                  AppPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(7, 3, 8, 12),
                          child: LayoutBuilder(builder: (context, constraints) {
                            if (constraints.maxWidth < 670) return const SizedBox.shrink();
                            return const Row(children: [Expanded(flex: 4, child: _TableLabel('EMPLOYEE')), Expanded(flex: 3, child: _TableLabel('DEPARTMENT')), Expanded(flex: 2, child: _TableLabel('START DATE')), SizedBox(width: 92, child: _TableLabel('STATUS')), SizedBox(width: 36)]);
                          }),
                        ),
                        const Divider(height: 1),
                        ..._employees.map((employee) => _EmployeeRow(
                              employee: employee,
                              onTap: () => _showProfile(employee),
                            )),
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

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.employee, required this.onTap});
  final Map<String, dynamic> employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = stringValue(employee['full_name'], fallback: 'Team member');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 670;
            final identity = Row(children: [PersonAvatar(name: name, size: 42), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text('${stringValue(employee['employee_code'])} · ${stringValue(employee['title'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11))]))]);
            if (!wide) {
              return Row(children: [Expanded(child: identity), const SizedBox(width: 9), StatusBadge(status: stringValue(employee['status'], fallback: 'active')), const SizedBox(width: 5), const Icon(Icons.chevron_right_rounded, color: AppColors.muted)]);
            }
            return Row(children: [Expanded(flex: 4, child: identity), Expanded(flex: 3, child: Text(stringValue(employee['department']), style: const TextStyle(color: AppColors.ink, fontSize: 12))), Expanded(flex: 2, child: Text(formatDate(employee['start_date']), style: const TextStyle(color: AppColors.muted, fontSize: 12))), SizedBox(width: 92, child: StatusBadge(status: stringValue(employee['status'], fallback: 'active'))), const SizedBox(width: 36, child: Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20))]);
          },
        ),
      ),
    );
  }
}

class _TableLabel extends StatelessWidget {
  const _TableLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.9));
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 105, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))), Expanded(child: Text(value, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w600)))]));
}

class _EmployeeFormDialog extends StatefulWidget {
  const _EmployeeFormDialog({this.employee, required this.employees});
  final Map<String, dynamic>? employee;
  final List<Map<String, dynamic>> employees;

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _email;
  late final TextEditingController _department;
  late final TextEditingController _title;
  late final TextEditingController _startDate;
  late final TextEditingController _employmentType;
  late String _status;
  int? _managerId;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee ?? const <String, dynamic>{};
    _code = TextEditingController(text: stringValue(employee['employee_code']));
    _first = TextEditingController(text: stringValue(employee['first_name']));
    _last = TextEditingController(text: stringValue(employee['last_name']));
    _email = TextEditingController(text: stringValue(employee['email']));
    _department = TextEditingController(text: stringValue(employee['department']));
    _title = TextEditingController(text: stringValue(employee['title']));
    _startDate = TextEditingController(text: stringValue(employee['start_date'], fallback: DateTime.now().toIso8601String().substring(0, 10)));
    _employmentType = TextEditingController(text: stringValue(employee['employment_type'], fallback: 'Full-time'));
    _status = stringValue(employee['status'], fallback: 'active');
    _managerId = int.tryParse(stringValue(employee['manager_id']));
  }

  @override
  void dispose() {
    for (final controller in [_code, _first, _last, _email, _department, _title, _startDate, _employmentType]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{
      'employee_code': _code.text.trim(),
      'first_name': _first.text.trim(),
      'last_name': _last.text.trim(),
      'email': _email.text.trim(),
      'department': _department.text.trim(),
      'title': _title.text.trim(),
      'start_date': _startDate.text.trim(),
      'employment_type': _employmentType.text.trim(),
      'status': _status,
      'manager_id': _managerId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.employee != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
      title: Text(editing ? 'Update employee' : 'Add employee', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
      content: SizedBox(
        width: 510,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Row(children: [Expanded(child: _field('Employee ID', _code)), const SizedBox(width: 12), Expanded(child: _field('Department', _department))]),
                Row(children: [Expanded(child: _field('First name', _first)), const SizedBox(width: 12), Expanded(child: _field('Last name', _last))]),
                _field('Work email', _email, keyboardType: TextInputType.emailAddress),
                Row(children: [Expanded(child: _field('Job title', _title)), const SizedBox(width: 12), Expanded(child: _field('Employment type', _employmentType))]),
                Row(
                  children: [
                    Expanded(child: _field('Start date (YYYY-MM-DD)', _startDate)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          DropdownMenuItem(value: 'on_leave', child: Text('On leave')),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _status = value);
                        },
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<int?>(
                  value: _managerId,
                  decoration: const InputDecoration(labelText: 'Reporting manager'),
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(value: null, child: Text('No manager')),
                    ...widget.employees
                        .where((candidate) => stringValue(candidate['id']) != stringValue(widget.employee?['id']) && (stringValue(candidate['status']) == 'active' || int.tryParse(stringValue(candidate['id'])) == _managerId))
                        .map((candidate) => DropdownMenuItem<int?>(
                              value: int.tryParse(stringValue(candidate['id'])),
                              child: Text('${stringValue(candidate['full_name'])} · ${stringValue(candidate['employee_code'])}'),
                            )),
                  ],
                  onChanged: (value) => setState(() => _managerId = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded, size: 17), label: Text(editing ? 'Save changes' : 'Create employee')),
      ],
    );
  }

  Widget _field(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return 'Required';
          if (label == 'Work email' && !text.contains('@')) return 'Enter a valid email';
          if (label.startsWith('Start date') && DateTime.tryParse(text) == null) return 'Use YYYY-MM-DD';
          return null;
        },
      ),
    );
  }
}
