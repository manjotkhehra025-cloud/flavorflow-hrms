import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class IdCardScreen extends StatefulWidget {
  const IdCardScreen({super.key});

  @override
  State<IdCardScreen> createState() => _IdCardScreenState();
}

class _IdCardScreenState extends State<IdCardScreen> {
  List<Map<String, dynamic>> _cards = const [];
  List<Map<String, dynamic>> _passes = const [];
  bool _loading = true;
  bool _saving = false;
  bool _showCardBack = false;
  String? _error;
  String _section = 'card';
  String _passFilter = 'all';
  int? _selectedEmployeeId;

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
      final user = AppScope.of(context).user!;
      final api = AppScope.of(context).api;
      final responses = await Future.wait<dynamic>([
        user.canAny(const ['idcard.read', 'idcard.read.team', 'idcard.read.self', 'idcard.update'])
            ? api.get('id-cards')
            : Future<dynamic>.value(const <String, dynamic>{}),
        user.canAny(const ['gatepass.read', 'gatepass.read.team', 'gatepass.read.self', 'gatepass.create', 'gatepass.approve', 'gatepass.manage'])
            ? api.get('gate-passes')
            : Future<dynamic>.value(const <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final cards = asJsonList(asJsonMap(responses[0])['items']);
      final passes = asJsonList(asJsonMap(responses[1])['items']);
      final selectedExists = _selectedEmployeeId != null && cards.any(
        (card) => int.tryParse(stringValue(card['id'])) == _selectedEmployeeId,
      );
      setState(() {
        _cards = cards;
        _passes = passes;
        if (!selectedExists) {
          _selectedEmployeeId = int.tryParse(stringValue(cards.isEmpty ? null : cards.first['id']));
        }
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? get _selectedCard {
    for (final card in _cards) {
      if (int.tryParse(stringValue(card['id'])) == _selectedEmployeeId) return card;
    }
    return null;
  }

  Future<void> _editDetails() async {
    final card = _selectedCard;
    if (card == null) return;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _IdDetailsDialog(card: card),
    );
    if (values == null || !mounted) return;
    try {
      setState(() => _saving = true);
      final updated = await AppScope.of(context).api.patch('id-cards/${card['id']}', values);
      final result = asJsonMap(updated);
      if (!mounted) return;
      setState(() {
        _cards = _cards.map((item) => int.tryParse(stringValue(item['id'])) == _selectedEmployeeId ? result : item).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID-card details updated.')));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareCard() async {
    final card = _selectedCard;
    if (card == null) return;
    try {
      final bytes = await _buildCardPdf(card);
      final code = stringValue(card['employee_code'], fallback: 'employee').replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      await Printing.sharePdf(bytes: bytes, filename: 'FlavorFlow_ID_$code.pdf');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not prepare the ID card: $error')));
      }
    }
  }

  Future<void> _printCard() async {
    final card = _selectedCard;
    if (card == null) return;
    try {
      final bytes = await _buildCardPdf(card);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open print preview: $error')));
      }
    }
  }

  Future<void> _newPass() async {
    final user = AppScope.of(context).user!;
    final canIssueForOthers = user.can('gatepass.manage');
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _GatePassFormDialog(
        employees: canIssueForOthers ? _cards : const [],
        selectedEmployeeId: _selectedEmployeeId,
      ),
    );
    if (values == null || !mounted) return;
    try {
      setState(() => _saving = true);
      await AppScope.of(context).api.post('gate-passes', values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gate-pass request submitted.')));
      setState(() {
        _section = 'passes';
        _passFilter = 'all';
      });
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _decidePass(Map<String, dynamic> pass, String decision) async {
    try {
      setState(() => _saving = true);
      await AppScope.of(context).api.post('gate-passes/${pass['id']}/decision', {'decision': decision});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gate pass $decision.')));
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
    final card = _selectedCard;
    final canEdit = user.can('idcard.update');
    final canRequestPass = user.canAny(const ['gatepass.create', 'gatepass.manage']);
    final canReviewPass = user.canAny(const ['gatepass.approve', 'gatepass.manage']);
    final visiblePasses = _passes.where((pass) => _passFilter == 'all' || stringValue(pass['status']) == _passFilter).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeading(
                title: 'ID Card & Gate Pass',
                subtitle: 'Employee identity cards and digital pass requests, powered by current staff records.',
                trailing: IconButton.filledTonal(onPressed: _load, tooltip: 'Refresh ID details', icon: const Icon(Icons.refresh_rounded)),
              ),
              if (_error != null) ...[
                ErrorNotice(message: _error!, onRetry: _load),
                const SizedBox(height: 14),
              ],
              if (_cards.length > 1)
                AppPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: DropdownButtonFormField<int>(
                    value: _selectedEmployeeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Employee', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                    items: _cards.map((employee) => DropdownMenuItem(
                      value: int.tryParse(stringValue(employee['id'])),
                      child: Text('${stringValue(employee['full_name'])} · ${stringValue(employee['employee_code'])}', overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) => setState(() {
                      _selectedEmployeeId = value;
                      _showCardBack = false;
                    }),
                  ),
                ),
              if (_cards.length > 1) const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'card', label: Text('ID card'), icon: Icon(Icons.badge_outlined)),
                  ButtonSegment(value: 'passes', label: Text('Gate passes'), icon: Icon(Icons.confirmation_number_outlined)),
                ],
                selected: {_section},
                onSelectionChanged: (selection) => setState(() => _section = selection.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 15),
              if (_loading && _cards.isEmpty)
                const AppPanel(child: SizedBox(height: 190, child: LoadingView(label: 'Loading current employee records…')))
              else if (_section == 'card') ...[
                if (card == null)
                  const AppPanel(child: EmptyNotice(title: 'No employee card is available', subtitle: 'Your role may not have access to an employee ID card.', icon: Icons.badge_outlined))
                else ...[
                  _CardSideToggle(showBack: _showCardBack, onChanged: (value) => setState(() => _showCardBack = value)),
                  const SizedBox(height: 12),
                  Center(child: _EmployeeBadge(card: card, showBack: _showCardBack)),
                  const SizedBox(height: 14),
                  AppPanel(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton.icon(onPressed: _saving ? null : _printCard, icon: const Icon(Icons.print_outlined, size: 17), label: const Text('Print card')),
                        OutlinedButton.icon(onPressed: _saving ? null : _shareCard, icon: const Icon(Icons.download_outlined, size: 17), label: const Text('Download / share PDF')),
                        if (canEdit) FilledButton.tonalIcon(onPressed: _saving ? null : _editDetails, icon: const Icon(Icons.edit_outlined, size: 17), label: const Text('Edit contact details')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                  const _PrivacyHint(),
                ],
              ] else ...[
                Row(children: [
                  const Expanded(child: Text('Digital gate passes', style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w800))),
                  if (canRequestPass) PrimaryButton(label: 'Request pass', icon: Icons.add_rounded, onPressed: _saving ? null : _newPass),
                ]),
                const SizedBox(height: 6),
                const Text('Submit a reason and validity window. A manager or HR approver issues the pass reference after approval.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.45)),
                const SizedBox(height: 14),
                _GatePassFilter(selected: _passFilter, onSelected: (value) => setState(() => _passFilter = value)),
                const SizedBox(height: 12),
                if (visiblePasses.isEmpty)
                  const AppPanel(child: EmptyNotice(title: 'No gate-pass requests', subtitle: 'Your requests and their review status will appear here.', icon: Icons.confirmation_number_outlined))
                else
                  Column(children: [
                    for (final pass in visiblePasses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _GatePassCard(
                          pass: pass,
                          showEmployee: user.canAny(const ['gatepass.read', 'gatepass.read.team', 'gatepass.manage']),
                          canReview: canReviewPass && stringValue(pass['status']) == 'pending',
                          onApprove: () => _decidePass(pass, 'approved'),
                          onReject: () => _decidePass(pass, 'rejected'),
                          busy: _saving,
                        ),
                      ),
                  ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _CardSideToggle extends StatelessWidget {
  const _CardSideToggle({required this.showBack, required this.onChanged});
  final bool showBack;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Center(
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Front')),
            ButtonSegment(value: true, label: Text('Back')),
          ],
          selected: {showBack},
          onSelectionChanged: (selection) => onChanged(selection.first),
          showSelectedIcon: false,
        ),
      );
}

class _EmployeeBadge extends StatelessWidget {
  const _EmployeeBadge({required this.card, required this.showBack});
  final Map<String, dynamic> card;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final badgeWidth = width < 430 ? width - 52 : 390.0;
    return SizedBox(
      width: badgeWidth,
      child: AspectRatio(
        aspectRatio: 1.58,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            gradient: showBack
                ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0C2B47), Color(0xFF145E67)])
                : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.navy, Color(0xFF174B70), Color(0xFF087A7C)]),
            boxShadow: const [BoxShadow(color: Color(0x24112C43), blurRadius: 22, offset: Offset(0, 12))],
          ),
          child: showBack ? _BadgeBack(card: card) : _BadgeFront(card: card),
        ),
      ),
    );
  }
}

class _BadgeFront extends StatelessWidget {
  const _BadgeFront({required this.card});
  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(19),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 31, height: 31, decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), gradient: const LinearGradient(colors: [AppColors.blue, AppColors.teal])), child: const Icon(Icons.bubble_chart_rounded, color: Colors.white, size: 19)),
          const SizedBox(width: 9),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('FlavorFlow', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            Text('EMPLOYEE ID', style: TextStyle(color: Color(0xFFB5D1DC), fontSize: 8, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
          ])),
          StatusBadge(status: stringValue(card['status'], fallback: 'active')),
        ]),
        const Spacer(),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          PersonAvatar(name: stringValue(card['full_name']), size: 56),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stringValue(card['full_name'], fallback: 'Team member'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(stringValue(card['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFD3E2E8), fontSize: 10)),
            const SizedBox(height: 3),
            Text(stringValue(card['department']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFA9C4D0), fontSize: 9)),
          ])),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('ID', style: TextStyle(color: Color(0xFF9CBBC8), fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: .7)),
          const SizedBox(width: 7),
          Text(stringValue(card['employee_code']), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const Spacer(),
          Text(stringValue(card['employment_category_label'], fallback: stringValue(card['employment_type'], fallback: 'Employee')), style: const TextStyle(color: Color(0xFFBDDAE0), fontSize: 9, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}

class _BadgeBack extends StatelessWidget {
  const _BadgeBack({required this.card});
  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.verified_user_outlined, color: Color(0xFF8FE4D2), size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('EMPLOYEE DETAILS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1))),
          Text(stringValue(card['employee_code']), style: const TextStyle(color: Color(0xFFB9D2DC), fontSize: 9, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 13),
        _BadgeInfo(label: 'WORK EMAIL', value: _idCardDetail(card, 'email'), icon: Icons.alternate_email_rounded),
        const SizedBox(height: 8),
        _BadgeInfo(label: 'PHONE', value: _idCardDetail(card, 'phone'), icon: Icons.phone_outlined),
        const SizedBox(height: 8),
        Expanded(child: _BadgeInfo(label: 'ADDRESS', value: _idCardDetail(card, 'address'), icon: Icons.location_on_outlined)),
        const Text('If found, please return this card to FlavorFlow People Operations.', style: TextStyle(color: Color(0xFFB8D0D7), fontSize: 8, height: 1.4)),
      ]),
    );
  }
}

class _BadgeInfo extends StatelessWidget {
  const _BadgeInfo({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: const Color(0xFF8FE4D2), size: 15),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xFF9DBCC8), fontSize: 7, fontWeight: FontWeight.w800, letterSpacing: .8)),
          const SizedBox(height: 2),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600, height: 1.2)),
        ])),
      ]);
}

class _PrivacyHint extends StatelessWidget {
  const _PrivacyHint();

  @override
  Widget build(BuildContext context) => const AppPanel(
        padding: EdgeInsets.all(13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_outline_rounded, color: AppColors.blue, size: 17),
          SizedBox(width: 9),
          Expanded(child: Text('Phone and mailing address are protected by your role permissions. Employee identity, role, department and employment status are populated from current employee records.', style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4))),
        ]),
      );
}

class _GatePassFilter extends StatelessWidget {
  const _GatePassFilter({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final filter in const ['all', 'pending', 'approved', 'rejected']) ...[
            ChoiceChip(
              label: Text(filter == 'all' ? 'All' : _titleCase(filter)),
              selected: selected == filter,
              onSelected: (_) => onSelected(filter),
              selectedColor: AppColors.softBlue,
              labelStyle: TextStyle(color: selected == filter ? AppColors.blue : AppColors.ink, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
          ],
        ]),
      );
}

class _GatePassCard extends StatelessWidget {
  const _GatePassCard({
    required this.pass,
    required this.showEmployee,
    required this.canReview,
    required this.onApprove,
    required this.onReject,
    required this.busy,
  });
  final Map<String, dynamic> pass;
  final bool showEmployee;
  final bool canReview;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final code = stringValue(pass['reference_code']);
    final expired = DateTime.tryParse(stringValue(pass['valid_until']))?.isBefore(DateTime.now()) ?? false;
    return AppPanel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.confirmation_number_outlined, color: AppColors.blue, size: 20)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_passTypeLabel(stringValue(pass['pass_type'])), style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${showEmployee ? '${stringValue(pass['employee_name'])} · ' : ''}${stringValue(pass['employee_code'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ])),
          StatusBadge(status: expired && stringValue(pass['status']) == 'approved' ? 'expired' : stringValue(pass['status'], fallback: 'pending')),
        ]),
        const SizedBox(height: 12),
        Text(stringValue(pass['purpose']), style: const TextStyle(color: AppColors.ink, fontSize: 11, height: 1.4)),
        const SizedBox(height: 9),
        Row(children: [
          const Icon(Icons.schedule_rounded, color: AppColors.muted, size: 15),
          const SizedBox(width: 6),
          Expanded(child: Text('${formatDateTime(pass['valid_from'])} – ${formatDateTime(pass['valid_until'])}', style: const TextStyle(color: AppColors.muted, fontSize: 10))),
        ]),
        if (code.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(color: AppColors.softGreen, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFD4F0E3))),
            child: Row(children: [
              const Icon(Icons.qr_code_2_rounded, color: AppColors.success, size: 22),
              const SizedBox(width: 9),
              const Text('DIGITAL PASS CODE', style: TextStyle(color: AppColors.muted, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: .7)),
              const Spacer(),
              SelectableText(code, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ]),
          ),
        ],
        if (stringValue(pass['decision_note']).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Reviewer note: ${stringValue(pass['decision_note'])}', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        ],
        if (canReview) ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: busy ? null : onReject, child: const Text('Decline')),
            const SizedBox(width: 6),
            FilledButton.icon(onPressed: busy ? null : onApprove, icon: const Icon(Icons.check_rounded, size: 16), label: const Text('Approve')),
          ]),
        ],
      ]),
    );
  }
}

class _IdDetailsDialog extends StatefulWidget {
  const _IdDetailsDialog({required this.card});
  final Map<String, dynamic> card;

  @override
  State<_IdDetailsDialog> createState() => _IdDetailsDialogState();
}

class _IdDetailsDialogState extends State<_IdDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: stringValue(widget.card['phone']));
    _address = TextEditingController(text: stringValue(widget.card['address']));
  }

  @override
  void dispose() {
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{'phone': _phone.text.trim(), 'address': _address.text.trim()});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Edit ID-card details', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 430,
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'), validator: (value) => (value?.length ?? 0) > 40 ? 'Keep phone under 40 characters' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _address, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Mailing address'), validator: (value) => (value?.length ?? 0) > 240 ? 'Keep address under 240 characters' : null),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton.icon(onPressed: _submit, icon: const Icon(Icons.check_rounded, size: 17), label: const Text('Save details')),
        ],
      );
}

class _GatePassFormDialog extends StatefulWidget {
  const _GatePassFormDialog({required this.employees, required this.selectedEmployeeId});
  final List<Map<String, dynamic>> employees;
  final int? selectedEmployeeId;

  @override
  State<_GatePassFormDialog> createState() => _GatePassFormDialogState();
}

class _GatePassFormDialogState extends State<_GatePassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _purpose = TextEditingController();
  String _type = 'personal_exit';
  late DateTime _from;
  late DateTime _until;
  int? _employeeId;
  bool _datesInvalid = false;

  @override
  void initState() {
    super.initState();
    _from = DateTime.now().add(const Duration(minutes: 30));
    _until = _from.add(const Duration(hours: 2));
    _employeeId = widget.selectedEmployeeId ?? (widget.employees.isEmpty ? null : int.tryParse(stringValue(widget.employees.first['id'])));
  }

  @override
  void dispose() {
    _purpose.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateUtils.dateOnly(initial),
      firstDate: DateUtils.dateOnly(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _changeDate({required bool start}) async {
    final picked = await _pickDateTime(start ? _from : _until);
    if (picked == null) return;
    setState(() {
      if (start) {
        _from = picked;
        if (!_until.isAfter(_from)) _until = _from.add(const Duration(hours: 1));
      } else {
        _until = picked;
      }
      _datesInvalid = false;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (!_until.isAfter(_from) || _from.isBefore(DateTime.now().subtract(const Duration(hours: 1)))) {
      setState(() => _datesInvalid = true);
      return;
    }
    final result = <String, dynamic>{
      'pass_type': _type,
      'purpose': _purpose.text.trim(),
      'valid_from': _isoWithOffset(_from),
      'valid_until': _isoWithOffset(_until),
    };
    if (widget.employees.isNotEmpty && _employeeId != null) result['employee_id'] = _employeeId;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Request a gate pass', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 450,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.employees.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: _employeeId,
                  decoration: const InputDecoration(labelText: 'Employee'),
                  items: widget.employees.map((employee) => DropdownMenuItem(value: int.tryParse(stringValue(employee['id'])), child: Text('${stringValue(employee['full_name'])} · ${stringValue(employee['employee_code'])}', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (value) => setState(() => _employeeId = value),
                ),
              if (widget.employees.isNotEmpty) const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Pass category'),
                items: const [
                  DropdownMenuItem(value: 'personal_exit', child: Text('Personal exit')),
                  DropdownMenuItem(value: 'official_duty', child: Text('Official duty')),
                  DropdownMenuItem(value: 'visitor', child: Text('Visitor / guest')),
                ],
                onChanged: (value) => setState(() => _type = value ?? 'personal_exit'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _PassDateField(label: 'Valid from', value: _from, onTap: () => _changeDate(start: true))),
                const SizedBox(width: 10),
                Expanded(child: _PassDateField(label: 'Valid until', value: _until, onTap: () => _changeDate(start: false))),
              ]),
              if (_datesInvalid) const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(top: 6), child: Text('Choose a valid future time window.', style: TextStyle(color: Color(0xFFC94D54), fontSize: 11)))),
              const SizedBox(height: 12),
              TextFormField(controller: _purpose, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Purpose'), validator: (value) => (value?.trim().isEmpty ?? true) ? 'Purpose is required' : null),
            ])),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton.icon(onPressed: _submit, icon: const Icon(Icons.send_rounded, size: 17), label: const Text('Submit request')),
        ],
      );
}

class _PassDateField extends StatelessWidget {
  const _PassDateField({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.schedule_rounded, size: 17)),
          child: Text(_formatDateAndTime(value), style: const TextStyle(color: AppColors.ink, fontSize: 10)),
        ),
      );
}

Future<Uint8List> _buildCardPdf(Map<String, dynamic> card) async {
  final pdf = pw.Document();
  const navy = PdfColor.fromInt(0xFF081C33);
  const teal = PdfColor.fromInt(0xFF087A7C);
  const muted = PdfColor.fromInt(0xFF718198);
  pw.Widget side(String title, List<pw.Widget> lines) => pw.Container(
        width: 390,
        height: 242,
        padding: const pw.EdgeInsets.all(23),
        decoration: pw.BoxDecoration(
          color: navy,
          borderRadius: pw.BorderRadius.circular(18),
          border: pw.Border.all(color: teal, width: 2),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('FLAVORFLOW  ·  $title', style: pw.TextStyle(color: PdfColors.white, fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
          pw.SizedBox(height: 22),
          ...lines,
          pw.Spacer(),
          pw.Text('People, connected.', style: const pw.TextStyle(color: PdfColor.fromInt(0xFFB9D2DC), fontSize: 9)),
        ]),
      );
  pw.Widget field(String label, Object? value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label.toUpperCase(), style: pw.TextStyle(color: const PdfColor.fromInt(0xFF9DBCC8), fontSize: 7, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
          pw.SizedBox(height: 3),
          pw.Text(_pdfValue(value), style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ]),
      );
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    build: (_) => pw.Center(child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
      side('EMPLOYEE ID · FRONT', [
        field('Employee name', card['full_name']),
        field('Employee ID', card['employee_code']),
        field('Department', card['department']),
        field('Role', card['title']),
      ]),
      pw.SizedBox(height: 24),
      side('EMPLOYEE ID · BACK', [
        field('Work email', _idCardDetail(card, 'email')),
        field('Phone', _idCardDetail(card, 'phone')),
        field('Address', _idCardDetail(card, 'address')),
      ]),
      pw.SizedBox(height: 18),
      pw.Text('Confidential staff identity details. Share only with authorized recipients.', style: const pw.TextStyle(color: muted, fontSize: 8)),
    ])),
  ));
  return pdf.save();
}

String _isoWithOffset(DateTime value) {
  final offset = value.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  final sign = offset.isNegative ? '-' : '+';
  final hoursText = (minutes ~/ 60).toString().padLeft(2, '0');
  final minutesText = (minutes % 60).toString().padLeft(2, '0');
  final timestamp = value.toIso8601String().substring(0, 19);
  return '$timestamp$sign$hoursText:$minutesText';
}

String _idCardDetail(Map<String, dynamic> card, String key) {
  if (!card.containsKey(key)) return 'Restricted';
  final value = stringValue(card[key]).trim();
  return value.isEmpty ? 'Not provided' : value;
}

String _pdfValue(Object? value) {
  final text = stringValue(value).trim();
  return text.isEmpty ? 'Not provided' : text;
}

String _formatDateAndTime(DateTime value) => '${_dateString(value)} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _dateString(DateTime value) => '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _titleCase(String value) => value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
String _passTypeLabel(String value) => switch (value) {
      'personal_exit' => 'Personal exit pass',
      'official_duty' => 'Official duty pass',
      'visitor' => 'Visitor / guest pass',
      _ => _titleCase(value.replaceAll('_', ' ')),
    };
