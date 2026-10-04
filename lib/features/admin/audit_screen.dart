import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  List<Map<String, dynamic>> _logs = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'All activity';

  static const _filters = ['All activity', 'Attendance', 'Leave', 'Employees', 'Access'];

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
      final response = await AppScope.of(context).api.get('audit-logs', query: const {'limit': '200'});
      if (mounted) setState(() => _logs = asJsonList(asJsonMap(response)['items']));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visibleLogs {
    final filter = _filter.toLowerCase();
    if (_filter == 'All activity') return _logs;
    return _logs.where((log) {
      final type = stringValue(log['entity_type']).toLowerCase();
      final action = stringValue(log['action']).toLowerCase();
      return switch (_filter) {
        'Attendance' => type.contains('attendance') || action.contains('attendance'),
        'Leave' => type.contains('leave') || action.contains('leave'),
        'Employees' => type.contains('employee') || action.contains('employee'),
        'Access' => type.contains('user') || type.contains('role') || type.contains('session') || action.contains('user') || action.contains('role') || action.startsWith('auth.'),
        _ => action.contains(filter),
      };
    }).toList();
  }

  void _showDetails(Map<String, dynamic> log) {
    final details = log['details'] is Map ? const JsonEncoder.withIndent('  ').convert(log['details']) : stringValue(log['details'], fallback: '{}');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Audit event', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              _DetailLine(label: 'Action', value: stringValue(log['action'])),
              _DetailLine(label: 'Actor', value: stringValue(log['actor_name'], fallback: 'System')),
              _DetailLine(label: 'Entity', value: '${stringValue(log['entity_type'])} ${stringValue(log['entity_id'])}'),
              _DetailLine(label: 'Time', value: formatDateTime(log['created_at'])),
              _DetailLine(label: 'Remote address', value: stringValue(log['remote_address'], fallback: 'Unavailable')),
              const SizedBox(height: 8),
              const Text('Details', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFF5F8FB), borderRadius: BorderRadius.circular(12)), child: SelectableText(details, style: const TextStyle(color: AppColors.ink, fontSize: 11, height: 1.45, fontFamily: 'monospace'))),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = _visibleLogs;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1250),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeading(title: 'Audit log', subtitle: 'A clear record of meaningful changes and access events.', trailing: IconButton.filledTonal(onPressed: _load, tooltip: 'Refresh audit log', icon: const Icon(Icons.refresh_rounded))),
              AppPanel(
                padding: const EdgeInsets.fromLTRB(15, 15, 15, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 8, children: _filters.map((filter) => ChoiceChip(label: Text(filter), selected: _filter == filter, onSelected: (_) => setState(() => _filter = filter), selectedColor: AppColors.softBlue, side: BorderSide(color: _filter == filter ? const Color(0xFFCCDEFB) : AppColors.line), labelStyle: TextStyle(color: _filter == filter ? AppColors.blue : AppColors.muted, fontWeight: FontWeight.w700, fontSize: 11))).toList()),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  if (_loading && _logs.isEmpty)
                    const SizedBox(height: 180, child: LoadingView(label: 'Loading audit events…'))
                  else if (_error != null && _logs.isEmpty)
                    Padding(padding: const EdgeInsets.only(top: 12), child: ErrorNotice(message: _error!, onRetry: _load))
                  else if (logs.isEmpty)
                    const EmptyNotice(title: 'No audit events found', subtitle: 'Activity will be recorded here as people use the workspace.', icon: Icons.manage_search_rounded)
                  else
                    ...logs.map((log) => _AuditRow(log: log, onTap: () => _showDetails(log))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.log, required this.onTap});
  final Map<String, dynamic> log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final action = stringValue(log['action']);
    final icon = action.startsWith('attendance') ? Icons.location_history_rounded : action.startsWith('leave') ? Icons.event_note_rounded : action.startsWith('role') || action.startsWith('user') ? Icons.admin_panel_settings_outlined : action.startsWith('auth.') ? Icons.lock_outline_rounded : Icons.edit_note_rounded;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680;
          return Row(children: [
            Container(width: 39, height: 39, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: AppColors.blue, size: 19)),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_humanize(action), style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 12)), const SizedBox(height: 4), Text('${stringValue(log['actor_name'], fallback: 'System')} · ${stringValue(log['entity_type'])} ${stringValue(log['entity_id'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11))])),
            if (wide) Expanded(child: Text(stringValue(log['remote_address'], fallback: '—'), style: const TextStyle(color: AppColors.muted, fontSize: 11))),
            Text(formatDateTime(log['created_at']), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 18),
          ]);
        }),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 108, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11))), Expanded(child: Text(value, style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w600)))]));
}

String _humanize(String action) => action.split('.').map((part) => part.replaceAll('_', ' ').split(' ').map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}').join(' ')).join(' · ');
