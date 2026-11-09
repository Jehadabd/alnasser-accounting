// lib/org/screens/user_scope_screen.dart
//
// 🔐 «نطاق الموظفين»: لكل موظف (غير مدير) المخازن التي يحق له البيع منها والشراء إليها
// والتحويل منها. بلا اختيار = كل المخازن (كما كان). للمدير فقط.

import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../widgets/settings_kit.dart';
import '../org_service.dart';
import '../warehouse_scope.dart';

class UserScopeScreen extends StatefulWidget {
  const UserScopeScreen({super.key});
  @override
  State<UserScopeScreen> createState() => _UserScopeScreenState();
}

class _UserScopeScreenState extends State<UserScopeScreen> {
  List<AppUser>? _users;
  List<Warehouse> _warehouses = const [];
  final _edits = <int, Set<String>>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = (await AuthService().getAllUsers()).where((u) => !u.isAdmin && u.id != null).toList();
    final wh = await OrgService().warehouses(activeOnly: true);
    if (!mounted) return;
    setState(() {
      _users = users;
      _warehouses = wh;
      _edits.clear();
    });
  }

  Set<String> _codes(AppUser u) => _edits[u.id!] ?? WarehouseScope.codesOf(u);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final u in _users ?? const <AppUser>[]) {
        final e = _edits[u.id!];
        if (e != null) await WarehouseScope.setScope(u, e);
      }
      if (mounted) setToast(context, 'حُفظ نطاق الموظفين');
      await _load();
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!(AuthService().currentUser?.isAdmin ?? true)) {
      return const SettingsScaffold(
          title: 'نطاق الموظفين', icon: Icons.lock_person_rounded, children: [SetBanner('للمدير فقط', kind: SetBannerKind.warn)]);
    }
    final users = _users;
    return SettingsScaffold(
      title: 'نطاق الموظفين',
      icon: Icons.lock_person_rounded,
      subtitle: 'من أي مخزن يبيع كل موظف ويشتري ويحوّل',
      bottom: _edits.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.all(12),
              child: SetPrimaryButton(label: 'حفظ', icon: Icons.save_rounded, busy: _saving, onPressed: _save),
            ),
      children: [
        const SetBanner(
          'بلا اختيار = كل المخازن (كما كان). المقيَّد لا يحفظ بيعاً إلا إن كان مخزن الجهاز من مخازنه، '
          'ولا شراءً أو تحويلاً إلا من مخازنه. المدير لا يُقيَّد.',
        ),
        const SizedBox(height: 12),
        if (users == null)
          const LinearProgressIndicator()
        else if (users.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا موظفون (غير المدير) بعد')))
        else
          for (final u in users)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SetCard(
                title: u.shownName,
                subtitle: _codes(u).isEmpty ? 'كل المخازن' : '${_codes(u).length} مخزن',
                icon: Icons.person_rounded,
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final w in _warehouses)
                    FilterChip(
                      label: Text(w.name),
                      selected: _codes(u).contains(w.code),
                      onSelected: (on) => setState(() {
                        final s = {..._codes(u)};
                        on ? s.add(w.code) : s.remove(w.code);
                        _edits[u.id!] = s;
                      }),
                    ),
                ]),
              ),
            ),
        const SizedBox(height: 60),
      ],
    );
  }
}
