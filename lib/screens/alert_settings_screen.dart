// lib/screens/alert_settings_screen.dart
//
// 🔔 تنبيهات المخزون والركود وانتهاء الصلاحية — بالشكل الموحّد لشاشات الإعدادات.
// المنطق كما هو: تفعيل/إيقاف، تكرار الظهور، حدّ أشهر انتهاء الصلاحية، فحص فوري.

import 'package:flutter/material.dart';

import '../erp/erp_kit.dart' show ChoiceTile;
import '../models/app_settings.dart';
import '../services/alert_service.dart';
import '../services/settings_manager.dart';
import '../widgets/settings_kit.dart';
import 'debt_reminders_screen.dart'; // 📅

class AlertSettingsScreen extends StatefulWidget {
  const AlertSettingsScreen({super.key});

  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  late AppSettings _appSettings;
  bool _isLoading = true;
  bool _saving = false;
  bool _areAlertsEnabled = true;
  String _alertFrequency = 'startup';
  int _expiryAlertThresholdMonths = 3;

  static const _orange = Color(0xFFEA580C);

  // النصوص تطابق ما يفعله AlertService فعلاً: «أسبوعياً» = بعد 7 أيام من آخر ظهور،
  // و«شهرياً» = بعد 30 يوماً (وليس بداية الأسبوع/الشهر كما كان مكتوباً سابقاً).
  static const _frequencies = <(String, String, String, IconData)>[
    ('startup', 'عند كل تشغيل', 'في كل مرة تفتح فيها التطبيق', Icons.power_settings_new_rounded),
    ('daily', 'يومياً', 'مرة واحدة في اليوم', Icons.today_rounded),
    ('weekly', 'أسبوعياً', 'مرة كل 7 أيام', Icons.date_range_rounded),
    ('monthly', 'شهرياً', 'مرة كل 30 يوماً', Icons.calendar_month_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _appSettings = await SettingsManager.getAppSettings();
    if (!mounted) return;
    setState(() {
      _areAlertsEnabled = _appSettings.areAlertsEnabled;
      _alertFrequency = _appSettings.alertFrequency;
      _expiryAlertThresholdMonths = _appSettings.expiryAlertThresholdMonths.clamp(1, 12).toInt();
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      final newSettings = _appSettings.copyWith(
        areAlertsEnabled: _areAlertsEnabled,
        alertFrequency: _alertFrequency,
        expiryAlertThresholdMonths: _expiryAlertThresholdMonths,
      );
      await SettingsManager.saveAppSettings(newSettings);
      if (!mounted) return;
      setToast(context, 'تم حفظ إعدادات التنبيهات');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setToast(context, 'تعذّر الحفظ: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _months(int n) => n == 1 ? 'شهر واحد' : (n == 2 ? 'شهرين' : (n <= 10 ? '$n أشهر' : '$n شهراً'));

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'تنبيهات المخزون والركود',
      subtitle: 'النواقص، المواد الراكدة، وقرب انتهاء الصلاحية',
      icon: Icons.notifications_active_rounded,
      loading: _isLoading,
      bottom: _isLoading ? null : _bottomBar(),
      children: _isLoading
          ? null
          : [
              SetHero(
                icon: Icons.notifications_active_rounded,
                color: _orange,
                title: 'تنبيهات ذكية عند فتح التطبيق',
                text: 'يعرض التطبيق قائمة بالمواد الناقصة والراكدة والقريبة من انتهاء الصلاحية '
                    'حسب التكرار الذي تختاره أدناه.',
                status: SetStatusPill(_areAlertsEnabled ? 'التنبيهات مفعّلة' : 'التنبيهات متوقفة',
                    ok: _areAlertsEnabled),
              ),
              // 📅 تذكير الديون له إعداده الخاص في شاشته
              SetCard(
                title: 'مواعيد المطالبة بالدين',
                subtitle: 'تذكير بعملاء محددين في أيام تختارها — إعداد منفصل',
                icon: Icons.event_repeat_rounded,
                color: const Color(0xFF4F46E5),
                child: SetActionRow(
                  icon: Icons.event_note_rounded,
                  color: const Color(0xFF4F46E5),
                  title: 'فتح مواعيد المطالبة',
                  subtitle: 'كل المواعيد، وظهورها: أول تشغيل في اليوم أو كل تشغيل',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DebtRemindersScreen())),
                ),
              ),
              SetCard(
                title: 'التشغيل',
                icon: Icons.toggle_on_rounded,
                color: _orange,
                child: SetSwitch(
                  title: 'تفعيل التنبيهات',
                  subtitle: 'نظام تنبيهات النواقص والمواد الراكدة وانتهاء الصلاحية',
                  icon: Icons.notifications_rounded,
                  color: _orange,
                  value: _areAlertsEnabled,
                  onChanged: (v) => setState(() => _areAlertsEnabled = v),
                ),
              ),
              _disabledWrap(
                SetCard(
                  title: 'تكرار ظهور التنبيه',
                  subtitle: 'متى تظهر نافذة التنبيهات عند فتح التطبيق',
                  icon: Icons.repeat_rounded,
                  color: _orange,
                  child: LayoutBuilder(builder: (context, c) {
                    final cols = c.maxWidth >= 520 ? 2 : 1;
                    final w = (c.maxWidth - (cols - 1) * 10) / cols;
                    return Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final f in _frequencies)
                        ChoiceTile(
                          width: w,
                          title: f.$2,
                          subtitle: f.$3,
                          icon: f.$4,
                          color: _orange,
                          selected: _alertFrequency == f.$1,
                          onTap: () => setState(() => _alertFrequency = f.$1),
                        ),
                    ]);
                  }),
                ),
              ),
              _disabledWrap(
                SetCard(
                  title: 'انتهاء الصلاحية',
                  subtitle: 'نبّهني عن المواد التي تنتهي صلاحيتها خلال أقل من:',
                  icon: Icons.hourglass_bottom_rounded,
                  color: kSetRed,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: kSetRed,
                            thumbColor: kSetRed,
                            inactiveTrackColor: const Color(0xFFFDE2E2),
                            overlayColor: kSetRed.withValues(alpha: 0.10),
                            valueIndicatorColor: kSetRed,
                            trackHeight: 6,
                          ),
                          child: Slider(
                            value: _expiryAlertThresholdMonths.toDouble(),
                            min: 1,
                            max: 12,
                            divisions: 11,
                            label: _months(_expiryAlertThresholdMonths),
                            onChanged: _areAlertsEnabled
                                ? (v) => setState(() => _expiryAlertThresholdMonths = v.round())
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 74,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kSetRed.withValues(alpha: 0.25)),
                        ),
                        child: Column(children: [
                          Text('$_expiryAlertThresholdMonths',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kSetRed)),
                          const Text('شهر', style: TextStyle(fontSize: 11.5, color: kSetRed)),
                        ]),
                      ),
                    ]),
                    // أزرار سريعة لقيم شائعة
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final m in const [1, 3, 6, 12])
                        ChoiceChip(
                          label: Text(_months(m)),
                          selected: _expiryAlertThresholdMonths == m,
                          onSelected: _areAlertsEnabled ? (_) => setState(() => _expiryAlertThresholdMonths = m) : null,
                          selectedColor: kSetRed.withValues(alpha: 0.12),
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _expiryAlertThresholdMonths == m ? kSetRed : kSetText,
                          ),
                          side: BorderSide(color: _expiryAlertThresholdMonths == m ? kSetRed : kSetBorder),
                          showCheckmark: false,
                        ),
                    ]),
                    const SizedBox(height: 12),
                    SetBanner(
                      'سيظهر تنبيه لأي مادة تنتهي صلاحيتها خلال ${_months(_expiryAlertThresholdMonths)} القادمة.',
                      kind: SetBannerKind.warn,
                      icon: Icons.event_busy_rounded,
                    ),
                  ]),
                ),
              ),
            ],
    );
  }

  Widget _disabledWrap(Widget child) => AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _areAlertsEnabled ? 1 : 0.45,
        child: IgnorePointer(ignoring: !_areAlertsEnabled, child: child),
      );

  Widget _bottomBar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: kSetBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                    onPressed: () => AlertService().checkAndShowAlerts(context, forceShow: true),
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Text('فحص التنبيهات الآن'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SetPrimaryButton(
                    label: 'حفظ الإعدادات',
                    icon: Icons.save_rounded,
                    busy: _saving,
                    onPressed: _saveSettings,
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}
