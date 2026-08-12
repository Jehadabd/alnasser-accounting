# 🔄 كيفية استخدام نظام المزامنة المحسّن

## الوضع الحالي

التطبيق يستخدم حالياً نظام مزامنة بسيط في `DriveService` يعمل كالتالي:
- كل جهاز يرفع ملف JSON باسمه
- يقرأ ملفات الأجهزة الأخرى
- يدمج المعاملات يدوياً

## النظام الجديد المحسّن

أنشأنا نظام مزامنة متقدم في `lib/services/sync/` يتضمن:
- ضغط البيانات (توفير 70-90% من المساحة)
- تجميع العمليات (Batching)
- قفل موزع آمن
- Snapshots دورية

---

## 🚀 طريقة الاستخدام

### الطريقة 1: استخدام SyncService (الأسهل)

```dart
import 'package:debt_book/services/sync/sync_service.dart';

// في أي مكان في التطبيق
final syncService = SyncService();

// تهيئة (مرة واحدة عند بدء التطبيق)
await syncService.initialize();

// تنفيذ المزامنة
final result = await syncService.sync();

if (result.success) {
  print('✅ تمت المزامنة');
  print('تنزيل: ${result.downloaded}');
  print('رفع: ${result.uploaded}');
} else {
  print('❌ فشل: ${result.message}');
}
```

### الطريقة 2: تحديث AppProvider

في `lib/providers/app_provider.dart`، أضف:

```dart
import '../services/sync/sync_service.dart';

class AppProvider extends ChangeNotifier {
  final SyncService _syncService = SyncService();
  
  // دالة المزامنة المحسّنة
  Future<void> syncDebtsOptimized() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    _setLoading(true);
    
    try {
      // تهيئة إذا لم تكن جاهزة
      await _syncService.initialize();
      
      // تنفيذ المزامنة
      final result = await _syncService.sync();
      
      if (!result.success) {
        throw Exception(result.message);
      }
      
      // تحديث البيانات المحلية
      await loadCustomers();
      
    } finally {
      _isSyncing = false;
      _setLoading(false);
    }
  }
}
```

### الطريقة 3: في الشاشة مباشرة

```dart
// في home_screen.dart
FloatingActionButton(
  heroTag: 'sync_debts',
  onPressed: () async {
    final syncService = SyncService();
    
    // إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            StreamBuilder<String>(
              stream: syncService.messageStream,
              builder: (_, snap) => Text(snap.data ?? 'جاري المزامنة...'),
            ),
          ],
        ),
      ),
    );
    
    try {
      await syncService.initialize();
      final result = await syncService.sync();
      
      Navigator.pop(context); // إغلاق الحوار
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success 
            ? 'تمت المزامنة ✅ (${result.downloaded} تنزيل، ${result.uploaded} رفع)'
            : 'فشلت المزامنة: ${result.message}'),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    }
  },
  tooltip: 'مزامنة',
  child: Icon(Icons.sync),
),
```

---

## 📊 فحص المساحة

```dart
final syncService = SyncService();
await syncService.initialize();

final storage = await syncService.checkStorage();
print('المساحة المستخدمة: ${storage['total_mb']}MB');
```

---

## 🧹 تنظيف المساحة

```dart
await syncService.cleanupStorage();
```

---

## ⚙️ تخصيص الإعدادات

في `sync_service.dart`، يمكنك تعديل:

```dart
_syncEngine = OptimizedSyncEngine(
  config: OptimizedSyncConfig(
    maxStorageMB: 300,           // الحد الأقصى للمساحة
    maxSnapshotsToKeep: 3,       // عدد النسخ الاحتياطية
    maxOperationFilesToKeep: 10, // عدد ملفات العمليات
    enableCompression: true,     // تفعيل الضغط
    snapshotEveryNOperations: 200, // إنشاء snapshot كل 200 عملية
  ),
);
```

---

## 🔄 الفرق بين النظامين

| الميزة | النظام القديم | النظام الجديد |
|--------|--------------|---------------|
| الضغط | ❌ لا | ✅ GZIP (90% توفير) |
| القفل | ❌ لا | ✅ Verify-After-Write |
| Batching | ❌ لا | ✅ ملف واحد لكل مزامنة |
| Snapshots | ❌ لا | ✅ كل 200 عملية |
| التنظيف التلقائي | ❌ لا | ✅ عند 80% |
| تتبع التعارضات | ❌ لا | ✅ Causality Vector |

---

## ⚠️ ملاحظات مهمة

1. **النظام الجديد مستقل** - يستخدم مجلد مختلف (`DebtBook_Sync_v3`)
2. **لا يتعارض مع القديم** - يمكن استخدام كلاهما
3. **يتطلب تسجيل الدخول** - نفس حساب Google Drive
4. **المفتاح السري** - يُنشأ تلقائياً ويُحفظ محلياً

---

## 🐛 استكشاف الأخطاء

### "المحرك غير جاهز"
```dart
await syncService.initialize(); // تأكد من التهيئة أولاً
```

### "فشل الحصول على القفل"
- جهاز آخر يزامن حالياً
- انتظر دقيقة وحاول مرة أخرى

### "لم يتم تسجيل الدخول"
```dart
final driveService = DriveService();
await driveService.signIn();
```
