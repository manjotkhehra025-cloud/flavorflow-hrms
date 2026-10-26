import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../providers/employee_provider.dart';
import '../../widgets/common.dart';
import 'employee_form_screen.dart';

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<EmployeeProvider>();
      p.search('');
      p.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EmployeeProvider>();
    final list = p.filtered;
    return Scaffold(
      appBar: AppBar(title: Text('Employees (${p.all.length})')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => pushScreen(context, const EmployeeFormScreen()),
        icon: const Icon(Icons.person_add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: p.search,
              decoration: const InputDecoration(
                hintText: 'Search name, ID, department...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: p.loading && p.all.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const EmptyState(icon: Icons.person_search, message: 'No employees found')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final e = list[i];
                          return Card(
                            child: ListTile(
                              leading: EmployeeAvatar(initials: e.initials),
                              title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${e.id}  \u2022  ${e.designation}\n${e.department}'),
                              isThreeLine: true,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (e.isAdmin) const StatusChip('Admin', AppTheme.warning),
                                  if (!e.isActive) const StatusChip('Inactive', AppTheme.muted),
                                  const Icon(Icons.edit_outlined, size: 18),
                                ],
                              ),
                              onTap: () => pushScreen(context, EmployeeFormScreen(employee: e)),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
