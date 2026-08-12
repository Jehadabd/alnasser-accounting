// lib/services/firebase_sync/invoice_verifier_service.dart
import 'invoice_snapshot_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InvoiceDiscrepancy {
  final String deviceId;
  final bool hasMismatch;
  final List<String> missingInvoiceUuids; // فواتير موجودة عنده وغير موجودة عندي
  final List<String> outdatedInvoiceUuids; // فواتير نسختي منها أقدم من التي عنده
  
  InvoiceDiscrepancy({
    required this.deviceId,
    required this.hasMismatch,
    required this.missingInvoiceUuids,
    required this.outdatedInvoiceUuids,
  });
}

class InvoiceVerifierService {
  static final InvoiceVerifierService _instance = InvoiceVerifierService._internal();
  factory InvoiceVerifierService() => _instance;
  InvoiceVerifierService._internal();

  final InvoiceSnapshotService _snapshotService = InvoiceSnapshotService();
  
  static const String _invoiceMismatchFlagKey = 'invoice_mismatch_detected_flag';

  /// 🔍 التحقق من جميع اللقطات ومقارنتها باللقطة المحلية
  Future<List<InvoiceDiscrepancy>> verifyAll() async {
    try {
      final localSnapshot = await _snapshotService.createSnapshot();
      final otherSnapshots = await _snapshotService.fetchOtherDevicesSnapshots();
      
      List<InvoiceDiscrepancy> discrepancies = [];
      bool anyMismatchFound = false;

      for (final remoteSnapshot in otherSnapshots) {
        final discrepancy = _compareSnapshots(localSnapshot, remoteSnapshot);
        discrepancies.add(discrepancy);
        
        if (discrepancy.hasMismatch) {
          anyMismatchFound = true;
        }
      }

      // حفظ حالة عدم التطابق (True أو False) في SharedPreferences ليتم عرض الإشعار
      await setMismatchFlag(anyMismatchFound);
      
      return discrepancies;
    } catch (e) {
      print('⚠️ خطأ أثناء تدقيق الفواتير: $e');
      return [];
    }
  }

  /// 🔬 مقارنة لقطتين (المحلية والبعيدة) لاكتشاف الفروقات
  InvoiceDiscrepancy _compareSnapshots(InvoiceSnapshot local, InvoiceSnapshot remote) {
    List<String> missing = [];
    List<String> outdated = [];
    bool mismatch = false;

    // 1. هل هناك اختلاف في الإجمالي كلياً؟
    if ((local.totalAmount - remote.totalAmount).abs() > 0.01 || local.totalInvoices != remote.totalInvoices) {
      mismatch = true;
    }

    // 2. فحص الفواتير التي عند الجهاز البعيد
    remote.invoiceVersions.forEach((uuid, remoteVersion) {
      final localVersion = local.invoiceVersions[uuid];
      
      if (localVersion == null) {
        // الفاتورة موجودة عنده وغير موجودة عندي إطلاقاً
        missing.add(uuid);
        mismatch = true;
      } else if (localVersion < remoteVersion) {
        // نسختي أقدم من نسخته
        outdated.add(uuid);
        mismatch = true;
      }
    });

    return InvoiceDiscrepancy(
      deviceId: remote.deviceId,
      hasMismatch: mismatch,
      missingInvoiceUuids: missing,
      outdatedInvoiceUuids: outdated,
    );
  }

  /// حفظ/تحديث حالة عدم التطابق
  Future<void> setMismatchFlag(bool hasMismatch) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_invoiceMismatchFlagKey, hasMismatch);
  }

  /// التحقق هل يوجد إشعار عدم تطابق حالياً
  Future<bool> hasMismatchFlag() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_invoiceMismatchFlagKey) ?? false;
  }
}
