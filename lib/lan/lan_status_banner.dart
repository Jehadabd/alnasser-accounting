// lib/lan/lan_status_banner.dart
//
// شريط حالة الاتصال بالسيرفر — يظهر على الطرفية فقط عند انقطاع الاتصال،
// وعلى السيرفر يعرض عدد الطرفيات المتصلة.

import 'dart:async';

import 'package:flutter/material.dart';

import 'lan_bootstrap.dart';
import 'lan_client.dart';
import 'lan_server.dart';

class LanStatusBanner extends StatefulWidget {
  const LanStatusBanner({super.key});

  @override
  State<LanStatusBanner> createState() => _LanStatusBannerState();
}

class _LanStatusBannerState extends State<LanStatusBanner> {
  StreamSubscription<LanLinkState>? _linkSub;
  StreamSubscription<List<LanClientInfo>>? _clientsSub;
  LanLinkState? _link;
  int _clients = 0;
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();
    final c = LanRuntime.client;
    if (c != null) {
      _link = c.state;
      _linkSub = c.stateStream.listen((s) {
        if (mounted) setState(() => _link = s);
      });
    }
    final srv = LanRuntime.server;
    if (srv != null) {
      _clients = srv.clients.length;
      _clientsSub = srv.clientsStream.listen((l) {
        if (mounted) setState(() => _clients = l.length);
      });
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _clientsSub?.cancel();
    super.dispose();
  }

  Future<void> _reconnect() async {
    final c = LanRuntime.client;
    if (c == null) return;
    setState(() => _reconnecting = true);
    try {
      await c.connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (LanRuntime.client != null && _link != LanLinkState.connected) {
      return Material(
        color: const Color(0xFFB91C1C),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            const Icon(Icons.lan_outlined, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _link == LanLinkState.connecting
                    ? 'جارٍ الاتصال بحاسبة السيرفر...'
                    : 'انقطع الاتصال بحاسبة السيرفر — لا تُحفظ أي عملية حتى يعود',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: _reconnecting ? null : _reconnect,
              child: const Text('أعد الاتصال', style: TextStyle(color: Colors.white)),
            ),
          ]),
        ),
      );
    }
    if (LanRuntime.server?.isRunning == true) {
      return Container(
        width: double.infinity,
        color: const Color(0xFF0F3460),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          '🖧 هذه حاسبة السيرفر — $_clients طرفية متصلة',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
