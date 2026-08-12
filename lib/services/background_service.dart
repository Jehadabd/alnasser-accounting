// services/background_service.dart
// تم تعطيل الكود الخاص ب Workmanager والرفع التلقائي

import 'package:workmanager/workmanager.dart';
import '../providers/app_provider.dart';
import 'package:flutter/widgets.dart';

const String dailyReportTask = 'uploadDailyReportTask';

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == dailyReportTask) {
      // يجب تهيئة Flutter قبل أي كود يستخدمه
      WidgetsFlutterBinding.ensureInitialized();
      final provider = AppProvider();
      try {
        await provider.initialize();
        await provider.uploadDebtRecord();
        return Future.value(true);
      } catch (e) {
        return Future.value(false);
      }
    }
    return Future.value(false);
  });
}
