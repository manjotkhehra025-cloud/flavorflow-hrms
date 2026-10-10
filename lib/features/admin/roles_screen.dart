import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _catalog = const [];
  String? _selectedId;
  Set<String> _draft = <String>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? get _selected {
    for (final role in _roles) {
      if (role['id'] == _selectedId) return role;
    }
    return null;
  }

  bool get _dirty {
    final original = asStringList(_selected?['permissions']).toSet();
    return original.length != _draft.length || !original.containsAll(_draft);
  }

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
      final response = asJsonMap(await AppScope.of(context).api.get('roles'));
      if (!mounted) return;
      final roles = asJsonList(response['roles']);
      final catalog = asJsonList(response['permission_catalog']);
      final id = _selectedId != null && roles.any((role) => role['id'] == _selectedId) ? _selectedId : (roles.isEmpty ? null : stringValue(roles.first['id']));
      final selected = firstOrNone(roles.where((role) => role['id'] == id));
      setState(() {
        _roles = roles;
        _catalog = catalog;
        _selectedId = id;
        _draft = asStringList(selected?['permissions']).toSet();
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(Map<String, dynamic> role) {
    setState(() {
      _selectedId = stringValue(role['id']);
      _draft = asStringList(role['permissions']).toSet();
    });
  }

  Future<void> _save() async {
    final role = _selected;
    if (role == null || !_dirty || role['id'] == 'super_admin') return;
    setState(() => _saving = true);
    final controller = AppScope.of(context);
    try {
      await controller.api.patch('roles/${role['id']}/permissions', {'permissions': _draft.toList()..sort()});
      await controller.refreshUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role permissions saved.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createRole() async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _RoleFormDialog(),
    );
    if (values == null || !mounted) return;
    try {
      final created = asJsonMap(await AppScope.of(context).api.post('roles', values));
      if (!mounted) return;
      setState(() {
        _selectedId = stringValue(created['id']);
        _draft = <String>{};
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role created. Choose its permissions and save.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _toggle(String key, bool value) {
    setState(() {
      if (value) {
        _draft.add(key);
      } else {
        _draft.remove(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = AppScope.of(context).user!.can('rbac.update');
    final role = _selected;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1370),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeading(title: 'Roles & permissions', subtitle: 'Shape access around how your teams work.', trailing: canEdit ? OutlinedButton.icon(onPressed: _createRole, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New role')) : null),
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFDDE9FC))), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.storage_rounded, color: AppColors.blue, size: 20), SizedBox(width: 11), Expanded(child: Text('This permission catalog and every role grant are stored in the API database. The UI reads the live catalog; the API validates these same keys on each protected request.', style: TextStyle(color: AppColors.ink, fontSize: 12, height: 1.5)))])),
              const SizedBox(height: 17),
              if (_loading && _roles.isEmpty)
                const SizedBox(height: 220, child: LoadingView(label: 'Loading role catalog…'))
              else if (_error != null && _roles.isEmpty)
                ErrorNotice(message: _error!, onRetry: _load)
              else if (role == null)
                const AppPanel(child: EmptyNotice(title: 'No roles found', subtitle: 'Role records will appear here.', icon: Icons.admin_panel_settings_outlined))
              else
                LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 850;
                  final picker = _RolePicker(roles: _roles, selectedId: _selectedId, onSelect: _select, compact: !wide);
                  final editor = _PermissionEditor(
                    role: role,
                    catalog: _catalog,
                    draft: _draft,
                    canEdit: canEdit && role['id'] != 'super_admin',
                    saving: _saving,
                    dirty: _dirty,
                    onToggle: _toggle,
                    onSave: _save,
                  );
                  if (!wide) return Column(children: [picker, const SizedBox(height: 14), editor]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 270, child: picker), const SizedBox(width: 16), Expanded(child: editor)]);
                }),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.roles, required this.selectedId, required this.onSelect, required this.compact});
  final List<Map<String, dynamic>> roles;
  final String? selectedId;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final selected = firstOrNone(roles.where((role) => role['id'] == selectedId));
    if (compact) {
      return AppPanel(
        padding: const EdgeInsets.all(15),
        child: DropdownButtonFormField<String>(
          value: selectedId,
          decoration: const InputDecoration(labelText: 'Selected role'),
          items: roles.map((role) => DropdownMenuItem(value: stringValue(role['id']), child: Text(stringValue(role['name'])))).toList(),
          onChanged: (id) { final role = firstOrNone(roles.where((item) => item['id'] == id)); if (role != null) onSelect(role); },
        ),
      );
    }
    return AppPanel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.fromLTRB(9, 7, 9, 13), child: Text('WORKSPACE ROLES', style: TextStyle(color: AppColors.muted, letterSpacing: 0.9, fontSize: 9, fontWeight: FontWeight.w800))),
        ...roles.map((role) {
          final active = role['id'] == selectedId;
          final count = asStringList(role['permissions']).length;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: active ? AppColors.softBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => onSelect(role),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
                  child: Row(children: [Icon(role['id'] == 'super_admin' ? Icons.shield_rounded : Icons.badge_outlined, size: 19, color: active ? AppColors.blue : AppColors.muted), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stringValue(role['name']), style: TextStyle(color: active ? AppColors.blue : AppColors.ink, fontWeight: FontWeight.w700, fontSize: 12)), const SizedBox(height: 3), Text('$count permissions', style: const TextStyle(color: AppColors.muted, fontSize: 10))])), if (active) const Icon(Icons.chevron_right_rounded, color: AppColors.blue, size: 18)]),
                ),
              ),
            ),
          );
        }),
        if (selected != null && stringValue(selected['id']) == 'super_admin')
          const Padding(padding: EdgeInsets.fromLTRB(9, 10, 9, 3), child: Text('Super Admin is protected and always receives full access.', style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.45))),
      ]),
    );
  }
}

class _PermissionEditor extends StatelessWidget {
  const _PermissionEditor({required this.role, required this.catalog, required this.draft, required this.canEdit, required this.saving, required this.dirty, required this.onToggle, required this.onSave});
  final Map<String, dynamic> role;
  final List<Map<String, dynamic>> catalog;
  final Set<String> draft;
  final bool canEdit;
  final bool saving;
  final bool dirty;
  final void Function(String key, bool value) onToggle;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final permission in catalog) {
      grouped.putIfAbsent(stringValue(permission['module']), () => []).add(permission);
    }
    final system = role['id'] == 'super_admin';
    final effectivePermissions = system ? asStringList(role['permissions']).toSet() : draft;
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stringValue(role['name']), style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(stringValue(role['description']), style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4))])), StatusBadge(status: system ? 'protected' : 'editable')]),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: system ? AppColors.softGreen : const Color(0xFFF6F9FC), borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(system ? Icons.verified_user_rounded : Icons.tune_rounded, color: system ? AppColors.success : AppColors.blue, size: 17), const SizedBox(width: 8), Expanded(child: Text(system ? 'Full access · ${catalog.length} catalog permissions' : '${effectivePermissions.length} permissions granted', style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w700))), if (dirty) const Text('Unsaved changes', style: TextStyle(color: Color(0xFFAE751C), fontSize: 10, fontWeight: FontWeight.w700))])),
        const SizedBox(height: 12),
        if (catalog.isEmpty)
          const EmptyNotice(title: 'Catalog is empty', subtitle: 'Permission keys will appear when registered by the API.', icon: Icons.key_off_rounded)
        else
          ...grouped.entries.map((entry) => _PermissionGroup(module: entry.key, permissions: entry.value, selected: effectivePermissions, enabled: canEdit, onToggle: onToggle)),
        if (system)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('This system role cannot be edited. Newly registered permission keys are included in its effective permissions by the server.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5)))
        else if (canEdit)
          Padding(padding: const EdgeInsets.only(top: 15), child: Align(alignment: Alignment.centerRight, child: PrimaryButton(label: saving ? 'Saving…' : 'Save permissions', icon: Icons.save_outlined, busy: saving, onPressed: dirty ? onSave : null))),
      ]),
    );
  }
}

class _PermissionGroup extends StatelessWidget {
  const _PermissionGroup({required this.module, required this.permissions, required this.selected, required this.enabled, required this.onToggle});
  final String module;
  final List<Map<String, dynamic>> permissions;
  final Set<String> selected;
  final bool enabled;
  final void Function(String key, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    final title = module.isEmpty ? 'Other' : '${module[0].toUpperCase()}${module.substring(1)}';
    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        ...permissions.map((permission) {
          final key = stringValue(permission['key']);
          final checked = selected.contains(key);
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(color: checked ? const Color(0xFFF8FBFF) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line.withValues(alpha: 0.8))),
            child: CheckboxListTile(
              value: checked,
              onChanged: enabled ? (value) => onToggle(key, value ?? false) : null,
              activeColor: AppColors.blue,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 9),
              title: Text(stringValue(permission['label'], fallback: key), style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w600)),
              subtitle: Text(key, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            ),
          );
        }),
      ]),
    );
  }
}

class _RoleFormDialog extends StatefulWidget {
  const _RoleFormDialog();
  @override
  State<_RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends State<_RoleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text('Create a role', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Role name'),
                validator: (value) => (value?.trim().isEmpty ?? true) ? 'Enter a role name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () { if (_formKey.currentState!.validate()) Navigator.pop(context, <String, String>{'name': _name.text.trim(), 'description': _description.text.trim()}); }, child: const Text('Create role'))],
    );
  }
}
