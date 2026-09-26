// firebase_options_helper_web.dart
// 🌐 بناء FirebaseOptions بمعايير الويب — يشترط authDomain (أشهر سبب
// لفشل/تذبذب المصادقة على الويب). يُشتق تلقائياً: <projectId>.firebaseapp.com

import 'package:firebase_core/firebase_core.dart';

FirebaseOptions? buildWebFirebaseOptions({
  required String apiKey,
  required String appId,
  required String projectId,
  required String messagingSenderId,
  String? authDomain,
  String? storageBucket,
}) {
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    projectId: projectId,
    messagingSenderId: messagingSenderId,
    authDomain: authDomain ?? '$projectId.firebaseapp.com',
    storageBucket: storageBucket ?? '$projectId.appspot.com',
  );
}
