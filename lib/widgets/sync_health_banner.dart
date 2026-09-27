// lib/widgets/sync_health_banner.dart
//
// 🩺 شريط تنبيهات صحة المزامنة في الشاشة الرئيسية (SyncHealth). لا يظهر شيء
// ما دام كل شيء سليماً.

import 'package:flutter/material.dart';

import '../services/database_service.dart';
import '../services/firebase_sync/sync_health.dart';

class SyncHealthBanner extends StatefulWidget {
  const SyncHealthBanner({super.key});

  @override
  State<SyncHealthBanner> createState() => _SyncHealthBannerState();
}

class _SyncHealthBannerState extends State<SyncHealthBanner> {
  @override
  void initState() {
    super.initState();
    SyncHealth.load();
    // وضع الاستعادة من أول لحظة (قبل أن تكتمل تهيئة المزامنة وتضبطه)
    DatabaseService.isRestoreLockActive().then((active) {
      if (active) SyncHealth.setRecovering(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SyncHealthWarning>>(
      valueListenable: SyncHealth.warnings,
      builder: (context, list, _) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final w in list) _tile(context, w)],
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, SyncHealthWarning w) {
    final Color color;
    final IconData icon;
    switch (w.level) {
      case SyncHealthLevel.error:
        color = Colors.red.shade700;
        icon = Icons.error_outline;
        break;
      case SyncHealthLevel.warning:
        color = Colors.orange.shade800;
        icon = Icons.warning_amber_rounded;
        break;
      case SyncHealthLevel.info:
        color = Colors.blue.shade700;
        icon = Icons.sync_problem;
        break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 4),
                Text(w.details, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          if (w.dismissible)
            TextButton(
              onPressed: () => SyncHealth.dismiss(w.id),
              child: const Text('تمت المراجعة'),
            ),
        ],
      ),
    );
  }
}
