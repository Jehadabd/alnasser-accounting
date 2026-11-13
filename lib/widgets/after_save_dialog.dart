// lib/widgets/after_save_dialog.dart
//
// ✅ نافذة «حُفظ» بعد حفظ تسديد أو وصل: علامة نجاح متحركة، رقم المستند والمبلغ، ثم أزرار كبيرة
// (طباعة / مشاركة / واتساب) و«لا، شكراً». تعيد 'print' أو 'share' أو 'wa' أو null.
// الحفظ تم قبل ظهورها في كل الأحوال — هي لما بعده فقط.

import 'package:flutter/material.dart';

import '../services/sync_perks.dart';
import 'settings_kit.dart';

class AfterSaveAction {
  const AfterSaveAction(this.value, this.label, this.icon, this.color, {this.primary = false});
  final String value, label;
  final IconData icon;
  final Color color;
  final bool primary;
}

const kAfterSavePrint = AfterSaveAction('print', 'طباعة', Icons.print_rounded, kSetNavy, primary: true);
const kAfterSaveShare = AfterSaveAction('share', 'مشاركة', Icons.share_rounded, kSetBlue);
const kAfterSaveWa = AfterSaveAction('wa', 'واتساب', Icons.send_to_mobile_rounded, kSetGreen);

Future<String?> showAfterSaveDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  String? amount,
  List<AfterSaveAction> actions = const [kAfterSavePrint, kAfterSaveShare, kAfterSaveWa],
  String question = 'ماذا تريد أن تفعل بالوصل؟',
}) =>
    showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق',
      barrierColor: const Color(0x660F172A),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => _AfterSaveDialog(
          title: title,
          subtitle: subtitle,
          amount: amount,
          // ⭐ «واتساب» (إرسال عبر الخادم) من ميزات اشتراك المزامنة
          actions: [for (final a in actions) if (a.value != 'wa' || SyncPerks.enabled) a],
          question: question),
      transitionBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: child),
      ),
    );

class _AfterSaveDialog extends StatelessWidget {
  const _AfterSaveDialog(
      {required this.title, required this.subtitle, required this.amount, required this.actions, required this.question});
  final String title, subtitle, question;
  final String? amount;
  final List<AfterSaveAction> actions;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [BoxShadow(color: Color(0x290F172A), blurRadius: 40, offset: Offset(0, 16))],
              ),
              child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const _SuccessMark(),
                  const SizedBox(height: 14),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: kSetText)),
                  const SizedBox(height: 4),
                  Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: kSetMuted)),
                  if (amount != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: kSetGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(amount!,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kSetGreen)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(question,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kSetMuted)),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: _ActionTile(actions[i])),
                    ],
                  ]),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: kSetMuted, minimumSize: const Size.fromHeight(42)),
                    child: const Text('لا، شكراً'),
                  ),
                ]),
              ),
            ),
            ),
          ),
        ),
      );
}

class _SuccessMark extends StatelessWidget {
  const _SuccessMark();

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: v, child: child),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF10B981), kSetGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [BoxShadow(color: kSetGreen.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 42),
        ),
      );
}

class _ActionTile extends StatefulWidget {
  const _ActionTile(this.a);
  final AfterSaveAction a;
  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final filled = a.primary;
    return Semantics(
      button: true,
      label: a.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          scale: _hover ? 1.04 : 1,
          duration: const Duration(milliseconds: 150),
          child: Material(
            color: filled ? a.color : a.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.pop(context, a.value),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: filled ? a.color : a.color.withValues(alpha: 0.25)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(a.icon, color: filled ? Colors.white : a.color, size: 28),
                  const SizedBox(height: 6),
                  Text(a.label,
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13.5, color: filled ? Colors.white : a.color)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
