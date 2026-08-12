// 🔐 Firebase Authentication Helper
// هذا الملف يساعد في تسجيل الدخول التلقائي لـ Firebase
// حتى تعمل قواعد Firestore الآمنة

import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthHelper {
  static final FirebaseAuthHelper _instance = FirebaseAuthHelper._internal();
  factory FirebaseAuthHelper() => _instance;
  FirebaseAuthHelper._internal();

  FirebaseAuth? _auth;
  
  /// تهيئة Firebase Auth
  Future<void> initialize() async {
    try {
      _auth = FirebaseAuth.instance;
      
      // التحقق من حالة المستخدم الحالية
      final currentUser = _auth?.currentUser;
      
      if (currentUser != null) {
        print('✅ مستخدم Firebase موجود بالفعل: ${currentUser.uid}');
      } else {
        print('ℹ️ لا يوجد مستخدم Firebase - سيتم تسجيل الدخول تلقائياً');
        await signInAnonymously();
      }
    } catch (e) {
      print('⚠️ خطأ في تهيئة Firebase Auth: $e');
    }
  }
  
  /// تسجيل دخول مجهول (Anonymous)
  /// هذا يسمح للتطبيق بالوصول إلى Firestore بدون حساب مستخدم
  Future<User?> signInAnonymously() async {
    try {
      if (_auth == null) {
        print('⚠️ Firebase Auth غير مهيأ');
        return null;
      }
      
      final userCredential = await _auth!.signInAnonymously();
      final user = userCredential.user;
      
      if (user != null) {
        print('✅ تم تسجيل الدخول المجهول بنجاح: ${user.uid}');
        return user;
      } else {
        print('❌ فشل تسجيل الدخول المجهول');
        return null;
      }
    } catch (e) {
      print('❌ خطأ في تسجيل الدخول المجهول: $e');
      return null;
    }
  }
  
  /// الحصول على المستخدم الحالي
  User? get currentUser => _auth?.currentUser;
  
  /// التحقق من تسجيل الدخول
  bool get isSignedIn => _auth?.currentUser != null;
  
  /// تسجيل الخروج
  Future<void> signOut() async {
    try {
      await _auth?.signOut();
      print('✅ تم تسجيل الخروج بنجاح');
    } catch (e) {
      print('❌ خطأ في تسجيل الخروج: $e');
    }
  }
  
  /// الاستماع لتغييرات حالة المستخدم
  Stream<User?>? get authStateChanges => _auth?.authStateChanges();
}
