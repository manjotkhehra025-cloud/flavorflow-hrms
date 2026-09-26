import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Employee detail — web /employees/[id] parity (row 13 slice 1).
/// Overview + attendance (31d) + leaves + balances + KYC + letters + pay history + payroll + perms link.
class EmployeeDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const EmployeeDetailScreen({super.key, required this.id});

  @override
  ConsumerState<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/api/employees/${widget.id}');
      if (!mounted) return;
      setState(() {
        _data = res.data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(
        title: Text(_data == null ? T.s('Employee', lang) : (_data!['employee']?['name'] ?? T.s('Employee', lang))),
        actions: [
          if (_data != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: HMC.primary))
          : _error != null
              ? ListView(children: [HmMessage(icon: Icons.error_outline, text: _error!, onRetry: _load, retryLabel: T.s('Retry', lang))])
              : _data == null
                  ? ListView(children: [HmMessage(icon: Icons.person_off_outlined, text: T.s('Employee not found', lang))])
                  : _buildContent(lang),
    );
  }

  Widget _buildContent(String lang) {
    final d = _data!;
    final emp = Map<String, dynamic>.from(d['employee'] as Map? ?? {});
    final login = d['login'] is Map ? Map<String, dynamic>.from(d['login'] as Map) : null;
    final perms = d['permissions'] is Map ? Map<String, dynamic>.from(d['permissions'] as Map) : null;
    final attendance = asMaps(d['attendance']);
    final leaves = asMaps(d['leaves']);
    final balances = asMaps(d['balances']);
    final kycDocs = asMaps(d['kycDocs']);
    final letters = asMaps(d['letters']);
    final advances = asMaps(d['advances']);
    final salaryRevs = asMaps(d['salaryRevisions']);
    final payroll = asMaps(d['payroll']);

    final photo = emp['photo'] as String?;
    final name = '${emp['name'] ?? ''}';
    final code = '${emp['code'] ?? ''}';
    final status = '${emp['status'] ?? 'ACTIVE'}';
    final category = '${emp['category'] ?? 'OFFICIAL'}';
    final isYellow = category == 'YELLOW_CARD';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        // Hero card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: HMC.ink,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  HmAvatar(name: name, photo: photo, radius: 34),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(height: 2),
                      Text('$code · ${emp['designation']?['title'] ?? T.s('No designation', lang)}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                      const SizedBox(height: 8),
                      Row(children: [
                        _Badge(text: status, tone: status == 'ACTIVE' ? HMC.primary : Colors.grey),
                        const SizedBox(width: 6),
                        _Badge(text: isYellow ? 'YELLOW CARD' : 'OFFICIAL', tone: isYellow ? HMC.amber : HMC.primary),
                      ]),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InfoGrid(emp: emp, lang: lang),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Login & perms quick row
        Row(children: [
          Expanded(
            child: _MiniCard(
              icon: Icons.login,
              title: login == null ? T.s('No login', lang) : '${login['email']}',
              subtitle: login == null ? T.s('No account linked', lang) : '${login['role']} · ${login['isActive'] == true ? 'Active' : 'Inactive'}',
              tone: login == null ? Colors.grey : HMC.primaryDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniCard(
              icon: Icons.admin_panel_settings_outlined,
              title: T.s('Permissions', lang),
              subtitle: perms == null
                  ? T.s('Default (all on)', lang)
                  : '${perms.values.where((v) => v == false).length} ${T.s('off', lang)}',
              tone: HMC.ink,
              onTap: () => context.push('/permissions/${emp['id']}'),
            ),
          ),
        ]),
        const SizedBox(height: 14),

        // Department / shift / manager / weekly off
        _Section(
          title: T.s('Work details', lang),
          children: [
            _Row(k: T.s('Department', lang), v: emp['department']?['name'] ?? '—'),
            _Row(k: T.s('Designation', lang), v: emp['designation']?['title'] ?? '—'),
            _Row(k: T.s('Shift', lang), v: emp['shift'] != null ? '${emp['shift']['name']} (${emp['shift']['startTime']})' : T.s('General (default)', lang)),
            _Row(k: T.s('Weekly Off', lang), v: _weekday(emp['weeklyOff'] as int? ?? 0, lang)),
            _Row(k: T.s('Manager', lang), v: emp['manager']?['name'] ?? '—'),
            _Row(k: T.s('Joined', lang), v: '${emp['joinDate'] ?? '—'}'),
            _Row(k: T.s('Contractor', lang), v: emp['contractor'] ?? '—'),
          ],
        ),

        _Section(
          title: T.s('Contact & personal', lang),
          children: [
            _Row(k: T.s('Email', lang), v: emp['email'] ?? '—'),
            _Row(k: T.s('Phone', lang), v: emp['phone'] ?? '—'),
            _Row(k: T.s('Gender', lang), v: emp['gender'] ?? '—'),
            _Row(k: T.s('Blood Group', lang), v: emp['bloodGroup'] ?? '—'),
            _Row(k: T.s('Emergency Contact', lang), v: emp['emergencyPhone'] ?? '—'),
            _Row(k: T.s('DOB', lang), v: emp['dateOfBirth'] ?? '—'),
            _Row(k: T.s('Address', lang), v: emp['address'] ?? '—'),
          ],
        ),

        _Section(
          title: T.s('Pay setup', lang),
          children: [
            _Row(k: T.s('Salary Type', lang), v: '${emp['salaryType'] ?? 'MONTHLY'}'),
            _Row(k: T.s('Base Salary', lang), v: emp['baseSalary'] != null ? inr(emp['baseSalary']) : '—'),
            _Row(k: T.s('Daily Rate', lang), v: emp['dailyRate'] != null ? inr(emp['dailyRate']) : '—'),
            _Row(k: T.s('OT Rate', lang), v: emp['otRate'] != null ? '${inr(emp['otRate'])}/hr' : T.s('Auto', lang)),
            _Row(k: T.s('Bank Account', lang), v: emp['bankAccount'] ?? '—'),
            _Row(k: T.s('IFSC', lang), v: emp['ifsc'] ?? '—'),
            _Row(k: T.s('PF', lang), v: emp['pfEnabled'] == true ? (emp['pfNumber'] ?? 'Enabled') : '—'),
            _Row(k: T.s('ESI', lang), v: emp['esiEnabled'] == true ? (emp['esiNumber'] ?? 'Enabled') : '—'),
          ],
        ),

        // Balances
        if (balances.isNotEmpty)
          _Section(
            title: T.s('Leave balances', lang),
            children: balances
                .map((b) => _Row(
                      k: '${b['type']}',
                      v: '${b['remaining']} / ${b['quota']} ${T.s('left', lang)}',
                    ))
                .toList(),
          ),

        // Attendance last 31d
        _Section(
          title: T.s('Attendance — this month', lang),
          trailing: Text('${attendance.length} ${T.s('days', lang)}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w700)),
          children: attendance.isEmpty
              ? [Text(T.s('No attendance yet', lang), style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5))]
              : attendance.take(12).map((a) {
                  final status = '${a['status']}';
                  final tone = switch (status) {
                    'PRESENT' => HMC.primaryDark,
                    'HALF_DAY' => Colors.purple,
                    'LEAVE' => HMC.amber,
                    'HOLIDAY' => Colors.blueGrey,
                    _ => HMC.danger,
                  };
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text('${a['date']}'.split('-').last, style: TextStyle(fontWeight: FontWeight.w900, color: tone, fontSize: 13)))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${a['date']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: HMC.ink)),
                        Text('${a['checkIn'] != null ? shortStamp(a['checkIn']) : '—'} → ${a['checkOut'] != null ? shortStamp(a['checkOut']) : '—'}',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                      ])),
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: tone))),
                    ]),
                  );
                }).toList(),
        ),

        // Recent leaves
        _Section(
          title: T.s('Recent leaves', lang),
          children: leaves.isEmpty
              ? [Text(T.s('No leave requests yet', lang), style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5))]
              : leaves.take(8).map((l) {
                  final st = '${l['status']}';
                  final tone = st == 'APPROVED' ? HMC.primaryDark : st == 'REJECTED' ? HMC.danger : HMC.amber;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${l['type']} · ${l['fromDate']} → ${l['toDate']} (${l['days']}d)',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: HMC.ink)),
                        if ((l['reason'] as String?)?.isNotEmpty == true)
                          Text('${l['reason']}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ])),
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: Text(st, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: tone))),
                    ]),
                  );
                }).toList(),
        ),

        // KYC
        _Section(
          title: T.s('KYC documents', lang),
          children: kycDocs.isEmpty
              ? [Text(T.s('No KYC docs yet', lang), style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5))]
              : kycDocs.map((d) => _Row(k: '${d['docType']}', v: '${d['refNumber']} · ${d['createdAt']}')).toList(),
        ),

        // Letters
        _Section(
          title: T.s('Letters', lang),
          trailing: letters.isNotEmpty
              ? InkWell(
                  onTap: () => context.push('/letters'),
                  child: Text(T.s('View all', lang), style: const TextStyle(color: HMC.primaryDark, fontSize: 12, fontWeight: FontWeight.w800)),
                )
              : null,
          children: letters.isEmpty
              ? [Text(T.s('No letters issued yet', lang), style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5))]
              : letters.take(10).map((l) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => context.push('/letters/${l['id']}'),
                      borderRadius: BorderRadius.circular(10),
                      child: Row(children: [
                        Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: HMC.primaryFade, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.description_outlined, size: 18, color: HMC.primaryDark)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${l['serial']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: HMC.ink)),
                          Text('${l['type']} · ${l['createdAt']}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                        ])),
                        Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 18),
                      ]),
                    ),
                  );
                }).toList(),
        ),

        // Advances
        if (advances.isNotEmpty)
          _Section(
            title: T.s('Advances', lang),
            children: advances
                .map((a) => _Row(k: '${a['givenDate']} · ${inr(a['amount'])}', v: '${T.s('Repaid', lang)} ${inr(a['repaid'])}${a['emi'] != null ? ' · EMI ${inr(a['emi'])}' : ''}'))
                .toList(),
          ),

        // Salary revisions
        if (salaryRevs.isNotEmpty)
          _Section(
            title: T.s('Pay history', lang),
            children: salaryRevs.map((r) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: switch (r['changeType']) {
                            'RAISE' => const Color(0xFFDCFCE7),
                            'DEMOTE' => const Color(0xFFFFE4E6),
                            _ => Colors.grey.shade200,
                          },
                          borderRadius: BorderRadius.circular(7)),
                      child: Text('${r['changeType']}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: HMC.ink))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          '${r['oldSalary'] != null ? inr(r['oldSalary']) : '—'} → ${inr(r['newSalary'])} · ${r['effectiveDate']}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: HMC.ink))),
                ]),
              );
            }).toList(),
          ),

        // Payroll rows
        if (payroll.isNotEmpty)
          _Section(
            title: T.s('Recent payroll', lang),
            children: payroll.map((p) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(child: Text('${p['month']} · ${p['status']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: HMC.ink))),
                  Text('${p['payableDays']}d · ${inr(p['netPay'])}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              );
            }).toList(),
          ),

        const SizedBox(height: 8),
        // Quick actions
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: Text(T.s('ID Card', lang)),
              onPressed: () => context.push('/idcard'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(T.s('Payslips', lang)),
              onPressed: () => context.push('/payslips'),
            ),
          ),
        ]),
      ],
    );
  }

  String _weekday(int d, String lang) {
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const pa = ['ਐਤਵਾਰ', 'ਸੋਮਵਾਰ', 'ਮੰਗਲਵਾਰ', 'ਬੁੱਧਵਾਰ', 'ਵੀਰਵਾਰ', 'ਸ਼ੁੱਕਰਵਾਰ', 'ਸ਼ਨੀਵਾਰ'];
    if (d < 0 || d > 6) return '—';
    return lang == 'pa' ? pa[d] : days[d];
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color tone;
  const _Badge({required this.text, required this.tone});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: tone, letterSpacing: 0.6)),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final Map<String, dynamic> emp;
  final String lang;
  const _InfoGrid({required this.emp, required this.lang});
  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      (T.s('Phone', lang), emp['phone'] ?? '—'),
      (T.s('Email', lang), emp['email'] ?? '—'),
      (T.s('Joined', lang), emp['joinDate'] ?? '—'),
      (T.s('Blood', lang), emp['bloodGroup'] ?? '—'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: items
          .map((it) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.$1, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  Text(it.$2, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ))
          .toList(),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tone;
  final VoidCallback? onTap;
  const _MiniCard({required this.icon, required this.title, required this.subtitle, required this.tone, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(backgroundColor: tone.withValues(alpha: 0.1), radius: 18, child: Icon(icon, size: 18, color: tone)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: HMC.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            if (onTap != null) Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 16),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  const _Section({required this.title, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x0F0A1628), blurRadius: 12, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.ink, fontSize: 13.5)),
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String k;
  final String v;
  const _Row({required this.k, required this.v});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(k, style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5, fontWeight: FontWeight.w600))),
        Expanded(child: Text(v, style: const TextStyle(color: HMC.ink, fontSize: 12.5, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
