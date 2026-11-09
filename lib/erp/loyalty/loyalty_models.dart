// lib/erp/loyalty/loyalty_models.dart
//
// 🎁 برنامج الولاء — الإعدادات والحساب (دوال صافية مختبَرة).
//
// النقاط لا تُخزَّن رقماً يُزاد ويُنقص: تُشتق كل مرة من مبيعات العضو الصافية منذ انضمامه
// (الفواتير − الراجع − مرتجع المبيعات) من محرك التقارير نفسه. فالتعديل والمرتجع
// ينعكسان وحدهما، ولا تنحرف النقاط عن المبيعات أبداً. المخزَّن فقط: ما صُرف من مكافآت.
//
//   نقاط:  المكتسب = ⌊صافي المبيعات ÷ مبلغ النقطة⌋ ، المكافأة كل [rewardCost] نقطة.
//   أختام: المكتسب = عدد الفواتير التي صافيها ≥ [stampMinFils] ، المكافأة كل [stampsPerReward] ختم.
//   المتاح = المكتسب − المصروف (لا يقل عن صفر).

enum LoyaltyMode { points, stamps }

class LoyaltySettings {
  const LoyaltySettings({
    this.enabled = false,
    this.mode = LoyaltyMode.points,
    this.filsPerPoint = 100000, // 1,000 دينار = نقطة
    this.rewardCost = 100,
    this.stampMinFils = 1000000, // 10,000 دينار
    this.stampsPerReward = 10,
    this.rewardText = 'خصم 5,000 دينار على فاتورتك القادمة',
  });

  final bool enabled;
  final LoyaltyMode mode;
  final int filsPerPoint;
  final int rewardCost;
  final int stampMinFils;
  final int stampsPerReward;
  final String rewardText;

  int get unitsPerReward => mode == LoyaltyMode.points ? rewardCost : stampsPerReward;
  String get unitName => mode == LoyaltyMode.points ? 'نقطة' : 'ختم';

  LoyaltySettings copyWith({
    bool? enabled,
    LoyaltyMode? mode,
    int? filsPerPoint,
    int? rewardCost,
    int? stampMinFils,
    int? stampsPerReward,
    String? rewardText,
  }) =>
      LoyaltySettings(
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        filsPerPoint: filsPerPoint ?? this.filsPerPoint,
        rewardCost: rewardCost ?? this.rewardCost,
        stampMinFils: stampMinFils ?? this.stampMinFils,
        stampsPerReward: stampsPerReward ?? this.stampsPerReward,
        rewardText: rewardText ?? this.rewardText,
      );

  Map<String, String> toMap() => {
        'enabled': enabled ? '1' : '0',
        'mode': mode.name,
        'fils_per_point': '$filsPerPoint',
        'reward_cost': '$rewardCost',
        'stamp_min_fils': '$stampMinFils',
        'stamps_per_reward': '$stampsPerReward',
        'reward_text': rewardText,
      };

  factory LoyaltySettings.fromMap(Map<String, String> m) {
    int i(String k, int def, {int min = 1}) {
      final v = int.tryParse(m[k] ?? '');
      return v == null || v < min ? def : v;
    }

    const d = LoyaltySettings();
    return LoyaltySettings(
      enabled: m['enabled'] == '1',
      mode: m['mode'] == 'stamps' ? LoyaltyMode.stamps : LoyaltyMode.points,
      filsPerPoint: i('fils_per_point', d.filsPerPoint),
      rewardCost: i('reward_cost', d.rewardCost),
      stampMinFils: i('stamp_min_fils', d.stampMinFils, min: 0),
      stampsPerReward: i('stamps_per_reward', d.stampsPerReward),
      rewardText: (m['reward_text'] ?? '').trim().isEmpty ? d.rewardText : m['reward_text']!.trim(),
    );
  }
}

class LoyaltyMember {
  LoyaltyMember({required this.customerId, required this.name, required this.cardNo, required this.joinedAt, this.phone, this.active = true});
  final int customerId;
  final String name, cardNo;
  final String? phone;
  final DateTime joinedAt;
  final bool active;
}

/// رصيد عضو. دالة صافية.
class LoyaltyBalance {
  const LoyaltyBalance(this.earned, this.redeemed, this.unitsPerReward);
  final int earned, redeemed, unitsPerReward;

  int get available => earned - redeemed < 0 ? 0 : earned - redeemed;
  int get rewardsAvailable => unitsPerReward <= 0 ? 0 : available ~/ unitsPerReward;
  int get toNextReward => unitsPerReward <= 0 ? 0 : unitsPerReward - available % unitsPerReward;

  /// [invoiceNetFils]: صافي كل فاتورة للعضو منذ انضمامه. [returnsFils]: مستندات مرتجع المبيعات.
  static LoyaltyBalance of(LoyaltySettings s, {required List<int> invoiceNetFils, int returnsFils = 0, int redeemed = 0}) {
    final int earned;
    if (s.mode == LoyaltyMode.points) {
      final net = invoiceNetFils.fold<int>(0, (a, b) => a + b) - returnsFils;
      earned = net <= 0 || s.filsPerPoint <= 0 ? 0 : net ~/ s.filsPerPoint;
    } else {
      earned = invoiceNetFils.where((v) => v > 0 && v >= s.stampMinFils).length;
    }
    return LoyaltyBalance(earned, redeemed, s.unitsPerReward);
  }
}
