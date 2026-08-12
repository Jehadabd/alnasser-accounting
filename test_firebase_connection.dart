// 🧪 سكريبت اختبار اتصال Firebase
// لاختبار الاتصال بـ Firebase وصلاحيات Firestore

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firebase_sync/firebase_custom_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('\n🔬 بدء اختبار Firebase...\n');
  
  try {
    // 1️⃣ تهيئة Firebase
    print('1️⃣ تهيئة Firebase...');
    final customOptions = await FirebaseCustomConfig.getCustomOptions();
    
    if (customOptions == null) {
      print('❌ لم يتم العثور على إعدادات Firebase!');
      print('   → تأكد من تكوين Firebase في التطبيق');
      return;
    }
    
    await Firebase.initializeApp(options: customOptions);
    print('   ✅ تم تهيئة Firebase بنجاح\n');
    
    // 2️⃣ اختبار Firebase Auth
    print('2️⃣ اختبار Firebase Authentication...');
    final auth = FirebaseAuth.instance;
    
    if (auth.currentUser != null) {
      print('   ✅ مستخدم موجود بالفعل: ${auth.currentUser!.uid}');
    } else {
      print('   ℹ️ لا يوجد مستخدم - محاولة تسجيل دخول مجهول...');
      try {
        final userCredential = await auth.signInAnonymously();
        print('   ✅ تم تسجيل الدخول المجهول: ${userCredential.user!.uid}');
      } catch (e) {
        print('   ⚠️ فشل تسجيل الدخول المجهول: $e');
        print('   → تأكد من تفعيل Anonymous Auth في Firebase Console');
      }
    }
    print('');
    
    // 3️⃣ اختبار Firestore - القراءة
    print('3️⃣ اختبار Firestore - القراءة...');
    final firestore = FirebaseFirestore.instance;
    
    try {
      final testDoc = await firestore
          .collection('_test')
          .doc('connection_test')
          .get();
      
      if (testDoc.exists) {
        print('   ✅ تمت قراءة وثيقة اختبار موجودة');
      } else {
        print('   ℹ️ الوثيقة الاختبارية غير موجودة (طبيعي)');
      }
    } catch (e) {
      print('   ❌ فشلت القراءة من Firestore!');
      print('   → الخطأ: $e');
      if (e.toString().contains('PERMISSION_DENIED')) {
        print('   → 🔴 مشكلة صلاحيات! راجع firestore.rules');
        print('   → الحل السريع: راجع SOLUTION_QUICK_FIX.md');
      }
    }
    print('');
    
    // 4️⃣ اختبار Firestore - الكتابة
    print('4️⃣ اختبار Firestore - الكتابة...');
    try {
      await firestore
          .collection('_test')
          .doc('connection_test')
          .set({
        'timestamp': FieldValue.serverTimestamp(),
        'test': true,
        'message': 'اختبار اتصال Firebase',
      });
      
      print('   ✅ تمت الكتابة إلى Firestore بنجاح');
    } catch (e) {
      print('   ❌ فشلت الكتابة إلى Firestore!');
      print('   → الخطأ: $e');
      if (e.toString().contains('PERMISSION_DENIED')) {
        print('   → 🔴 مشكلة صلاحيات! راجع firestore.rules');
        print('   → الحل السريع: راجع SOLUTION_QUICK_FIX.md');
      }
    }
    print('');
    
    // 5️⃣ اختبار قراءة من مجموعة فعلية
    print('5️⃣ اختبار قراءة من مجموعة العملاء...');
    try {
      final snapshot = await firestore
          .collection('customers')
          .limit(1)
          .get();
      
      print('   ✅ تمت قراءة ${snapshot.docs.length} وثيقة من customers');
    } catch (e) {
      print('   ❌ فشلت القراءة من customers!');
      print('   → الخطأ: $e');
      if (e.toString().contains('PERMISSION_DENIED')) {
        print('   → 🔴 مشكلة صلاحيات! راجع firestore.rules');
      }
    }
    print('');
    
    // 6️⃣ النتيجة النهائية
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 ملخص الاختبار:');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    final authStatus = auth.currentUser != null ? '✅' : '❌';
    print('$authStatus Firebase Authentication');
    
    print('');
    print('💡 الخطوات التالية:');
    print('   1. إذا كان هناك أخطاء PERMISSION_DENIED:');
    print('      → راجع SOLUTION_QUICK_FIX.md');
    print('   2. للحل الآمن مع Authentication:');
    print('      → راجع FIREBASE_AUTH_INTEGRATION.md');
    print('   3. للشرح الكامل:');
    print('      → راجع FIREBASE_PERMISSION_FIX.md');
    print('');
    
  } catch (e) {
    print('❌ خطأ عام في الاختبار: $e');
    print('\n💡 تأكد من:');
    print('   1. تشغيل flutter pub get');
    print('   2. وجود google-services.json في android/app/');
    print('   3. الاتصال بالإنترنت');
  }
  
  print('\n🏁 انتهى الاختبار\n');
}
