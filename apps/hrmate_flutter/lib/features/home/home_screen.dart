import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// P1 stub — real dashboard (GPS+selfie punch, live timer) lands in P2.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final session = ref.watch(sessionStoreProvider);
    final name = (session.user?.name ?? '').split(' ').first;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset('assets/hrmate_emblem.png', width: 30, height: 30),
          const SizedBox(width: 10),
          const Text('HRMate'),
        ]),
        actions: [
          IconButton(
            tooltip: T.s('Log out', lang),
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionStoreProvider).clear(),
          ),
        ],
      ),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/hrmate_emblem.png', width: 96, height: 96),
          const SizedBox(height: 16),
          Text(
            name.isEmpty ? T.s('Home', lang) : '${T.s('Home', lang)} · $name',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: HMC.ink),
          ),
          const SizedBox(height: 8),
          Text(T.s('Dashboard is coming next phase', lang), style: TextStyle(color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}
