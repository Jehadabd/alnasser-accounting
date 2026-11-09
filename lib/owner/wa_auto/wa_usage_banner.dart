// lib/owner/wa_auto/wa_usage_banner.dart
//
// 🔖 شريط يظهر إن شُغّلت خدمة الإرسال الآلي عبر واتساب على هذا الجهاز ولو مرة
// (انظر WaUsageMark). لا زر لإخفائه.

import 'package:flutter/material.dart';

import 'wa_usage_mark.dart';

class WaUsageBanner extends StatelessWidget {
  const WaUsageBanner({super.key, this.margin = const EdgeInsets.only(bottom: 12)});
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => FutureBuilder<WaUsage?>(
        future: WaUsageMark.read(),
        builder: (context, snap) {
          final u = snap.data;
          if (u == null) return const SizedBox.shrink();
          return Container(
            margin: margin,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDBA74)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.flag_rounded, color: Color(0xFFC2410C)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${u.summary()}\nهذه العلامة دائمة: إطفاء الخدمة لا يزيلها.',
                  style: const TextStyle(fontSize: 12.5, height: 1.6, color: Color(0xFF7C2D12)),
                ),
              ),
            ]),
          );
        },
      );
}
