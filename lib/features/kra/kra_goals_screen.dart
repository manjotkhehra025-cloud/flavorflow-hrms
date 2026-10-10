import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class KraGoalsScreen extends StatefulWidget {
  const KraGoalsScreen({super.key});

  @override
  State<KraGoalsScreen> createState() => _KraGoalsScreenState();
}

class _KraGoalsScreenState extends State<KraGoalsScreen> {
  List<Map<String, dynamic>> _templates = const [];
  List<Map<String, dynamic>> _goals = const [];
  List<Map<String, dynamic>> _employees = const [];
  bool _applicable = true;
  String? _notice;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  bool get _canManage => AppScope.of(context).user!.can('kra.manage');
  bool get _canUpdateSelf => AppScope.of(context).user!.can('kra.update.self');
  bool get _canReviewTeam => AppScope.of(context).user!.canAny(const ['kra.update.team', 'kra.manage']);

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
      final api = AppScope.of(context).api;
      final responses = await Future.wait<dynamic>([
        api.get('kra/templates'),
        api.get('kra/goals'),
        _canManage ? api.get('employees') : Future<dynamic>.value(const <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final templates = asJsonMap(responses[0]);
      final goals = asJsonMap(responses[1]);
      setState(() {
        _templates = asJsonList(templates['items']);
        _goals = asJsonList(goals['items']);
        _employees = asJsonList(asJsonMap(responses[2])['items']);
        _applicable = templates['applicable'] != false && goals['applicable'] != false;
        _notice = stringValue(goals['notice'], fallback: stringValue(templates['notice']));
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addTemplate() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _KraTemplateDialog(),
    );
    if (values == null || !mounted) return;
    await _saveRequest(() => AppScope.of(context).api.post('kra/templates', values), 'KRA template saved.');
  }

  Future<void> _editTemplate(Map<String, dynamic> template) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _KraTemplateDialog(template: template),
    );
    if (values == null || !mounted) return;
    await _saveRequest(
      () => AppScope.of(context).api.patch('kra/templates/${template['id']}', values),
      'KRA template updated.',
    );
  }

  Future<void> _assignGoal() async {
    final officialEmployees = _employees.where((employee) =>
      stringValue(employee['employment_type']) != 'Yellow Card' &&
      stringValue(employee['status']) == 'active'
    ).toList();
    if (_templates.isEmpty || officialEmployees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a verified role template and active Official Staff profile first.')));
      return;
    }
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AssignGoalDialog(templates: _templates, employees: officialEmployees),
    );
    if (values == null || !mounted) return;
    await _saveRequest(() => AppScope.of(context).api.post('kra/goals', values), 'Goal assigned.');
  }

  Future<void> _editProgress(Map<String, dynamic> goal) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _GoalProgressDialog(goal: goal),
    );
    if (values == null || !mounted) return;
    await _saveRequest(() => AppScope.of(context).api.patch('kra/goals/${goal['id']}', values), 'Goal progress saved.');
  }

  Future<void> _reviewGoal(Map<String, dynamic> goal) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _GoalReviewDialog(goal: goal),
    );
    if (values == null || !mounted) return;
    await _saveRequest(() => AppScope.of(context).api.patch('kra/goals/${goal['id']}', values), 'KRA review saved.');
  }

  Future<void> _saveRequest(Future<dynamic> Function() request, String success) async {
    setState(() => _saving = true);
    try {
      await request();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
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
                  title: 'KRA & Goals',
                  subtitle: 'Role templates, goal progress, and manager reviews for Official Staff.',
                  trailing: Wrap(spacing: 8, children: [
                    if (_canManage) OutlinedButton.icon(onPressed: _saving ? null : _addTemplate, icon: const Icon(Icons.library_add_outlined, size: 17), label: const Text('Add template')),
                    if (_canManage) PrimaryButton(label: _saving ? 'Saving…' : 'Assign goal', icon: Icons.add_task_rounded, busy: _saving, onPressed: _saving ? null : _assignGoal),
                  ]),
                ),
                if (_error != null) ...[
                  ErrorNotice(message: _error!, onRetry: _load),
                  const SizedBox(height: 13),
                ],
                if (_notice != null && !_applicable) ...[
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: AppColors.softAmber, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFFFE2B0))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline_rounded, color: Color(0xFFAC741E), size: 19), const SizedBox(width: 9), Expanded(child: Text(_notice!, style: const TextStyle(color: AppColors.ink, fontSize: 12, height: 1.45)))]),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_loading && _goals.isEmpty && _templates.isEmpty)
                  const SizedBox(height: 190, child: LoadingView(label: 'Loading KRA templates and goals…'))
                else ...[
                  if (_applicable && _canManage) ...[
                    AppPanel(
                      padding: const EdgeInsets.all(17),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [const Expanded(child: Text('Role Templates', style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800))), Text('${_templates.length} templates', style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700))]),
                        const SizedBox(height: 4),
                        const Text('Create templates only after confirming their KPI wording and weights against the supplied reference.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
                        const SizedBox(height: 12),
                        if (_templates.isEmpty)
                          const EmptyNotice(title: 'No verified role templates', subtitle: 'Use Add template to enter approved KRA text and weights. No screenshot wording has been guessed or auto-seeded.', icon: Icons.fact_check_outlined)
                        else
                          ..._templates.map((template) => _TemplateRow(
                                template: template,
                                onEdit: () => _editTemplate(template),
                              )),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],
                  AppPanel(
                    padding: const EdgeInsets.all(17),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [const Expanded(child: Text('Assigned Goals', style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800))), Text('${_goals.length} goals', style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700))]),
                      const SizedBox(height: 4),
                      const Text('Official Staff KRAs and appraisals are recorded separately from Yellow Card output logs.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                      const SizedBox(height: 12),
                      if (_goals.isEmpty)
                        EmptyNotice(
                          title: _applicable ? 'No goals assigned yet' : 'KRA is not applicable to this employee category',
                          subtitle: _applicable ? 'HR or People Ops can assign goals from an approved role template.' : 'See the category note above for Yellow Card performance tracking.',
                          icon: Icons.track_changes_rounded,
                        )
                      else
                        ..._goals.map((goal) => _GoalCard(
                              goal: goal,
                              canUpdateSelf: _canUpdateSelf,
                              canReview: _canReviewTeam,
                              onUpdate: () => _editProgress(goal),
                              onReview: () => _reviewGoal(goal),
                            )),
                    ]),
                  ),
                  if (!_canManage && user.canAny(const ['kra.read.self', 'kra.read.team'])) ...[
                    const SizedBox(height: 12),
                    const Text('Your visibility follows your current KRA role scope. Goals for other departments are not shown.', style: TextStyle(color: AppColors.muted, fontSize: 10)),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.template, required this.onEdit});
  final Map<String, dynamic> template;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.assignment_outlined, color: AppColors.blue, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stringValue(template['title']), style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text('${stringValue(template['department'])} · ${stringValue(template['role_title'])} · ${stringValue(template['description'], fallback: 'No details')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10))])),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: AppColors.softGreen, borderRadius: BorderRadius.circular(20)), child: Text('${stringValue(template['weight_percent'])}%', style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w800))),
          IconButton(onPressed: onEdit, tooltip: 'Edit template wording and weight', icon: const Icon(Icons.edit_outlined, color: AppColors.blue, size: 18)),
        ]),
      );
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.canUpdateSelf, required this.canReview, required this.onUpdate, required this.onReview});
  final Map<String, dynamic> goal;
  final bool canUpdateSelf;
  final bool canReview;
  final VoidCallback onUpdate;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final progress = (int.tryParse(stringValue(goal['progress_percent'])) ?? 0).clamp(0, 100);
    final status = stringValue(goal['status'], fallback: 'not_started').replaceAll('_', ' ');
    final employeeName = stringValue(goal['employee_name'], fallback: 'My goal');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF9FBFE), borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stringValue(goal['title']), style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('$employeeName · ${stringValue(goal['department'])} · ${stringValue(goal['cycle'])}', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(18)), child: Text('$status · ${stringValue(goal['weight_percent'])}%', style: const TextStyle(color: AppColors.blue, fontSize: 9, fontWeight: FontWeight.w700))),
        ]),
        if (stringValue(goal['description']).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(stringValue(goal['description']), style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
        ],
        if (stringValue(goal['target']).isNotEmpty) ...[
          const SizedBox(height: 7),
          Text('Target: ${stringValue(goal['target'])}', style: const TextStyle(color: AppColors.ink, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 11),
        Row(children: [Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: progress / 100, minHeight: 6, backgroundColor: AppColors.line, color: AppColors.teal))), const SizedBox(width: 9), Text('$progress%', style: const TextStyle(color: AppColors.ink, fontSize: 10, fontWeight: FontWeight.w800))]),
        if (stringValue(goal['self_comment']).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Employee note: ${stringValue(goal['self_comment'])}', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        ],
        if (goal['manager_score'] != null) ...[
          const SizedBox(height: 6),
          Text('Manager score: ${stringValue(goal['manager_score'])}/100 · ${stringValue(goal['manager_comment'])}', style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
        if (canUpdateSelf || canReview) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            if (canUpdateSelf) OutlinedButton.icon(onPressed: onUpdate, icon: const Icon(Icons.edit_outlined, size: 15), label: const Text('Update progress')),
            if (canReview) OutlinedButton.icon(onPressed: onReview, icon: const Icon(Icons.rate_review_outlined, size: 15), label: const Text('Manager review')),
          ]),
        ],
      ]),
    );
  }
}

class _KraTemplateDialog extends StatefulWidget {
  const _KraTemplateDialog({this.template});
  final Map<String, dynamic>? template;

  @override
  State<_KraTemplateDialog> createState() => _KraTemplateDialogState();
}

class _KraTemplateDialogState extends State<_KraTemplateDialog> {
  static const _departments = ['Production', 'Agriculture', 'Security', 'Engineering', 'Accounts', 'Quality'];
  final _role = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _weight = TextEditingController();
  late String _department;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _role.text = stringValue(template?['role_title']);
    _title.text = stringValue(template?['title']);
    _description.text = stringValue(template?['description']);
    _weight.text = stringValue(template?['weight_percent'], fallback: '25');
    _department = stringValue(template?['department'], fallback: 'Production');
  }

  @override
  void dispose() { _role.dispose(); _title.dispose(); _description.dispose(); _weight.dispose(); super.dispose(); }

  void _save() {
    final weight = int.tryParse(_weight.text.trim());
    if (_role.text.trim().isEmpty || _title.text.trim().isEmpty || weight == null || weight < 1 || weight > 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a role, a KRA title, and a weight from 1 to 100.')));
      return;
    }
    Navigator.pop(context, {'department': _department, 'role_title': _role.text.trim(), 'title': _title.text.trim(), 'description': _description.text.trim(), 'weight_percent': weight});
  }

  @override
  Widget build(BuildContext context) {
    final departments = {..._departments, _department}.toList();
    final editing = widget.template != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(editing ? 'Edit role template' : 'Create role template', style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
      content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: _department, decoration: const InputDecoration(labelText: 'Department'), items: departments.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) { if (value != null) setState(() => _department = value); }),
        const SizedBox(height: 10),
        TextField(controller: _role, decoration: const InputDecoration(labelText: 'Role title')),
        const SizedBox(height: 10),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'KRA / KPI title')),
        const SizedBox(height: 10),
        TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Verified description')),
        const SizedBox(height: 10),
        TextField(controller: _weight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weight percent (1–100)')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded, size: 17), label: Text(editing ? 'Save changes' : 'Save template'))],
    );
  }
}

class _AssignGoalDialog extends StatefulWidget {
  const _AssignGoalDialog({required this.templates, required this.employees});
  final List<Map<String, dynamic>> templates;
  final List<Map<String, dynamic>> employees;
  @override
  State<_AssignGoalDialog> createState() => _AssignGoalDialogState();
}

class _AssignGoalDialogState extends State<_AssignGoalDialog> {
  final _cycle = TextEditingController(text: '${DateTime.now().year}');
  final _target = TextEditingController();
  int? _employeeId;
  int? _templateId;

  @override
  void initState() { super.initState(); if (widget.employees.isNotEmpty) _employeeId = int.tryParse(stringValue(widget.employees.first['id'])); if (widget.templates.isNotEmpty) _templateId = int.tryParse(stringValue(widget.templates.first['id'])); }
  @override
  void dispose() { _cycle.dispose(); _target.dispose(); super.dispose(); }

  void _save() {
    if (_employeeId == null || _templateId == null || _cycle.text.trim().isEmpty) return;
    Navigator.pop(context, {'employee_id': _employeeId, 'template_id': _templateId, 'cycle': _cycle.text.trim(), 'target': _target.text.trim()});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Assign KRA goal', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
        content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(value: _employeeId, decoration: const InputDecoration(labelText: 'Official Staff employee'), items: widget.employees.where((employee) => stringValue(employee['employment_type']) != 'Yellow Card' && stringValue(employee['status']) == 'active').map((employee) => DropdownMenuItem(value: int.tryParse(stringValue(employee['id'])), child: Text('${stringValue(employee['full_name'])} · ${stringValue(employee['employee_code'])}'))).toList(), onChanged: (value) => setState(() => _employeeId = value)),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(value: _templateId, decoration: const InputDecoration(labelText: 'Role template'), items: widget.templates.map((template) => DropdownMenuItem(value: int.tryParse(stringValue(template['id'])), child: Text('${stringValue(template['role_title'])} · ${stringValue(template['title'])}', maxLines: 1, overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setState(() => _templateId = value)),
          const SizedBox(height: 10),
          TextField(controller: _cycle, decoration: const InputDecoration(labelText: 'Cycle (year or 2026-Q1)')),
          const SizedBox(height: 10),
          TextField(controller: _target, maxLines: 2, decoration: const InputDecoration(labelText: 'Measurable target')),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.assignment_turned_in_outlined, size: 17), label: const Text('Assign goal'))],
      );
}

class _GoalProgressDialog extends StatefulWidget {
  const _GoalProgressDialog({required this.goal});
  final Map<String, dynamic> goal;
  @override
  State<_GoalProgressDialog> createState() => _GoalProgressDialogState();
}

class _GoalProgressDialogState extends State<_GoalProgressDialog> {
  late double _progress;
  late final TextEditingController _comment;
  @override
  void initState() { super.initState(); _progress = (double.tryParse(stringValue(widget.goal['progress_percent'])) ?? 0).clamp(0, 100).toDouble(); _comment = TextEditingController(text: stringValue(widget.goal['self_comment'])); }
  @override
  void dispose() { _comment.dispose(); super.dispose(); }
  void _save() => Navigator.pop(context, {'progress_percent': _progress.round(), 'self_comment': _comment.text.trim(), 'status': _progress >= 100 ? 'completed' : _progress > 0 ? 'in_progress' : 'not_started'});
  @override
  Widget build(BuildContext context) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)), title: const Text('Update goal progress', style: TextStyle(fontWeight: FontWeight.w800)), content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [Text('${_progress.round()}% complete', style: const TextStyle(color: AppColors.blue, fontSize: 15, fontWeight: FontWeight.w800)), Slider(value: _progress, min: 0, max: 100, divisions: 20, label: '${_progress.round()}%', onChanged: (value) => setState(() => _progress = value)), TextField(controller: _comment, maxLines: 3, decoration: const InputDecoration(labelText: 'Progress note'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined, size: 17), label: const Text('Save progress'))]);
}

class _GoalReviewDialog extends StatefulWidget {
  const _GoalReviewDialog({required this.goal});
  final Map<String, dynamic> goal;
  @override
  State<_GoalReviewDialog> createState() => _GoalReviewDialogState();
}

class _GoalReviewDialogState extends State<_GoalReviewDialog> {
  late final TextEditingController _score;
  late final TextEditingController _comment;
  @override
  void initState() { super.initState(); _score = TextEditingController(text: stringValue(widget.goal['manager_score'], fallback: '')); _comment = TextEditingController(text: stringValue(widget.goal['manager_comment'])); }
  @override
  void dispose() { _score.dispose(); _comment.dispose(); super.dispose(); }
  void _save() { final score = int.tryParse(_score.text.trim()); if (score == null || score < 0 || score > 100) return; Navigator.pop(context, {'manager_score': score, 'manager_comment': _comment.text.trim(), 'status': 'reviewed'}); }
  @override
  Widget build(BuildContext context) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)), title: const Text('Manager review', style: TextStyle(fontWeight: FontWeight.w800)), content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: _score, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Score (0–100)')), const SizedBox(height: 10), TextField(controller: _comment, maxLines: 3, decoration: const InputDecoration(labelText: 'Manager comment'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.rate_review_outlined, size: 17), label: const Text('Save review'))]);
}
