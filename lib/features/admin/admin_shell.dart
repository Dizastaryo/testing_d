import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'admin_audio_page.dart';
import 'admin_audit_page.dart';
import 'admin_auth_provider.dart';
import 'admin_metrics_page.dart';
import 'admin_reports_page.dart';
import 'admin_users_page.dart';

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _index = 0;

  static const _pages = [
    _NavEntry('Жалобы', PhosphorIconsRegular.flag, AdminReportsPage()),
    _NavEntry('Юзеры', PhosphorIconsRegular.usersThree, AdminUsersPage()),
    _NavEntry('Треки', PhosphorIconsRegular.musicNotes, AdminAudioPage()),
    _NavEntry('Метрики', PhosphorIconsRegular.chartLine, AdminMetricsPage()),
    _NavEntry('Аудит', PhosphorIconsRegular.receipt, AdminAuditPage()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.of(context).size.width >= 900,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Column(
                children: [
                  const Icon(PhosphorIconsRegular.shield, size: 28, color: Color(0xFFFF5A3C)),
                  if (MediaQuery.of(context).size.width >= 900) ...[
                    const SizedBox(height: 4),
                    const Text('SeeU Admin', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(PhosphorIconsRegular.signOut),
                    tooltip: 'Выйти',
                    onPressed: () =>
                        ref.read(adminAuthProvider.notifier).logout(),
                  ),
                ),
              ),
            ),
            destinations: [
              for (final p in _pages)
                NavigationRailDestination(
                  icon: Icon(p.icon),
                  label: Text(p.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [for (final p in _pages) p.page],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavEntry {
  final String label;
  final IconData icon;
  final Widget page;
  const _NavEntry(this.label, this.icon, this.page);
}
