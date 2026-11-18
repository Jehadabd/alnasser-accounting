// lib/services/telegram_net/tdlib_client_stub.dart
//
// 🌐 بديل الويب لعميل TDLib: الواجهة نفسها بلا dart:ffi. لا يُستدعى فعلياً
// (MTProto يعمل على Windows فقط)، وأي استدعاء يرمي TdError واضحاً.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

class TdError implements Exception {
  TdError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'TDLib $code: $message';
}

class TdlibClient {
  TdlibClient._();
  static final TdlibClient instance = TdlibClient._();

  static TdError get _unsupported => TdError(0, 'MTProto غير متاح في هذه النسخة (Windows فقط)');

  final _updates = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get updates => _updates.stream;

  Future<void> Function()? onWaitingForBot;

  Map<String, dynamic>? execute(Map<String, dynamic> q) => null;

  Future<void> ensureReady({required String token, required int apiId, required String apiHash}) async =>
      throw _unsupported;

  Future<Map<String, dynamic>> request(Map<String, dynamic> q, {Duration timeout = const Duration(seconds: 60)}) async =>
      throw _unsupported;

  Future<void> shutdown() async {}

  bool get ready => false;
  String get authState => '';

  /// معرّف قناة Bot API (‎-100XXXXXXXX) → معرّف supergroup في TDLib (نفس دالة التنفيذ الحقيقي).
  @visibleForTesting
  static int? supergroupIdOf(int chatId) {
    const base = -1000000000000;
    if (chatId > base) return null;
    return base - chatId;
  }
}
