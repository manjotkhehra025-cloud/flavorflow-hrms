import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../models/employee.dart';
import '../../providers/auth_provider.dart';
import '../../providers/employee_provider.dart';
import '../../widgets/common.dart';

/// Add a new employee, or edit an existing one when [employee] is given.
class EmployeeFormScreen extends StatefulWidget {
  const EmployeeFormScreen({super.key, this.employee});
  final Employee? employee;

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _department;
  late final TextEditingController _designation;
  late final TextEditingController _salary;
  late final TextEditingController _manager;
  late final TextEditingController _address;
  final _password = TextEditingController(text: 'emp123');
  late DateTime _joining;
  late UserRole _role;
  late bool _active;
  bool _saving = false;

  bool get _isEdit => widget.employee != null;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _id = TextEditingController(text: e?.id ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _department = TextEditingController(text: e?.department ?? '');
    _designation = TextEditingController(text: e?.designation ?? '');
    _salary = TextEditingController(text: e == null ? '' : e.monthlyCtc.toStringAsFixed(0));
    _manager = TextEditingController(text: e?.managerName ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _joining = e?.joiningDate ?? dateOnly(DateTime.now());
    _role = e?.role ?? UserRole.employee;
    _active = e?.isActive ?? true;
    if (!_isEdit) {
      context.read<EmployeeProvider>().nextId().then((id) {
        if (mounted && _id.text.isEmpty) _id.text = id;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_id, _name, _email, _phone, _department, _designation, _salary, _manager, _address, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _pickJoining() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joining,
      firstDate: DateTime(1990),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked != null) setState(() => _joining = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final employee = Employee(
      id: _id.text.trim().toUpperCase(),
      name: _name.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      department: _department.text.trim(),
      designation: _designation.text.trim(),
      joiningDate: _joining,
      monthlyCtc: double.tryParse(_salary.text.trim()) ?? 0,
      role: _role,
      managerName: _manager.text.trim().isEmpty ? null : _manager.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      bloodGroup: widget.employee?.bloodGroup,
      isActive: _active,
    );
    final provider = context.read<EmployeeProvider>();
    final auth = context.read<AuthProvider>();
    final error = _isEdit ? await provider.update(employee) : await provider.add(employee, _password.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      showSnack(context, error, error: true);
      return;
    }
    auth.refreshUser(employee);
    showSnack(context, _isEdit ? 'Employee updated' : 'Employee added');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Employee' : 'Add Employee')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _id,
              enabled: !_isEdit,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Employee ID'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 12),
            TextFormField(controller: _department, decoration: const InputDecoration(labelText: 'Department'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: _designation, decoration: const InputDecoration(labelText: 'Designation'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(
              controller: _salary,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Monthly salary (CTC)', prefixText: '\u20B9 '),
              validator: (v) => double.tryParse(v?.trim() ?? '') == null ? 'Enter amount in rupees' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _manager, decoration: const InputDecoration(labelText: 'Reporting manager')),
            const SizedBox(height: 12),
            TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickJoining,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date of joining', prefixIcon: Icon(Icons.event)),
                child: Text(Fmt.date(_joining)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Role', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<UserRole>(
              segments: const [
                ButtonSegment(value: UserRole.employee, label: Text('Employee'), icon: Icon(Icons.person)),
                ButtonSegment(value: UserRole.admin, label: Text('Admin / HR'), icon: Icon(Icons.admin_panel_settings)),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Inactive employees cannot log in'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 4),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Initial password'),
                validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_isEdit ? 'Save changes' : 'Add employee'),
            ),
          ],
        ),
      ),
    );
  }
}
