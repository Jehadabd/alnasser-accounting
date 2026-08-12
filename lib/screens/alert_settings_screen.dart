import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/settings_manager.dart';
import '../services/alert_service.dart'; // ✅ Added


class AlertSettingsScreen extends StatefulWidget {
  const AlertSettingsScreen({super.key});

  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  late AppSettings _appSettings;
  bool _isLoading = true;
  bool _areAlertsEnabled = true;
  String _alertFrequency = 'startup';
  int _expiryAlertThresholdMonths = 3; // ✅ Added

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _appSettings = await SettingsManager.getAppSettings();
    setState(() {
      _areAlertsEnabled = _appSettings.areAlertsEnabled;
      _alertFrequency = _appSettings.alertFrequency;
      _expiryAlertThresholdMonths = _appSettings.expiryAlertThresholdMonths; // ✅ Loaded
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final newSettings = _appSettings.copyWith(
      areAlertsEnabled: _areAlertsEnabled,
      alertFrequency: _alertFrequency,
      expiryAlertThresholdMonths: _expiryAlertThresholdMonths, // ✅ Saved
    );
    await SettingsManager.saveAppSettings(newSettings);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات التنبيهات')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات التنبيهات'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('تفعيل التنبيهات'),
            subtitle: const Text('تفعيل نظام التنبيهات للنواقص والمواد الراكدة'),
            value: _areAlertsEnabled,
            onChanged: (val) {
              setState(() {
                _areAlertsEnabled = val;
              });
            },
            activeColor: Colors.deepPurple,
          ),
          
          const Divider(),
          const SizedBox(height: 16),
          
          const Text(
            'تكرار التنبيه',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
          ),
          const SizedBox(height: 8),
          const Text(
            'اختر متى تريد أن يظهر لك تنبيه النواقص عند فتح التطبيق',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          
          _buildRadioOption('startup', 'عند كل تشغيل', 'يظهر التنبيه في كل مرة تفتح فيها التطبيق'),
          _buildRadioOption('daily', 'يومياً', 'يظهر مرة واحدة في اليوم'),
          _buildRadioOption('weekly', 'أسبوعياً', 'يظهر مرة واحدة في بداية الأسبوع'),
          _buildRadioOption('monthly', 'شهرياً', 'يظهر مرة واحدة في بداية الشهر'),
          
          _buildRadioOption('monthly', 'شهرياً', 'يظهر مرة واحدة في بداية الشهر'),
          
          const Divider(),
          const SizedBox(height: 16),
          
          const Text(
            'تنبيهات انتهاء الصلاحية',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
          ),
          const SizedBox(height: 8),
          Text(
            'نبهني عن المواد التي ستنتهي صلاحيتها خلال أقل من:',
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              const Icon(Icons.timer, color: Colors.orange),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    Slider(
                      value: _expiryAlertThresholdMonths.toDouble(),
                      min: 1,
                      max: 12,
                      divisions: 11,
                      label: '$_expiryAlertThresholdMonths أشهر',
                      activeColor: Colors.orange,
                      onChanged: _areAlertsEnabled ? (val) {
                        setState(() {
                          _expiryAlertThresholdMonths = val.toInt();
                        });
                      } : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('1 شهر', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text('12 شهر', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: Text(
                  '$_expiryAlertThresholdMonths',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'سيظهر تنبيه لأي مادة ستنتهي صلاحيتها خلال $_expiryAlertThresholdMonths أشهر القادمة',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),

          const SizedBox(height: 32),
          
          ElevatedButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: const Text('حفظ الإعدادات'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
          
          const SizedBox(height: 12), // ✅ Added
          
          OutlinedButton.icon( // ✅ Added manual trigger button
            onPressed: () {
              AlertService().checkAndShowAlerts(context, forceShow: true);
            },
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('فحص التنبيهات الآن'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              foregroundColor: Colors.deepPurple,
              side: const BorderSide(color: Colors.deepPurple),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioOption(String value, String title, String subtitle) {
    return RadioListTile<String>(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      groupValue: _alertFrequency,
      onChanged: _areAlertsEnabled ? (val) {
        setState(() {
          _alertFrequency = val!;
        });
      } : null,
      activeColor: Colors.deepPurple,
    );
  }
}
