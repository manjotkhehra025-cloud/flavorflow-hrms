import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../models/holiday.dart';
import '../../providers/content_provider.dart';
import '../../widgets/common.dart';

class HolidaysScreen extends StatelessWidget {
  const HolidaysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ContentProvider>();
    final today = dateOnly(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text('Holidays ${c.year}')),
      body: c.loading && c.holidays.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : c.holidays.isEmpty
              ? const EmptyState(icon: Icons.beach_access, message: 'No holidays listed')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: c.holidays.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final h = c.holidays[i];
                    final past = h.date.isBefore(today);
                    final isNext = identical(h, c.nextHoliday);
                    return Opacity(
                      opacity: past ? 0.5 : 1,
                      child: Card(
                        shape: isNext
                            ? RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(color: Colors.purple, width: 1.5),
                              )
                            : null,
                        child: ListTile(
                          leading: Container(
                            width: 50,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${h.date.day}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.purple)),
                                Text(Fmt.shortDate(h.date).split(' ').last, style: const TextStyle(fontSize: 11, color: Colors.purple)),
                              ],
                            ),
                          ),
                          title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(Fmt.weekday(h.date) + (isNext ? '  \u2022  Next holiday' : '')),
                          trailing: StatusChip(h.type.label, h.type == HolidayType.national ? Colors.green : Colors.purple),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
