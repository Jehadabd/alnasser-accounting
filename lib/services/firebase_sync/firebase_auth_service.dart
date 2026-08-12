// lib/services/firebase_sync/firebase_auth_service.dart
// خدمة المصادقة لـ Firebase - تستخدم REST API + Firebase Auth SDK
// يتم إنشاء حساب تلقائي فريد لكل جهاز

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseAuthService {
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();
  factory FirebaseAuthService() => _instance;
  FirebaseAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 🛡️ قفل لمنع الاستدعاء المتزامن
  bool _isAuthenticating = false;
  
  // 📱 معرف المستخدم المخبأ
  String? _cachedUid;
  DateTime? _lastAuthCheck;

  /// الحصول على المستخدم الحالي
  User? get currentUser => _auth.currentUser;

  /// الحصول على UID الحالي
  String? get uid => _auth.currentUser?.uid;

  /// هل المستخدم مصادق عليه؟
  bool get isAuthenticated => _auth.currentUser != null;

  /// تسجيل الدخول المجهول (مع حماية من الاستدعاء المتزامن)
  Future<String?> signInAnonymously() async {
    // 🛡️ منع الاستدعاء المتزامن
    if (_isAuthenticating) {
      // إذا كان هناك طلب جارٍ، ننتظر انتهاءه أو نعيد الـ cached UID
      if (_cachedUid != null && _lastAuthCheck != null) {
        final elapsed = DateTime.now().difference(_lastAuthCheck!);
        if (elapsed.inMinutes < 5) {
          return _cachedUid;
        }
      }
      
      // انتظار انتهاء الطلب الحالي
      int waitCount = 0;
      while (_isAuthenticating && waitCount < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        waitCount++;
      }
      if (_cachedUid != null) return _cachedUid;
    }
    
    _isAuthenticating = true;
    
    try {
      // التحقق مما إذا كان مسجلاً للدخول بالفعل
      if (_auth.currentUser != null) {
        try {
          // 🔒 استخدام compute لتجنب مشاكل الـ threading
          final tokenResult = await _getIdTokenSafely(_auth.currentUser!);
          if (tokenResult != null) {
            print('✅ المستخدم مصادق عليه مسبقاً (توكن صالح): ${_auth.currentUser!.uid}');
            _cachedUid = _auth.currentUser!.uid;
            _lastAuthCheck = DateTime.now();
            return _cachedUid;
          }
        } catch (e) {
          print('⚠️ التوكن الحالي غير صالح أو منتهي، سيتم تسجيل الخروج وإعادة الدخول... $e');
          try {
            await _auth.signOut();
          } catch (_) {}
        }
      }

      print('🔐 جاري تسجيل الدخول المجهول...');
      final userCredential = await _auth.signInAnonymously().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('انتهى الوقت (15 ثانية) لمحاولة تسجيل الدخول المجهول');
        },
      );
      
      if (userCredential.user != null) {
        print('✅ تم تسجيل الدخول بنجاح: ${userCredential.user!.uid}');
        
        // --- بدء الاختبار التشخيصي بناء على طلب المستخدم ---
        final user = userCredential.user;
        print('UID: ${user?.uid}');
        print('Anonymous: ${user?.isAnonymous}');
        
        final token = await user?.getIdToken(true);
        print('TOKEN: ${token != null}');
        print('TOKEN LENGTH: ${token?.length}');
        
        try {
          // جلب FirebaseFirestore.instance لمعرفة إذا كان يملك صلاحية أو لا
          await FirebaseFirestore.instance
              .collection('devices')
              .doc('test_${user!.uid}')
              .set({
                'uid': user.uid,
                'test': true,
                'createdAt': FieldValue.serverTimestamp(),
              });
        
          print('✅ FIRESTORE WRITE SUCCESS (Test Diagnostic)');
        } catch (e) {
          print('❌ FIRESTORE WRITE ERROR (Test Diagnostic): $e');
        }
        // --- نهاية الاختبار التشخيصي ---

        _cachedUid = userCredential.user!.uid;
        _lastAuthCheck = DateTime.now();
        return _cachedUid;
      }
      
      print('⚠️ signInAnonymously نجح ولكنه أعاد null للمستخدم');
      throw Exception('signInAnonymously returned null user');
    } catch (e) {
      print('❌ خطأ في تسجيل الدخول المجهول: $e');
      throw Exception('AuthError: $e');
    } finally {
      _isAuthenticating = false;
    }
  }

  /// 🔒 الحصول على التوكن بطريقة آمنة
  Future<String?> _getIdTokenSafely(User user) async {
    try {
      // على الويب/desktop/mobile، نستخدم try-catch للتعامل مع الأخطاء المحتملة
      return await user.getIdToken(true);
    } catch (e) {
      // في حالة الخطأ، نعيد null للسماح بإعادة المحاولة
      return null;
    }
  }

  /// تسجيل الخروج
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      _cachedUid = null;
      print('✅ تم تسجيل الخروج');
    } catch (e) {
      print('❌ خطأ في تسجيل الخروج: $e');
    }
  }

  /// Stream لمراقبة تغييرات حالة المصادقة
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// التحقق من صلاحية الجلسة وتجديدها إذا لزم
  Future<bool> refreshSessionIfNeeded() async {
    if (_auth.currentUser == null) {
      final uid = await signInAnonymously();
      return uid != null;
    }
    return true;
  }
}

/// Singleton للوصول السهل
class FirebaseAuthInstance {
  static FirebaseAuthService? _instance;

  static FirebaseAuthService get() {
    _instance ??= FirebaseAuthService();
    return _instance!;
  }
}
