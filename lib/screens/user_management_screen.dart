// screens/user_management_screen.dart
//
// 👥 الموظفون والصلاحيات
//   • المدير: صاحب البرنامج على هذا الجهاز (كل الصلاحيات، لا يُحذف).
//     منفصل عن حساب الترخيص: يختار اسمه وكلمة سره، ويغيّرهما من هنا.
//   • كل موظف: اسم دخول + كلمة سر + صلاحيات. قوالب جاهزة (كاشير، أمين مخزن،
//     محاسب، مدير فرع) تملأ الصلاحيات بضغطة ثم تُعدَّل كما تريد.
//   • المدير يغيّر كلمة سر أي موظف أو صلاحياته أو يحذفه.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/firebase_sync/users_sync_service.dart';
import '../widgets/user_menu_button.dart' show showChangeOwnPasswordDialog;

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

/// تجميع الصلاحيات في أقسام مفهومة بدل قائمة طويلة واحدة
const List<(String, IconData, List<String>)> _permissionGroups = [
  ('العمل اليومي', Icons.today, [
    AppPermissions.posAccess,
    AppPermissions.createInvoice,
    AppPermissions.editInvoices,
    AppPermissions.debtRegister,
    AppPermissions.addCustomer,
    AppPermissions.addTransaction,
    AppPermissions.lateCustomers,
    AppPermissions.shareDebtsPdf,
    AppPermissions.productEntry,
    AppPermissions.suppliers,
  ]),
  ('المبيعات والتحصيل', Icons.point_of_sale, [
    AppPermissions.salesDocs,
    AppPermissions.collection,
    AppPermissions.debtReports,
    AppPermissions.customerCard,
  ]),
  ('المخزون', Icons.inventory_2_outlined, [
    AppPermissions.editProducts,
    AppPermissions.monthlyInventory,
    AppPermissions.itemCard,
    AppPermissions.stockTransfer,
    AppPermissions.inventoryDocs,
    AppPermissions.priceTools,
    AppPermissions.inventoryReports,
    AppPermissions.manageBranches,
  ]),
  ('المحاسبة والتقارير', Icons.account_balance_outlined, [
    AppPermissions.accounting,
    AppPermissions.accountingPost,
    AppPermissions.viewCostProfit,
    AppPermissions.reports,
    AppPermissions.dashboard,
    AppPermissions.currencies,
    AppPermissions.periodClose,
  ]),
  ('الإدارة', Icons.admin_panel_settings_outlined, [
    AppPermissions.settings,
    AppPermissions.uploadDatabase,
    AppPermissions.networkSettings,
    AppPermissions.manageUsers,
  ]),
];

class _UserManagementScreenState extends State<UserManagementScreen> {
  final AuthService _auth = AuthService();
  List<AppUser> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final users = await _auth.getAllUsers();
    if (!mounted) return;
    setState(() {
      _users = users;
      _isLoading = false;
    });
  }

  /// اسم القالب المطابق لصلاحيات الموظف (إن طابق أحدها تماماً)
  String? _templateOf(AppUser u) {
    final set = u.permissions.toSet();
    for (final t in AppPermissions.roleTemplates.entries) {
      if (t.value.toSet().length == set.length && set.containsAll(t.value)) return t.key;
    }
    return null;
  }

  // ─────────────────────────── إضافة / تعديل ───────────────────────────

  Future<void> _editEmployee({AppUser? user}) async {
    final isNew = user == null;
    final nameCtrl = TextEditingController(text: user?.displayName ?? '');
    final userCtrl = TextEditingController(text: user?.username ?? '');
    final passCtrl = TextEditingController();
    final perms = <String>{...(user?.permissions ?? AppPermissions.roleTemplates['كاشير']!)};
    String? err;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                color: const Color(0xFF0F3460),
                child: Row(children: [
                  Icon(isNew ? Icons.person_add : Icons.manage_accounts, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(isNew ? 'موظف جديد' : 'تعديل الموظف ${user.shownName}',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'اسم الموظف', hintText: 'مثال: محمد أحمد', prefixIcon: Icon(Icons.badge)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: userCtrl,
                        enabled: isNew,
                        decoration: const InputDecoration(labelText: 'اسم الدخول', prefixIcon: Icon(Icons.person)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: passCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: isNew ? 'كلمة السر' : 'كلمة سر جديدة (اتركها فارغة للإبقاء)',
                          prefixIcon: const Icon(Icons.lock),
                        ),
                      ),
                    ),
                  ]),
                  if (err != null)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Colors.red))),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Text('قالب جاهز:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final t in AppPermissions.roleTemplates.entries)
                          ChoiceChip(
                            label: Text(t.key),
                            selected: perms.length == t.value.length && perms.containsAll(t.value),
                            onSelected: (_) => setD(() => perms
                              ..clear()
                              ..addAll(t.value)),
                          ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('${perms.length} صلاحية مختارة — عدّلها كما تريد:',
                      style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  const SizedBox(height: 8),
                  for (final g in _permissionGroups)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(g.$2, size: 18, color: const Color(0xFF0F3460)),
                            const SizedBox(width: 6),
                            Text(g.$1, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F3460))),
                            const Spacer(),
                            TextButton(
                              onPressed: () => setD(() {
                                if (g.$3.every(perms.contains)) {
                                  perms.removeAll(g.$3);
                                } else {
                                  perms.addAll(g.$3);
                                }
                              }),
                              child: Text(g.$3.every(perms.contains) ? 'إلغاء الكل' : 'تحديد الكل'),
                            ),
                          ]),
                          Wrap(spacing: 4, runSpacing: 0, children: [
                            for (final k in g.$3)
                              SizedBox(
                                width: 330,
                                child: CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  value: perms.contains(k),
                                  title: Text(AppPermissions.allPermissions[k] ?? k, style: const TextStyle(fontSize: 13)),
                                  onChanged: (v) => setD(() {
                                    if (v == true) {
                                      perms.add(k);
                                    } else {
                                      perms.remove(k);
                                    }
                                  }),
                                ),
                              ),
                          ]),
                        ]),
                      ),
                    ),
                ]),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: Text(isNew ? 'إضافة الموظف' : 'حفظ التعديل'),
                    onPressed: () async {
                      final uname = userCtrl.text.trim();
                      if (isNew && (uname.isEmpty || passCtrl.text.isEmpty)) {
                        setD(() => err = 'اكتب اسم الدخول وكلمة السر');
                        return;
                      }
                      if (perms.isEmpty) {
                        setD(() => err = 'اختر صلاحية واحدة على الأقل');
                        return;
                      }
                      if (isNew) {
                        final created = await _auth.createAccountant(uname, passCtrl.text, perms.toList());
                        if (created == null) {
                          setD(() => err = 'اسم الدخول موجود مسبقاً');
                          return;
                        }
                        await _setDisplayName(created.id!, nameCtrl.text.trim());
                      } else {
                        final id = user.id!;
                        await _auth.updateUserPermissions(id, perms.toList());
                        await _setDisplayName(id, nameCtrl.text.trim());
                        if (passCtrl.text.isNotEmpty) await _auth.setPassword(id, passCtrl.text);
                      }
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
    if (saved == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isNew ? 'أُضيف الموظف. يدخل باسمه وكلمة سره من شاشة الدخول.' : 'حُفظ التعديل'),
        backgroundColor: Colors.green,
      ));
      _load();
    }
  }

  /// ✏️ المدير يغيّر اسم دخوله (مثلاً: أُنشئ قديماً باسم حساب الترخيص).
  Future<void> _renameSelf(AppUser user) async {
    final ctrl = TextEditingController(text: user.username);
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('تغيير اسم الدخول'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الاسم الذي تكتبه في شاشة الدخول. العمليات السابقة تبقى مسجّلة بالاسم القديم.',
                  style: TextStyle(color: Colors.black54, height: 1.5)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(labelText: 'اسم الدخول الجديد', errorText: err, border: const OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final name = ctrl.text.trim();
                if (name.isEmpty) {
                  setD(() => err = 'اكتب الاسم');
                  return;
                }
                if (name == user.username) {
                  Navigator.pop(ctx, false);
                  return;
                }
                final done = await _auth.renameUser(user.id!, name);
                if (!done) {
                  setD(() => err = 'هذا الاسم مستعمل لمستخدم آخر');
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم تغيير اسم الدخول — استعمله في المرة القادمة'),
        backgroundColor: Colors.green,
      ));
      _load();
    }
  }

  Future<void> _setDisplayName(int userId, String name) async {
    try {
      final db = await DatabaseService().database;
      await db.update('users', {'display_name': name.isEmpty ? null : name}, where: 'id = ?', whereArgs: [userId]);
      await UsersSyncService.instance.markChanged(userId);
    } catch (_) {}
  }

  Future<void> _deleteUser(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الموظف'),
        content: Text('حذف «${user.shownName}» يمنعه من الدخول. عملياته السابقة تبقى مسجّلة باسمه. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true && user.id != null) {
      await _auth.deleteUser(user.id!);
      _load();
    }
  }

  // ─────────────────────────── الواجهة ───────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_auth.hasPermission(AppPermissions.manageUsers)) {
      return Scaffold(
        appBar: AppBar(title: const Text('الموظفون والصلاحيات')),
        body: const Center(child: Text('هذه الشاشة للمدير أو لمن يملك صلاحية «إدارة المستخدمين»')),
      );
    }
    final me = _auth.currentUser;
    final df = DateFormat('yyyy/MM/dd HH:mm');
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('الموظفون والصلاحيات'),
        backgroundColor: const Color(0xFF0F3460),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editEmployee(),
        icon: const Icon(Icons.person_add),
        label: const Text('موظف جديد'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'كل من يستخدم البرنامج يدخل باسمه. المدير يملك كل الصلاحيات، وحسابه منفصل عن حساب الترخيص. '
                    'الموظف يرى الأزرار والشاشات التي تسمح بها صلاحياته فقط، وتُسجَّل عملياته باسمه.',
                    style: TextStyle(color: Colors.black54, height: 1.5),
                  ),
                ),
                for (final u in _users)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: CircleAvatar(
                        backgroundColor: u.isAdmin ? const Color(0xFF0F3460) : Colors.blue.shade50,
                        child: Icon(u.isAdmin ? Icons.admin_panel_settings : Icons.person,
                            color: u.isAdmin ? Colors.white : Colors.blue),
                      ),
                      title: Row(children: [
                        Text(u.shownName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        _chip(u.isAdmin ? 'مدير' : (_templateOf(u) ?? 'موظف'),
                            u.isAdmin ? const Color(0xFF0F3460) : Colors.teal),
                        if (me?.id == u.id) ...[const SizedBox(width: 6), _chip('أنت', Colors.green)],
                      ]),
                      subtitle: Text(
                        'اسم الدخول: ${u.username}'
                        '${u.isAdmin ? ' • كل الصلاحيات' : ' • ${u.permissions.length} صلاحية'}'
                        '${u.lastLoginAt != null ? ' • آخر دخول ${df.format(u.lastLoginAt!)}' : ''}',
                      ),
                      trailing: u.isAdmin
                          ? (me?.id == u.id
                              ? Row(mainAxisSize: MainAxisSize.min, children: [
                                  TextButton.icon(
                                    onPressed: () => _renameSelf(u),
                                    icon: const Icon(Icons.drive_file_rename_outline),
                                    label: const Text('تغيير اسم الدخول'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => showChangeOwnPasswordDialog(context),
                                    icon: const Icon(Icons.password),
                                    label: const Text('تغيير كلمة السر'),
                                  ),
                                ])
                              : null)
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              TextButton.icon(
                                onPressed: () => _editEmployee(user: u),
                                icon: const Icon(Icons.edit),
                                label: const Text('تعديل'),
                              ),
                              if (me?.id != u.id)
                                IconButton(
                                  tooltip: 'حذف',
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _deleteUser(u),
                                ),
                            ]),
                    ),
                  ),
                if (_users.where((u) => !u.isAdmin).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('لا يوجد موظفون بعد — اضغط «موظف جديد» واختر قالباً مثل «كاشير».',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
              ],
            ),
    );
  }

  static Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold)),
      );
}
