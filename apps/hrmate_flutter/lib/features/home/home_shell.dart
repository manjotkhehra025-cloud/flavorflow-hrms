import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/session.dart';
import '../../core/app_nav.dart';
import '../../core/push.dart';
import 'home_screen.dart';
import '../leaves/leaves_list.dart';
import '../approvals/approvals_tab.dart';
import '../more/more_tab.dart';

/// Signed-in shell: Home / Leaves / Approvals / More (mockup p2 nav).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // P6: register this phone for pushes once we're fully signed in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(pushServiceProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    var tab = ref.watch(homeTabProvider);
    final canApprove = ref.watch(sessionStoreProvider).user?.canApprove ?? false;

    final titles = [T.s('Home', lang), T.s('Leaves', lang), T.s('Approvals', lang), T.s('More', lang)];
    final pages = [
      const HomeScreen(),
      const LeavesList(),
      const ApprovalsTab(),
      const MoreTab(),
    ];

    // Employees without route-head / staff rights don't see Approvals nav entry (same as web).
    if (!canApprove && tab == 2) tab = 0;

    final items = [
      BottomNavigationBarItem(icon: const Icon(Icons.home_outlined), activeIcon: const Icon(Icons.home), label: titles[0]),
      BottomNavigationBarItem(icon: const Icon(Icons.eco_outlined), activeIcon: const Icon(Icons.eco), label: titles[1]),
      if (canApprove)
        BottomNavigationBarItem(
          icon: const Icon(Icons.check_circle_outline),
          activeIcon: const Icon(Icons.check_circle),
          label: titles[2],
        ),
      BottomNavigationBarItem(icon: const Icon(Icons.more_horiz), activeIcon: const Icon(Icons.more), label: titles[3]),
    ];

    // Map current tab index onto the (possibly 3-item) nav list.
    final navCount = items.length;
    final navIndex = tab >= 3 ? navCount - 1 : tab;

    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        onDestinationSelected: (i) {
          var target = i;
          if (!canApprove && i >= 2) target = 3; // leaves/more shift by one without approvals
          ref.read(homeTabProvider.notifier).state = target;
        },
        backgroundColor: Colors.white,
        indicatorColor: HMC.primaryFade,
        height: 64,
        destinations: items
            .map(
              (it) => NavigationDestination(
                icon: it.icon,
                selectedIcon: it.activeIcon,
                label: it.label ?? '',
              ),
            )
            .toList(),
      ),
    );
  }
}
