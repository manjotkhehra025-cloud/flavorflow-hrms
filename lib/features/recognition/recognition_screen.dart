import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  List<Map<String, dynamic>> _awards = const [];
  String _period = _monthKey(DateTime.now());
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
      final response = await AppScope.of(context).api.get(
        'recognition-awards',
        query: {'period': _period},
      );
      if (!mounted) return;
      setState(() => _awards = asJsonList(asJsonMap(response)['items']));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _issueAward() async {
    final api = AppScope.of(context).api;
    try {
      final response = await api.get('employees');
      if (!mounted) return;
      final employees = asJsonList(asJsonMap(response)['items'])
          .where((employee) => stringValue(employee['status']) == 'active')
          .toList();
      if (employees.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active employee profiles are available.')));
        return;
      }
      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _AwardDialog(employees: employees, period: _period),
      );
      if (values == null || !mounted) return;
      await api.post('recognition-awards', values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recognition award issued.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _changeMonth(int offset) async {
    final parts = _period.split('-');
    final current = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
    final next = DateTime(current.year, current.month + offset, 1);
    setState(() => _period = _monthKey(next));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final canIssue = AppScope.of(context).user!.can('recognition.manage');
    final headingMonth = _monthLabel(_period);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1050),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PageHeading(
                  title: 'Star Workers',
                  subtitle: 'Celebrate outstanding work and the people behind it.',
                  trailing: canIssue
                      ? FilledButton.icon(onPressed: _issueAward, icon: const Icon(Icons.add_rounded), label: const Text('Issue award'))
                      : IconButton.filledTonal(onPressed: _load, tooltip: 'Refresh awards', icon: const Icon(Icons.refresh_rounded)),
                ),
                AppPanel(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.softAmber, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFB57814), size: 23)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Monthly recognition', style: TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(headingMonth, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    ])),
                    IconButton(onPressed: () => _changeMonth(-1), tooltip: 'Previous month', icon: const Icon(Icons.chevron_left_rounded)),
                    IconButton(onPressed: () => _changeMonth(1), tooltip: 'Next month', icon: const Icon(Icons.chevron_right_rounded)),
                  ]),
                ),
                const SizedBox(height: 16),
                if (_error != null) ErrorNotice(message: _error!, onRetry: _load)
                else if (_loading && _awards.isEmpty)
                  const SizedBox(height: 200, child: LoadingView(label: 'Loading recognition…'))
                else if (_awards.isEmpty)
                  const AppPanel(child: EmptyNotice(
                    title: 'No awards this month',
                    subtitle: 'When the team is recognized, their stories will appear here.',
                    icon: Icons.workspace_premium_outlined,
                  ))
                else
                  ..._awards.asMap().entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: _AwardCard(award: entry.value, rank: entry.key + 1),
                      )),
                if (_loading && _awards.isNotEmpty)
                  const Padding(padding: EdgeInsets.all(14), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
                if (canIssue) ...[
                  const SizedBox(height: 5),
                  const Text('Awards are issued by Admin / People Ops. Employee-facing results are read-only.', style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4)),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _AwardCard extends StatelessWidget {
  const _AwardCard({required this.award, required this.rank});
  final Map<String, dynamic> award;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final name = stringValue(award['employee_name'], fallback: 'Team member');
    final category = stringValue(award['category'], fallback: 'star_worker');
    final badge = switch (category) {
      'perfect_attendance' => 'Perfect attendance',
      'safety' => 'Safety',
      'shift_output' => 'Shift output',
      'teamwork' => 'Teamwork',
      _ => 'Star worker',
    };
    final color = category == 'safety' ? AppColors.success : AppColors.blue;
    return AppPanel(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: rank == 1 ? AppColors.softAmber : AppColors.softBlue, borderRadius: BorderRadius.circular(14)),
          child: Icon(rank == 1 ? Icons.workspace_premium_rounded : Icons.star_rounded, color: rank == 1 ? const Color(0xFFB57814) : AppColors.blue, size: 22),
        ),
        const SizedBox(width: 12),
        PersonAvatar(name: name, size: 42),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w800))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(30)), child: Text(badge, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 5),
          Text(stringValue(award['department']), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          const SizedBox(height: 8),
          Text(stringValue(award['citation']), style: const TextStyle(color: AppColors.ink, fontSize: 12, height: 1.45)),
          const SizedBox(height: 8),
          Text('Recognized by ${stringValue(award['awarded_by_name'], fallback: 'People Ops')}', style: const TextStyle(color: AppColors.muted, fontSize: 9)),
        ])),
      ]),
    );
  }
}

class _AwardDialog extends StatefulWidget {
  const _AwardDialog({required this.employees, required this.period});
  final List<Map<String, dynamic>> employees;
  final String period;

  @override
  State<_AwardDialog> createState() => _AwardDialogState();
}

class _AwardDialogState extends State<_AwardDialog> {
  int? _employeeId;
  String _category = 'star_worker';
  final _citation = TextEditingController();

  @override
  void initState() {
    super.initState();
    _employeeId = int.tryParse(stringValue(widget.employees.first['id']));
  }

  @override
  void dispose() {
    _citation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Issue recognition award'),
        content: SizedBox(
          width: 470,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: _employeeId,
              decoration: const InputDecoration(labelText: 'Employee'),
              items: widget.employees.map((employee) {
                final id = int.tryParse(stringValue(employee['id'])) ?? 0;
                final name = stringValue(employee['full_name'], fallback: '${stringValue(employee['first_name'])} ${stringValue(employee['last_name'])}'.trim());
                return DropdownMenuItem<int>(value: id, child: Text(name, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (value) => setState(() => _employeeId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Award type'),
              items: const [
                DropdownMenuItem(value: 'star_worker', child: Text('Star worker')),
                DropdownMenuItem(value: 'perfect_attendance', child: Text('Perfect attendance')),
                DropdownMenuItem(value: 'safety', child: Text('Safety')),
                DropdownMenuItem(value: 'shift_output', child: Text('Shift output')),
                DropdownMenuItem(value: 'teamwork', child: Text('Teamwork')),
              ],
              onChanged: (value) => setState(() => _category = value ?? 'star_worker'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _citation, maxLength: 1000, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Recognition note')),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: Text('Period: ${_monthLabel(widget.period)}', style: const TextStyle(color: AppColors.muted, fontSize: 11))),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final citation = _citation.text.trim();
              if (_employeeId == null || citation.isEmpty) return;
              Navigator.pop(context, {
                'employee_id': _employeeId,
                'category': _category,
                'period': widget.period,
                'citation': citation,
              });
            },
            child: const Text('Issue award'),
          ),
        ],
      );
}

String _monthKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

String _monthLabel(String value) {
  final parts = value.split('-');
  final date = DateTime.tryParse('${parts[0]}-${parts[1]}-01');
  if (date == null) return value;
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${months[date.month - 1]} ${date.year}';
}
