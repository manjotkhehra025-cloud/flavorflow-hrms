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

class KycLettersScreen extends StatefulWidget {
  const KycLettersScreen({super.key});

  @override
  State<KycLettersScreen> createState() => _KycLettersScreenState();
}

class _KycLettersScreenState extends State<KycLettersScreen> {
  List<Map<String, dynamic>> _documents = const [];
  List<Map<String, dynamic>> _employees = const [];
  List<String> _documentTypes = const [];
  bool _loading = true;
  bool _saving = false;
  bool _creatingLetter = false;
  String? _error;
  int? _letterEmployeeId;
  String _letterType = 'Bonafide / Employment Letter';

  bool get _canManage => AppScope.of(context).user!.can('kyc.manage');

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
        api.get('kyc-documents'),
        api.get('employees'),
      ]);
      if (!mounted) return;
      final kycResponse = asJsonMap(responses[0]);
      final employees = asJsonList(asJsonMap(responses[1])['items']);
      setState(() {
        _documents = asJsonList(kycResponse['items']);
        _documentTypes = asStringList(kycResponse['document_types']);
        _employees = employees;
        if (_letterEmployeeId == null && employees.isNotEmpty) {
          _letterEmployeeId = int.tryParse(stringValue(employees.first['id']));
        }
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addDocument() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _KycDocumentDialog(
        documentTypes: _documentTypes,
        employees: _canManage ? _employees : const [],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).api.post('kyc-documents', result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('KYC metadata submitted for HR review.')),
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _verify(Map<String, dynamic> document, String decision) async {
    try {
      await AppScope.of(context).api.patch('kyc-documents/${document['id']}/verification', {
        'decision': decision,
        'note': decision == 'verified' ? 'Reviewed by HR.' : 'Please contact People Ops for follow-up.',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(decision == 'verified' ? 'KYC item verified.' : 'KYC item marked for follow-up.')),
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _generateLetter() async {
    final employee = _findEmployee(_employees, _letterEmployeeId);
    if (employee == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No employee profile is available for the letter.')));
      return;
    }
    setState(() => _creatingLetter = true);
    try {
      final bytes = await _buildEmploymentLetter(employee, _letterType);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'FlavorFlow_${_letterType.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_${stringValue(employee['employee_code'])}.pdf',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not prepare this letter on the device.')));
      }
    } finally {
      if (mounted) setState(() => _creatingLetter = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    final canAdd = user.canAny(const ['kyc.create.self', 'kyc.manage']);
    final pendingCount = _documents.where((item) => stringValue(item['status']) == 'pending').length;
    final letterEmployee = _findEmployee(_employees, _letterEmployeeId);

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'KYC & Letters',
                  subtitle: 'Track document status and prepare HR-review drafts.',
                  trailing: canAdd ? PrimaryButton(label: _saving ? 'Saving…' : 'Add KYC item', icon: Icons.add_rounded, busy: _saving, onPressed: _saving ? null : _addDocument) : null,
                ),
                if (_error != null) ...[
                  ErrorNotice(message: _error!, onRetry: _load),
                  const SizedBox(height: 14),
                ],
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.softAmber, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFFFE2B0))),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lock_outline_rounded, color: Color(0xFFAC741E), size: 18),
                    SizedBox(width: 9),
                    Expanded(child: Text('Privacy note: this tracker stores only document type, expiry date, and an optional last-four hint. Do not enter a full Aadhaar, PAN, bank, or other identifier. File upload and encryption-at-rest are not configured in this database.', style: TextStyle(color: AppColors.ink, fontSize: 11, height: 1.45))),
                  ]),
                ),
                const SizedBox(height: 15),
                Row(children: [
                  Expanded(child: _KycSummaryCard(title: 'KYC items', value: '${_documents.length}', subtitle: 'Visible to your role', icon: Icons.folder_shared_outlined, tint: AppColors.blue)),
                  const SizedBox(width: 10),
                  Expanded(child: _KycSummaryCard(title: 'Pending review', value: '$pendingCount', subtitle: 'Awaiting People Ops', icon: Icons.pending_actions_rounded, tint: const Color(0xFFB77A1C))),
                ]),
                const SizedBox(height: 17),
                AppPanel(
                  padding: const EdgeInsets.all(17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [const Expanded(child: Text('KYC Locker', style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800))), Text('${_documents.length} items', style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700))]),
                      const SizedBox(height: 4),
                      const Text('Metadata-only checklist; full document files are not stored by this version.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                      const SizedBox(height: 12),
                      if (_loading && _documents.isEmpty)
                        const SizedBox(height: 115, child: LoadingView(label: 'Loading KYC items…'))
                      else if (_documents.isEmpty)
                        const EmptyNotice(title: 'No KYC items yet', subtitle: 'Add a document type and optional expiry date to start a checklist.', icon: Icons.folder_open_outlined)
                      else
                        ..._documents.map((document) => _KycDocumentRow(
                              document: document,
                              canManage: _canManage,
                              onVerify: () => _verify(document, 'verified'),
                              onReject: () => _verify(document, 'rejected'),
                            )),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppPanel(
                  padding: const EdgeInsets.all(17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Letters & certificates', style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text('Create a local PDF draft from the employee profile; HR must verify details and sign before official use.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
                      const SizedBox(height: 13),
                      DropdownButtonFormField<String>(
                        value: _letterType,
                        decoration: const InputDecoration(labelText: 'Letter type'),
                        items: const [
                          DropdownMenuItem(value: 'Bonafide / Employment Letter', child: Text('Bonafide / Employment Letter')),
                          DropdownMenuItem(value: 'Factory Duty Letter', child: Text('Factory Duty Letter')),
                          DropdownMenuItem(value: 'Service / Experience Letter', child: Text('Service / Experience Letter')),
                        ],
                        onChanged: (value) { if (value != null) setState(() => _letterType = value); },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: _letterEmployeeId,
                        decoration: const InputDecoration(labelText: 'Employee'),
                        items: _employees.map((employee) => DropdownMenuItem(
                          value: int.tryParse(stringValue(employee['id'])),
                          child: Text('${stringValue(employee['full_name'])} · ${stringValue(employee['employee_code'])}'),
                        )).toList(),
                        onChanged: (value) => setState(() => _letterEmployeeId = value),
                      ),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: _creatingLetter ? 'Preparing PDF…' : 'Create letter draft',
                        icon: Icons.picture_as_pdf_outlined,
                        busy: _creatingLetter,
                        onPressed: _creatingLetter || letterEmployee == null ? null : _generateLetter,
                        expand: true,
                      ),
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

class _KycSummaryCard extends StatelessWidget {
  const _KycSummaryCard({required this.title, required this.value, required this.subtitle, required this.icon, required this.tint});
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) => AppPanel(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: tint, size: 19)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600)), const SizedBox(height: 3), Text(value, style: const TextStyle(color: AppColors.ink, fontSize: 19, fontWeight: FontWeight.w800)), Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 9))])),
        ]),
      );
}

class _KycDocumentRow extends StatelessWidget {
  const _KycDocumentRow({required this.document, required this.canManage, required this.onVerify, required this.onReject});
  final Map<String, dynamic> document;
  final bool canManage;
  final VoidCallback onVerify;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final status = stringValue(document['status'], fallback: 'pending');
    final statusColor = status == 'verified' ? AppColors.success : status == 'rejected' ? const Color(0xFFC94D54) : const Color(0xFFB77A1C);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.description_outlined, color: AppColors.blue, size: 19)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${stringValue(document['document_type'])} · ${stringValue(document['masked_identifier'], fallback: 'Not provided')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text('${stringValue(document['employee_name'], fallback: 'My profile')} · Expires ${stringValue(document['expiry_date'], fallback: 'not set')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        ])),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)), child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 8, fontWeight: FontWeight.w800))),
        if (canManage && status == 'pending') ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Review KYC item',
            onSelected: (value) { if (value == 'verified') onVerify(); if (value == 'rejected') onReject(); },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'verified', child: Text('Mark verified')),
              PopupMenuItem(value: 'rejected', child: Text('Request follow-up')),
            ],
          ),
        ],
      ]),
    );
  }
}

class _KycDocumentDialog extends StatefulWidget {
  const _KycDocumentDialog({required this.documentTypes, required this.employees});
  final List<String> documentTypes;
  final List<Map<String, dynamic>> employees;

  @override
  State<_KycDocumentDialog> createState() => _KycDocumentDialogState();
}

class _KycDocumentDialogState extends State<_KycDocumentDialog> {
  final _lastFour = TextEditingController();
  final _expiry = TextEditingController();
  String? _documentType;
  int? _employeeId;

  @override
  void initState() {
    super.initState();
    _documentType = widget.documentTypes.isEmpty ? null : widget.documentTypes.first;
    if (widget.employees.isNotEmpty) _employeeId = int.tryParse(stringValue(widget.employees.first['id']));
  }

  @override
  void dispose() {
    _lastFour.dispose();
    _expiry.dispose();
    super.dispose();
  }

  void _save() {
    final lastFour = _lastFour.text.trim();
    final expiry = _expiry.text.trim();
    if (lastFour.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(lastFour)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter exactly four digits, or leave this field empty.')));
      return;
    }
    if (expiry.isNotEmpty && DateTime.tryParse(expiry) == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use an expiry date in YYYY-MM-DD format.')));
      return;
    }
    if (_documentType == null) return;
    Navigator.pop(context, <String, dynamic>{
      'document_type': _documentType,
      'last_four': lastFour,
      if (expiry.isNotEmpty) 'expiry_date': expiry,
      if (widget.employees.isNotEmpty && _employeeId != null) 'employee_id': _employeeId,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Add KYC item', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.employees.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: _employeeId,
                  decoration: const InputDecoration(labelText: 'Employee'),
                  items: widget.employees.map((employee) => DropdownMenuItem(value: int.tryParse(stringValue(employee['id'])), child: Text(stringValue(employee['full_name'])))).toList(),
                  onChanged: (value) => setState(() => _employeeId = value),
                ),
              DropdownButtonFormField<String>(
                value: _documentType,
                decoration: const InputDecoration(labelText: 'Document type'),
                items: widget.documentTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                onChanged: (value) => setState(() => _documentType = value),
              ),
              const SizedBox(height: 11),
              TextField(controller: _lastFour, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'Last four digits (optional)', helperText: 'Never enter a full ID or bank number.', counterText: '')),
              TextField(controller: _expiry, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Expiry date (YYYY-MM-DD, optional)')),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded, size: 17), label: const Text('Submit for review'))],
      );
}

Future<Uint8List> _buildEmploymentLetter(Map<String, dynamic> employee, String letterType) async {
  final pdf = pw.Document();
  final name = stringValue(employee['full_name'], fallback: 'Employee');
  final code = stringValue(employee['employee_code'], fallback: '—');
  final department = stringValue(employee['department'], fallback: '—');
  final title = stringValue(employee['title'], fallback: '—');
  final startDate = stringValue(employee['start_date'], fallback: '—');
  final today = _letterDate(DateTime.now());

  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(48),
    build: (context) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('FLAVORFLOW', style: pw.TextStyle(color: const PdfColor.fromInt(0xFF1E6FE0), fontSize: 14, fontWeight: pw.FontWeight.bold, letterSpacing: 1.4)),
        pw.SizedBox(height: 5),
        pw.Text('People Operations', style: const pw.TextStyle(color: PdfColor.fromInt(0xFF718198), fontSize: 10)),
        pw.SizedBox(height: 38),
        pw.Center(child: pw.Text(letterType.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8))),
        pw.SizedBox(height: 30),
        pw.Text('To whom it may concern,', style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 14),
        pw.Text('This draft confirms that the FlavorFlow HRMS employee record identifies $name (Employee ID: $code) as a $title in the $department department, with a recorded start date of $startDate.', style: const pw.TextStyle(fontSize: 11, lineSpacing: 5)),
        pw.SizedBox(height: 14),
        pw.Text('This document is generated from HRMS profile fields and is not an official certificate until reviewed, approved, and signed by an authorized People Operations representative.', style: const pw.TextStyle(fontSize: 10, lineSpacing: 4, color: PdfColor.fromInt(0xFF718198))),
        pw.Spacer(),
        pw.Text('Draft generated on $today', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF718198))),
        pw.SizedBox(height: 18),
        pw.Text('Authorized signature: ______________________________', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 10),
        pw.Text('FlavorFlow · Confidential HR document', style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF718198))),
      ],
    ),
  ));
  return pdf.save();
}

Map<String, dynamic>? _findEmployee(List<Map<String, dynamic>> employees, int? employeeId) {
  if (employeeId == null) return null;
  for (final employee in employees) {
    if (int.tryParse(stringValue(employee['id'])) == employeeId) return employee;
  }
  return null;
}

String _letterDate(DateTime date) {
  final day = date.day.toString().padLeft(2, "0");
  final month = date.month.toString().padLeft(2, "0");
  return '$day/$month/${date.year}';
}
