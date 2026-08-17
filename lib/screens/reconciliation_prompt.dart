// lib/screens/reconciliation_prompt.dart
//
// حوار طلب المطابقة الذي يظهر على الأجهزة الأخرى — يشمل:
// - جلسة التدقيق الجماعية القديمة (ReconciliationService)
// - المطابقة الحية بين الأجهزة المتصلة (LiveMatchService)

import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart' show globalNavigatorKey;
import '../services/firebase_sync/live_match_service.dart';
import '../services/firebase_sync/reconciliation_service.dart';
import 'reconciliation_screen.dart';

class ReconciliationPrompt {
  static StreamSubscription? _subAudit;
  static StreamSubscription? _subLive;
  static StreamSubscription? _subNavigate;
  static bool _showing = false;

  static void start() {
    _subAudit?.cancel();
    _subLive?.cancel();

    _subAudit = ReconciliationService().onRequest.listen((req) {
      _show(
        title: 'طلب مطابقة حسابية',
        body:
            'الجهاز "${req.initiatorName}" يطلب مطابقة شاملة للأرصدة والمعاملات '
            'بين ${req.invitedCount} أجهزة.',
        detail:
            'المطابقة تقارن بياناتك مع السحابة وتُنزل ما ينقصك وترفع ما لم يُرفع.',
        expiresAt: req.expiresAt,
        onRespond: (accepted) =>
            ReconciliationService().respond(req.sessionId, accept: accepted),
      );
    });

    _subLive = LiveMatchService().onRequest.listen((req) {
      // نبدأ الاستماع للجلسات على الجهاز المدعو أيضاً.
      LiveMatchService().start();
      _show(
        title: 'طلب مطابقة حية بين الأجهزة',
        body:
            'الجهاز "${req.initiatorName}" يطلب مطابقة حية مع ${req.invitedCount} أجهزة متصلة.',
        detail:
            'ستُقارَن ديونك الحالية وعدد معاملات كل عميل مع الجهاز الآخر مباشرة '
            '(ليست مع السحابة).',
        expiresAt: req.expiresAt,
        onRespond: (accepted) =>
            LiveMatchService().respond(req.sessionId, accept: accepted),
      );
    });

    // الاستماع لانتقال الشاشة عند بدء المطابقة
    _subNavigate?.cancel();
    _subNavigate = LiveMatchService().onMatchScreenRequested.listen((_) {
      final nav = globalNavigatorKey.currentState;
      final context = globalNavigatorKey.currentContext;
      if (nav == null || context == null) return;
      final currentName = ModalRoute.of(context)?.settings.name;
      if (currentName == '/live_match') return;
      nav.push(MaterialPageRoute(
        settings: const RouteSettings(name: '/live_match'),
        builder: (_) => const ReconciliationScreen(),
      ));
    });
  }

  static void stop() {
    _subAudit?.cancel();
    _subLive?.cancel();
    _subNavigate?.cancel();
    _subAudit = null;
    _subLive = null;
    _subNavigate = null;
  }

  static Future<void> _show({
    required String title,
    required String body,
    required String detail,
    required DateTime expiresAt,
    required Future<void> Function(bool accepted) onRespond,
  }) async {
    if (_showing) return;
    final context = globalNavigatorKey.currentContext;
    if (context == null) return;

    _showing = true;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RequestDialog(
          title: title,
          body: body,
          detail: detail,
          expiresAt: expiresAt,
        ),
      );

      await onRespond(accepted == true);
    } catch (e) {
      debugPrint('⚠️ تعذّر عرض طلب المطابقة: $e');
    } finally {
      _showing = false;
    }
  }
}

class _RequestDialog extends StatefulWidget {
  final String title;
  final String body;
  final String detail;
  final DateTime expiresAt;

  const _RequestDialog({
    required this.title,
    required this.body,
    required this.detail,
    required this.expiresAt,
  });

  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  late Timer _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final left = widget.expiresAt.difference(DateTime.now());
    setState(() =>
        _remaining = left.isNegative ? Duration.zero : left);
    if (left.isNegative || left == Duration.zero) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _remaining.inSeconds;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.sensors, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.body),
            const SizedBox(height: 12),
            Text(widget.detail,
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 18, color: Colors.orange),
                const SizedBox(width: 6),
                Text('تنتهي المهلة خلال $seconds ثانية',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('رفض'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check),
            label: const Text('موافق'),
          ),
        ],
      ),
    );
  }
}
