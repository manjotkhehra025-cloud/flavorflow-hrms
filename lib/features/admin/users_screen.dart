import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _employees = const [];
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
      final scope = AppScope.of(context);
      final api = scope.api;
      final userPayload = asJsonMap(await api.get('users'));
      var employeeItems = <Map<String, dynamic>>[];
      if (scope.user!.canAny(const ['employees.read', 'employees.read.team'])) {
        final employeePayload = await api.get('employees');
        employeeItems = asJsonList(asJsonMap(employeePayload)['items']);
      }
      if (!mounted) return;
      setState(() {
        _users = asJsonList(userPayload['items']);
        _roles = asJsonList(userPayload['role_options']);
        _employees = employeeItems;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createUser() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _UserFormDialog(roles: _roles, employees: _employees),
    );
    if (values == null || !mounted) return;
    try {
      await AppScope.of(context).api.post('users', values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User account created.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    final next = !(user['is_active'] == true || user['is_active'] == 1);
    try {
      await AppScope.of(context).api.patch('users/${user['id']}', {'is_active': next});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next ? 'Account reactivated.' : 'Account deactivated.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _UserAccessDialog(user: user, roles: _roles),
    );
    if (values == null || !mounted) return;
    try {
      await AppScope.of(context).api.patch('users/${user['id']}', values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User access updated.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AppScope.of(context).user!;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1220),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeading(title: 'User accounts', subtitle: 'Manage who can access your FlavorFlow workspace.', trailing: currentUser.can('users.create') ? PrimaryButton(label: 'Invite user', icon: Icons.person_add_alt_1_rounded, onPressed: _createUser) : null),
              Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFDDE9FC))), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.admin_panel_settings_outlined, color: AppColors.blue, size: 20), SizedBox(width: 11), Expanded(child: Text('Each account receives one or more roles. Effective permissions are resolved by the API from database grants every time a protected operation is requested.', style: TextStyle(color: AppColors.ink, fontSize: 12, height: 1.5)))])),
              const SizedBox(height: 17),
              if (_loading && _users.isEmpty)
                const SizedBox(height: 180, child: LoadingView(label: 'Loading user accounts…'))
              else if (_error != null && _users.isEmpty)
                ErrorNotice(message: _error!, onRetry: _load)
              else if (_users.isEmpty)
                const AppPanel(child: EmptyNotice(title: 'No accounts found', subtitle: 'Invite a teammate to give them access.', icon: Icons.person_add_alt_1_outlined))
              else
                AppPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Column(children: _users.map((user) => _UserRow(user: user, isCurrent: user['id'] == currentUser.id, canUpdate: currentUser.can('users.update'), onEdit: () => _editUser(user), onToggle: () => _toggleActive(user))).toList()),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, required this.isCurrent, required this.canUpdate, required this.onEdit, required this.onToggle});
  final Map<String, dynamic> user;
  final bool isCurrent;
  final bool canUpdate;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final active = user['is_active'] == true || user['is_active'] == 1;
    final roles = (user['roles'] as List? ?? const []).map((role) => role is Map ? stringValue(role['name']) : '').where((name) => name.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final identity = Row(children: [PersonAvatar(name: stringValue(user['full_name'], fallback: 'Team member'), size: 42), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stringValue(user['full_name']), style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(stringValue(user['email']), style: const TextStyle(color: AppColors.muted, fontSize: 11))]))]);
        if (!wide) {
          return Row(children: [Expanded(child: identity), const SizedBox(width: 8), StatusBadge(status: active ? 'active' : 'inactive'), if (canUpdate && !isCurrent) ...[IconButton(onPressed: onEdit, tooltip: 'Edit access', icon: const Icon(Icons.manage_accounts_outlined, color: AppColors.blue)), IconButton(onPressed: onToggle, tooltip: active ? 'Deactivate account' : 'Reactivate account', icon: Icon(active ? Icons.person_off_outlined : Icons.person_add_alt_1_outlined, color: active ? AppColors.muted : AppColors.success))]]);
        }
        return Row(children: [Expanded(flex: 4, child: identity), Expanded(flex: 3, child: Text(stringValue(user['employee_code'], fallback: 'No employee linked'), style: const TextStyle(color: AppColors.muted, fontSize: 11))), Expanded(flex: 3, child: Text(roles, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w600))), StatusBadge(status: active ? 'active' : 'inactive'), if (canUpdate && !isCurrent) ...[IconButton(onPressed: onEdit, tooltip: 'Edit access', icon: const Icon(Icons.manage_accounts_outlined, color: AppColors.blue)), IconButton(onPressed: onToggle, tooltip: active ? 'Deactivate account' : 'Reactivate account', icon: Icon(active ? Icons.person_off_outlined : Icons.person_add_alt_1_outlined, color: active ? AppColors.muted : AppColors.success))] else const SizedBox(width: 96)]);
      }),
    );
  }
}

class _UserAccessDialog extends StatefulWidget {
  const _UserAccessDialog({required this.user, required this.roles});
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> roles;

  @override
  State<_UserAccessDialog> createState() => _UserAccessDialogState();
}

class _UserAccessDialogState extends State<_UserAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final Set<String> _roleIds;
  late bool _active;
  String? _roleError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: stringValue(widget.user['full_name']));
    _roleIds = asJsonList(widget.user['roles']).map((role) => stringValue(role['id'])).where((id) => id.isNotEmpty).toSet();
    _active = widget.user['is_active'] == true || widget.user['is_active'] == 1;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_roleIds.isEmpty) {
      setState(() => _roleError = 'Select at least one role.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{'full_name': _name.text.trim(), 'is_active': _active, 'role_ids': _roleIds.toList()..sort()});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
      title: const Text('Edit user access', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: (value) => (value?.trim().isEmpty ?? true) ? 'Enter a name' : null),
              const SizedBox(height: 12),
              const Text('Assigned roles', style: TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...widget.roles.map((role) {
                final id = stringValue(role['id']);
                return CheckboxListTile(
                  value: _roleIds.contains(id),
                  onChanged: (value) => setState(() { if (value == true) { _roleIds.add(id); } else { _roleIds.remove(id); } _roleError = null; }),
                  activeColor: AppColors.blue,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(stringValue(role['name']), style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: Text(stringValue(role['description']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                );
              }),
              if (_roleError != null) Padding(padding: const EdgeInsets.only(left: 8), child: Text(_roleError!, style: const TextStyle(color: Color(0xFFC94D54), fontSize: 11))),
              SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _active, activeColor: AppColors.success, title: const Text('Account active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), onChanged: (value) => setState(() => _active = value)),
            ]),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton.icon(onPressed: _submit, icon: const Icon(Icons.save_outlined, size: 17), label: const Text('Save access'))],
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({required this.roles, required this.employees});
  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> employees;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _roleId;
  String? _employeeId;
  bool _hidePassword = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate() || _roleId == null) return;
    Navigator.pop(context, <String, dynamic>{
      'full_name': _name.text.trim(),
      'email': _email.text.trim(),
      'password': _password.text,
      'role_id': _roleId,
      if (_employeeId != null) 'employee_id': int.parse(_employeeId!),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
      title: const Text('Invite a teammate', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 430,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: (value) => (value?.trim().isEmpty ?? true) ? 'Enter a name' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Work email'), validator: (value) => (value?.contains('@') ?? false) ? null : 'Enter a valid email'),
            const SizedBox(height: 12),
            TextFormField(controller: _password, obscureText: _hidePassword, decoration: InputDecoration(labelText: 'Temporary password (10+ characters)', suffixIcon: IconButton(onPressed: () => setState(() => _hidePassword = !_hidePassword), icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined))), validator: (value) => (value?.length ?? 0) < 10 ? 'Use at least 10 characters' : null),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(value: _roleId, decoration: const InputDecoration(labelText: 'Role'), items: widget.roles.map((role) => DropdownMenuItem(value: stringValue(role['id']), child: Text(stringValue(role['name'])))).toList(), onChanged: (value) => setState(() => _roleId = value), validator: (value) => value == null ? 'Choose a role' : null),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(value: _employeeId, decoration: const InputDecoration(labelText: 'Link employee profile (optional)'), items: [const DropdownMenuItem<String>(value: null, child: Text('No employee profile')), ...widget.employees.where((employee) => employee['user_id'] == null).map((employee) => DropdownMenuItem(value: stringValue(employee['id']), child: Text('${stringValue(employee['full_name'])} · ${stringValue(employee['employee_code'])}')))], onChanged: (value) => setState(() => _employeeId = value)),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton.icon(onPressed: _submit, icon: const Icon(Icons.send_rounded, size: 17), label: const Text('Create account'))],
    );
  }
}
