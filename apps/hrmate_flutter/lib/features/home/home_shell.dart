import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/session.dart';
import '../../core/app_nav.dart';
import '../../core/push.dart';
import 'home_data.dart';
import 'home_screen.dart';
import '../leaves/leaves_list.dart';
import '../approvals/approvals_tab.dart';
import '../more/more_tab.dart';

/// Navy dock + emerald fingerprint FAB. Approvals stays for heads.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(pushServiceProvider).start();
    });
  }

  void _punchFab() {
    final tab = ref.read(homeTabProvider);
    if (tab != 0) {
      ref.read(homeTabProvider.notifier).state = 0;
    }
    final canPunch = ref.read(sessionStoreProvider).user?.perms['canPunch'] ?? true;
    if (!canPunch) return;
    final block = ref.read(attendanceProvider).asData?.value;
    if (block == null) return;
    if (block.checkOutAt != null) return;
    context.push('/punch', extra: block.checkInAt == null ? 'checkin' : 'checkout');
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    var tab = ref.watch(homeTabProvider);
    final canApprove = ref.watch(sessionStoreProvider).user?.canApprove ?? false;

    final pages = [
      const HomeScreen(),
      const LeavesList(),
      const ApprovalsTab(),
      const MoreTab(),
    ];

    if (!canApprove && tab == 2) tab = 0;

    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: GestureDetector(
        key: const ValueKey('home-fab'),
        onTap: _punchFab,
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF34D399), Color(0xFF059669)],
            ),
            border: Border.all(color: HMC.ink, width: 5),
            boxShadow: const [
              BoxShadow(color: Color(0x6610B981), blurRadius: 16, offset: Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.fingerprint, color: Colors.white, size: 30),
        ),
      ),
      bottomNavigationBar: Container(
        color: HMC.ink,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(children: [
              Expanded(
                child: _NavBtn(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: T.s('Home', lang),
                  selected: tab == 0,
                  onTap: () => ref.read(homeTabProvider.notifier).state = 0,
                ),
              ),
              Expanded(
                child: _NavBtn(
                  icon: Icons.eco_outlined,
                  activeIcon: Icons.eco,
                  label: T.s('Leaves', lang),
                  selected: tab == 1,
                  onTap: () => ref.read(homeTabProvider.notifier).state = 1,
                ),
              ),
              const SizedBox(width: 72),
              if (canApprove)
                Expanded(
                  child: _NavBtn(
                    icon: Icons.check_circle_outline,
                    activeIcon: Icons.check_circle,
                    label: T.s('Approvals', lang),
                    selected: tab == 2,
                    onTap: () => ref.read(homeTabProvider.notifier).state = 2,
                  ),
                ),
              Expanded(
                child: _NavBtn(
                  icon: Icons.apps_outlined,
                  activeIcon: Icons.apps,
                  label: T.s('More', lang),
                  selected: tab == 3,
                  onTap: () => ref.read(homeTabProvider.notifier).state = 3,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon, activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavBtn({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF6EE7B7) : const Color(0xFF8BA0B5);
    return InkWell(
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(selected ? activeIcon : icon, color: color, size: 22),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
        ),
      ]),
    );
  }
}
