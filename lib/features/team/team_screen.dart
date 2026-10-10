import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _members = const [];
  List<Map<String, dynamic>> _upcomingLeaves = const [];
  List<String> _departments = const [];
  Map<String, dynamic> _summary = const {};
  bool _loading = true;
  String? _error;
  String _selectedDepartment = '';
  String _selectedView = 'attendance';

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
      final query = <String, String>{'date': _dateString(DateTime.now())};
      final search = _searchController.text.trim();
      if (search.isNotEmpty) query['q'] = search;
      if (_selectedDepartment.isNotEmpty) query['department'] = _selectedDepartment;
      final response = await AppScope.of(context).api.get('team', query: query);
      if (!mounted) return;
      final payload = asJsonMap(response);
      setState(() {
        _members = asJsonList(payload['items']);
        _upcomingLeaves = asJsonList(payload['upcoming_leaves']);
        _departments = asStringList(payload['departments']);
        _summary = asJsonMap(payload['summary']);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showingAttendance = _selectedView == 'attendance';
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeading(
                title: 'Team directory',
                subtitle: 'Find your people and get a live view of attendance and planned time away.',
                trailing: IconButton.filledTonal(onPressed: _load, tooltip: 'Refresh team', icon: const Icon(Icons.refresh_rounded)),
              ),
              if (_error != null) ...[
                ErrorNotice(message: _error!, onRetry: _load),
                const SizedBox(height: 14),
              ],
              _TeamSummary(summary: _summary),
              const SizedBox(height: 17),
              AppPanel(
                padding: const EdgeInsets.all(13),
                child: LayoutBuilder(builder: (context, constraints) {
                  final filters = Row(children: [
                    const Icon(Icons.search_rounded, color: AppColors.muted, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _load(),
                        decoration: const InputDecoration(
                          hintText: 'Search employee, role or ID',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 9),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(onPressed: _load, tooltip: 'Search team', icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.blue)),
                    const SizedBox(width: 7),
                    Container(width: 1, height: 34, color: AppColors.line),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _selectedDepartment,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Department',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 5),
                        ),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('All departments')),
                          ..._departments.map((department) => DropdownMenuItem(value: department, child: Text(department, overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedDepartment = value ?? '');
                          _load();
                        },
                      ),
                    ),
                  ]);
                  if (constraints.maxWidth > 690) return filters;
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const Icon(Icons.search_rounded, color: AppColors.muted, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _load(),
                        decoration: const InputDecoration(hintText: 'Search employee, role or ID', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(vertical: 9)),
                      )),
                      IconButton(onPressed: _load, tooltip: 'Search team', icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.blue)),
                    ]),
                    const Divider(height: 1),
                    DropdownButtonFormField<String>(
                      value: _selectedDepartment,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Department', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All departments')),
                        ..._departments.map((department) => DropdownMenuItem(value: department, child: Text(department, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedDepartment = value ?? '');
                        _load();
                      },
                    ),
                  ]);
                }),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'attendance', label: Text('Today’s Attendance'), icon: Icon(Icons.how_to_reg_outlined)),
                  ButtonSegment(value: 'leaves', label: Text('Upcoming Leaves'), icon: Icon(Icons.event_available_outlined)),
                ],
                selected: {_selectedView},
                onSelectionChanged: (selection) => setState(() => _selectedView = selection.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 14),
              if (_loading && _members.isEmpty)
                const AppPanel(child: SizedBox(height: 190, child: LoadingView(label: 'Loading your team…')))
              else if (showingAttendance)
                _MemberGrid(members: _members)
              else
                _UpcomingLeaveList(leaves: _upcomingLeaves),
              if (!_loading && _members.isEmpty && showingAttendance)
                const AppPanel(child: EmptyNotice(title: 'No team members found', subtitle: 'Try a different name or department filter.', icon: Icons.groups_2_outlined)),
              if (!_loading && _upcomingLeaves.isEmpty && !showingAttendance)
                const AppPanel(child: EmptyNotice(title: 'No upcoming leaves', subtitle: 'Approved team leave will appear here when it is scheduled.', icon: Icons.event_note_outlined)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TeamSummary extends StatelessWidget {
  const _TeamSummary({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String, IconData, Color)>[
      ('Present', _value(summary['present']), Icons.login_rounded, AppColors.success),
      ('Checked out', _value(summary['checked_out']), Icons.logout_rounded, AppColors.blue),
      ('On leave', _value(summary['on_leave']), Icons.event_busy_outlined, const Color(0xFFAE751C)),
      ('Weekly off', _value(summary['weekly_off']), Icons.weekend_outlined, AppColors.teal),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 850 ? 4 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in stats)
            SizedBox(
              width: width,
              child: AppPanel(
                padding: const EdgeInsets.all(15),
                child: Row(children: [
                  Container(width: 35, height: 35, decoration: BoxDecoration(color: item.$4.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)), child: Icon(item.$3, color: item.$4, size: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.$2, style: const TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text(item.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600))])),
                ]),
              ),
            ),
        ],
      );
    });
  }
}

class _MemberGrid extends StatelessWidget {
  const _MemberGrid({required this.members});
  final List<Map<String, dynamic>> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1030 ? 3 : constraints.maxWidth >= 650 ? 2 : 1;
      final cardWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final member in members)
            SizedBox(width: cardWidth, child: _MemberCard(member: member)),
        ],
      );
    });
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member});
  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final name = stringValue(member['full_name'], fallback: 'Team member');
    final presence = stringValue(member['presence'], fallback: 'not_punched');
    final offDays = asStringList(member['weekly_off_days']);
    final punchIn = member['punch_in_at'];
    final detail = switch (presence) {
      'present' => 'Checked in ${formatDateTime(punchIn)}',
      'checked_out' => 'Last shift completed ${formatDateTime(member['punch_out_at'])}',
      'on_leave' => 'Approved leave today',
      'weekly_off' => 'Scheduled weekly off',
      _ => 'No punch recorded yet',
    };
    final shiftName = stringValue(member['shift_name']);
    return AppPanel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PersonAvatar(name: name, size: 46),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${stringValue(member['employee_code'])} · ${stringValue(member['department'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ])),
          StatusBadge(status: presence),
        ]),
        const SizedBox(height: 14),
        Text(stringValue(member['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(stringValue(member['employment_category_label'], fallback: stringValue(member['employment_type'])), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 11),
        Row(children: [const Icon(Icons.schedule_rounded, color: AppColors.blue, size: 15), const SizedBox(width: 7), Expanded(child: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)))]),
        const SizedBox(height: 7),
        Row(children: [const Icon(Icons.weekend_outlined, color: AppColors.muted, size: 15), const SizedBox(width: 7), Expanded(child: Text(offDays.isEmpty ? 'Weekly off not set' : 'Weekly off · ${offDays.join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)))]),
        if (shiftName.isNotEmpty) ...[
          const SizedBox(height: 7),
          Row(children: [const Icon(Icons.view_timeline_outlined, color: AppColors.muted, size: 15), const SizedBox(width: 7), Expanded(child: Text('$shiftName · ${stringValue(member['shift_start_time'])}–${stringValue(member['shift_end_time'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)))]),
        ],
      ]),
    );
  }
}

class _UpcomingLeaveList extends StatelessWidget {
  const _UpcomingLeaveList({required this.leaves});
  final List<Map<String, dynamic>> leaves;

  @override
  Widget build(BuildContext context) {
    if (leaves.isEmpty) return const SizedBox.shrink();
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 7),
      child: Column(children: [
        for (var index = 0; index < leaves.length; index++) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: PersonAvatar(name: stringValue(leaves[index]['employee_name'], fallback: 'Team member'), size: 42),
            title: Text(stringValue(leaves[index]['employee_name'], fallback: 'Team member'), style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w800)),
            subtitle: Text('${stringValue(leaves[index]['leave_type'])} · ${stringValue(leaves[index]['department'])}\n${formatDate(leaves[index]['start_date'])} – ${formatDate(leaves[index]['end_date'])}', style: const TextStyle(color: AppColors.muted, height: 1.5, fontSize: 10)),
            isThreeLine: true,
            trailing: leaves[index]['is_current'] == true ? const StatusBadge(status: 'on_leave') : const Icon(Icons.event_available_outlined, color: AppColors.teal, size: 19),
          ),
          if (index < leaves.length - 1) const Divider(height: 1),
        ],
      ]),
    );
  }
}

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _value(Object? value) => value?.toString() ?? '0';
