import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/content_provider.dart';
import '../../providers/employee_provider.dart';
import '../../providers/leave_provider.dart';
import '../../providers/payslip_provider.dart';
import '../attendance/attendance_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../leave/leave_screen.dart';
import '../more/more_screen.dart';
import '../payslip/payslip_list_screen.dart';

/// Main screen with bottom navigation.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Lets child screens switch tabs, e.g. HomeShell.of(context)?.goTo(1).
  static HomeShellState? of(BuildContext context) => context.findAncestorStateOfType<HomeShellState>();

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const tabAttendance = 1;
  static const tabLeave = 2;
  static const tabPayslip = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshAll());
  }

  Future<void> refreshAll() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final futures = <Future<void>>[
      context.read<AttendanceProvider>().load(user.id),
      context.read<LeaveProvider>().loadMine(user.id),
      context.read<PayslipProvider>().load(user.id),
      context.read<ContentProvider>().load(),
    ];
    if (user.isAdmin) {
      futures.add(context.read<EmployeeProvider>().load());
      futures.add(context.read<LeaveProvider>().loadAll());
    }
    await Future.wait(futures);
  }

  void goTo(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final pages = const [
      DashboardScreen(),
      AttendanceScreen(),
      LeaveScreen(),
      PayslipListScreen(),
      MoreScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: goTo,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.access_time), selectedIcon: Icon(Icons.access_time_filled), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Leave'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Payslip'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'More'),
        ],
      ),
    );
  }
}
