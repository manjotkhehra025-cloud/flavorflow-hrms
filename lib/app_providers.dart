import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'providers/attendance_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/content_provider.dart';
import 'providers/employee_provider.dart';
import 'providers/leave_provider.dart';
import 'providers/payslip_provider.dart';
import 'repositories/repository_factory.dart';

/// Wires every repository and provider into the widget tree.
class AppProviders extends StatelessWidget {
  const AppProviders({super.key, required this.repositories, required this.child});
  final Repositories repositories;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final repos = repositories;
    return MultiProvider(
      providers: [
        Provider<Repositories>.value(value: repos),
        ChangeNotifierProvider(create: (_) => AuthProvider(repos.auth)),
        ChangeNotifierProvider(create: (_) => AttendanceProvider(repos.attendance)),
        ChangeNotifierProvider(create: (_) => LeaveProvider(repos.leave)),
        ChangeNotifierProvider(create: (_) => PayslipProvider(repos.payslips)),
        ChangeNotifierProvider(create: (_) => EmployeeProvider(repos.employees)),
        ChangeNotifierProvider(create: (_) => ContentProvider(repos.content)),
      ],
      child: child,
    );
  }
}
