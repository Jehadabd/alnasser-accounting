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
import '../erp/erp_kit.dart' show ErpDialog;
import '../widgets/settings_kit.dart';
import '../widgets/user_menu_button.dart' show showChangeOwnPasswordDialog;
import '../services/invoice_staff_service.dart' show InvoiceStaff;
import '../services/employee_salary.dart'; // 💵

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

/// تجميع الصلاحيات في أقسام مفهومة بدل قائمة طويلة واحدة
const List<(String, IconData, List<String>)> _permissionGroups = [
  ('العمل اليومي', Icons.today_rounded, [
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
  ('المبيعات والتحصيل', Icons.point_of_sale_rounded, [
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
  ('التقارير المسموحة', Icons.insights_rounded, AppPermissions.reportKeys),
  ('الإدارة', Icons.admin_panel_settings_outlined, [
    AppPermissions.settings,
    AppPermissions.uploadDatabase,
    AppPermissions.networkSettings,
    AppPermissions.manageUsers,
  ]),
];

/// أيقونة ولون لكل قالب جاهز (والافتراضي لأي قالب يُضاف لاحقاً).
(IconData, Color) _templateLook(String name) => switch (name) {
      'كاشير' => (Icons.point_of_sale_rounded, const Color(0xFF0E7490)),
      'أمين مخزن' => (Icons.inventory_2_rounded, const Color(0xFFB45309)),
      'محاسب' => (Icons.calculate_rounded, const Color(0xFF6D28D9)),
      'مدير فرع' => (Icons.store_mall_directory_rounded, const Color(0xFF047857)),
      _ => (Icons.badge_rounded, const Color(0xFF475569)),
    };

class _UserManagementScreenState extends State<UserManagementScreen> {
  final AuthService _auth = AuthService();
  List<AppUser> _users = [];
  Map<int, double> _salaries = const {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final users = await _auth.getAllUsers();
    final salaries = await EmployeeSalary.all();
    if (!mounted) return;
    _salaries = salaries;
    setState(() {
      _users = users;
      _isLoading = false;
    });
  }

  /// اسم القالب المطابق لصلاحيات الموظف (إن طابق أحدها تماماً)
  String? _templateOf(AppUser u) {
    final set = AppPermissions.expandLegacy(u.permissions);
    for (final t in AppPermissions.roleTemplates.entries) {
      if (t.value.toSet().length == set.length && set.containsAll(t.value)) return t.key;
    }
    return null;
  }

  // ─────────────────────────── إضافة / تعديل ───────────────────────────

  Future<void> _editEmployee({AppUser? user}) async {
    final isNew = user == null;
    final nameCtrl = TextEditingController(text: user?.displayName ?? '');
    final titleCtrl = TextEditingController(text: user?.jobTitle ?? '');
    final userCtrl = TextEditingController(text: user?.username ?? '');
    final passCtrl = TextEditingController();
    // 💵 الراتب الشهري (اختياري) — يظهر في التقرير الشهري والسنوي
    final oldSalary = user?.id == null ? null : await EmployeeSalary.of(user!.id!);
    if (!mounted) return;
    final salaryCtrl = TextEditingController(
        text: oldSalary == null || oldSalary <= 0 ? '' : NumberFormat('#,##0.##', 'en_US').format(oldSalary));
    // الموظف القديم الذي يملك «التقارير» فقط: تظهر كل التقارير مختارة صراحةً
    final perms = AppPermissions.expandLegacy(user?.permissions ?? AppPermissions.roleTemplates['كاشير']!);
    // «التقارير» تفتح الشاشة، والتقارير المحددة تحدد ما يظهر داخلها
    void normalizeReports(String changed, bool on) {
      if (AppPermissions.isReportKey(changed) && on) perms.add(AppPermissions.reports);
      if (changed == AppPermissions.reports) {
        if (on && !perms.any(AppPermissions.isReportKey)) perms.addAll(AppPermissions.reportKeys);
        if (!on) perms.removeWhere(AppPermissions.isReportKey);
      }
      if (AppPermissions.isReportKey(changed) && !on && !perms.any(AppPermissions.isReportKey)) {
        perms.remove(AppPermissions.reports);
      }
    }
    String? err;
    bool busy = false;
    bool showPass = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Future<void> save() async {
            final uname = userCtrl.text.trim();
            if (isNew && (uname.isEmpty || passCtrl.text.isEmpty)) {
              setD(() => err = 'اكتب اسم الدخول وكلمة السر');
              return;
            }
            if (passCtrl.text.isNotEmpty && passCtrl.text.length < 4) {
              setD(() => err = 'كلمة السر قصيرة — 4 أحرف على الأقل');
              return;
            }
            if (perms.isEmpty) {
              setD(() => err = 'اختر صلاحية واحدة على الأقل');
              return;
            }
            final salaryText = salaryCtrl.text.trim().replaceAll(',', '');
            final salary = salaryText.isEmpty ? null : double.tryParse(salaryText);
            if (salaryText.isNotEmpty && (salary == null || salary < 0)) {
              setD(() => err = 'الراتب يُكتب رقماً، مثل 750000');
              return;
            }
            // منع الضغط المزدوج: كان يمكن أن يُنشئ الضغط الثاني خطأ «الاسم موجود» بعد نجاح الأول.
            setD(() {
              busy = true;
              err = null;
            });
            try {
              if (isNew) {
                final created = await _auth.createAccountant(uname, passCtrl.text, perms.toList());
                if (created == null) {
                  if (ctx.mounted) {
                    setD(() {
                      busy = false;
                      err = 'اسم الدخول موجود مسبقاً';
                    });
                  }
                  return;
                }
                await EmployeeSalary.set(created.id!, salary);
                await _setDisplayName(created.id!, nameCtrl.text.trim());
                await _setJobTitle(created.id!, titleCtrl.text.trim());
              } else {
                final id = user.id!;
                await _auth.updateUserPermissions(id, perms.toList());
                await EmployeeSalary.set(id, salary);
                await _setDisplayName(id, nameCtrl.text.trim());
                await _setJobTitle(id, titleCtrl.text.trim());
                if (passCtrl.text.isNotEmpty) await _auth.setPassword(id, passCtrl.text);
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              if (ctx.mounted) {
                setD(() {
                  busy = false;
                  err = 'تعذّر الحفظ: $e';
                });
              }
            }
          }

          final fields = [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'اسم الموظف', hintText: 'مثال: محمد أحمد', prefixIcon: Icon(Icons.badge_outlined)),
            ),
            // 👷 المسمى الوظيفي: يظهر في اختيار «المجهز/المحاسب» في الفاتورة
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: 'المسمى الوظيفي',
                hintText: 'محاسب، مجهز، مدقق...',
                prefixIcon: const Icon(Icons.work_outline_rounded),
                suffixIcon: PopupMenuButton<String>(
                  tooltip: 'اختيار مسمى',
                  icon: const Icon(Icons.arrow_drop_down_rounded),
                  itemBuilder: (_) => [
                    for (final t in InvoiceStaff.jobTitles) PopupMenuItem<String>(value: t, child: Text(t)),
                  ],
                  onSelected: (t) => setD(() => titleCtrl.text = t),
                ),
              ),
            ),
            TextField(
              controller: salaryCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'الراتب الشهري (اختياري)',
                hintText: 'مثال: 750,000',
                helperText: 'يُطرح من الربح في التقرير الشهري والسنوي',
                suffixText: 'دينار',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            TextField(
              controller: userCtrl,
              enabled: isNew,
              decoration: InputDecoration(
                labelText: 'اسم الدخول',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                helperText: isNew ? null : 'لا يُغيَّر بعد الإنشاء',
              ),
            ),
            TextField(
              controller: passCtrl,
              obscureText: !showPass,
              decoration: InputDecoration(
                labelText: isNew ? 'كلمة السر' : 'كلمة سر جديدة',
                helperText: isNew ? null : 'اتركها فارغة للإبقاء على القديمة',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: showPass ? 'إخفاء' : 'إظهار',
                  icon: Icon(showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setD(() => showPass = !showPass),
                ),
              ),
            ),
          ];

          return ErpDialog(
            width: 820,
            title: isNew ? 'موظف جديد' : 'تعديل الموظف',
            subtitle: isNew ? 'اسم دخول وكلمة سر وصلاحيات' : user.shownName,
            icon: isNew ? Icons.person_add_alt_1_rounded : Icons.manage_accounts_rounded,
            content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth >= 640 ? 3 : 1;
                final w = (c.maxWidth - (cols - 1) * 12) / cols;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final f in fields) SizedBox(width: w, child: f),
                ]);
              }),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: err == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey(err),
                        padding: const EdgeInsets.only(top: 12),
                        child: SetBanner(err!, kind: SetBannerKind.error),
                      ),
              ),
              const SizedBox(height: 18),
              const Text('قالب جاهز', style: TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in AppPermissions.roleTemplates.entries)
                  _TemplateChip(
                    name: t.key,
                    selected: perms.length == t.value.length && perms.containsAll(t.value),
                    onTap: () => setD(() => perms
                      ..clear()
                      ..addAll(t.value)),
                  ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                const Text('الصلاحيات', style: TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(10)),
                  child: Text('${perms.length} مختارة',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kSetNavy)),
                ),
                const Spacer(),
                const Text('عدّلها كما تريد', style: TextStyle(fontSize: 12, color: kSetMuted)),
              ]),
              const SizedBox(height: 10),
              for (final g in _permissionGroups)
                _PermGroup(
                  title: g.$1,
                  icon: g.$2,
                  keys: g.$3,
                  selected: perms,
                  onToggle: (k, on) => setD(() {
                    if (on) {
                      perms.add(k);
                    } else {
                      perms.remove(k);
                    }
                    normalizeReports(k, on);
                  }),
                  onToggleAll: (on) => setD(() {
                    if (on) {
                      perms.addAll(g.$3);
                    } else {
                      perms.removeAll(g.$3);
                    }
                    for (final k in g.$3) {
                      normalizeReports(k, on);
                    }
                  }),
                ),
            ]),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton.icon(
                icon: busy
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 19),
                label: Text(isNew ? 'إضافة الموظف' : 'حفظ التعديل'),
                onPressed: busy ? null : save,
              ),
            ],
          );
        },
      ),
    );
    if (saved == true) {
      if (!mounted) return;
      setToast(context, isNew ? 'أُضيف الموظف. يدخل باسمه وكلمة سره من شاشة الدخول.' : 'حُفظ التعديل');
      _load();
    }
  }

  /// ✏️ المدير يغيّر اسم دخوله (مثلاً: أُنشئ قديماً باسم حساب الترخيص).
  Future<void> _renameSelf(AppUser user) async {
    // لا نتخلّص من المتحكم بعد إغلاق النافذة مباشرة: حركة الإغلاق ما زالت تستعمله.
    final ctrl = TextEditingController(text: user.username);
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => ErpDialog(
          title: 'تغيير اسم الدخول',
          subtitle: 'الاسم الذي تكتبه في شاشة الدخول',
          icon: Icons.drive_file_rename_outline_rounded,
          width: 440,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SetBanner('العمليات السابقة تبقى مسجّلة بالاسم القديم.'),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'اسم الدخول الجديد',
                errorText: err,
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton.icon(
              icon: const Icon(Icons.check_rounded, size: 19),
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
                  if (ctx.mounted) setD(() => err = 'هذا الاسم مستعمل لمستخدم آخر');
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      setToast(context, 'تم تغيير اسم الدخول — استعمله في المرة القادمة');
      _load();
    }
  }

  Future<void> _setJobTitle(int userId, String title) async {
    try {
      final db = await DatabaseService().database;
      final cols = (await db.rawQuery('PRAGMA table_info(users)')).map((r) => '${r['name']}').toSet();
      if (!cols.contains('job_title')) await db.execute('ALTER TABLE users ADD COLUMN job_title TEXT');
      await db.update('users', {'job_title': title.isEmpty ? null : title}, where: 'id = ?', whereArgs: [userId]);
      await UsersSyncService.instance.markChanged(userId);
    } catch (_) {}
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
      builder: (ctx) => ErpDialog(
        title: 'حذف الموظف',
        subtitle: user.shownName,
        icon: Icons.person_remove_rounded,
        color: kSetRed,
        width: 440,
        content: const SetBanner(
          'حذف الموظف يمنعه من الدخول على كل الأجهزة. عملياته السابقة تبقى مسجّلة باسمه.',
          kind: SetBannerKind.warn,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kSetRed),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            label: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true && user.id != null) {
      final done = await _auth.deleteUser(user.id!);
      if (!mounted) return;
      setToast(context, done ? 'حُذف الموظف' : 'تعذّر الحذف', error: !done);
      _load();
    }
  }

  // ─────────────────────────── الواجهة ───────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_auth.hasPermission(AppPermissions.manageUsers)) {
      return const SettingsScaffold(
        title: 'الموظفون والصلاحيات',
        icon: Icons.groups_rounded,
        children: [
          SetBanner('هذه الشاشة للمدير أو لمن يملك صلاحية «إدارة المستخدمين».', kind: SetBannerKind.warn),
        ],
      );
    }
    final me = _auth.currentUser;
    final df = DateFormat('yyyy/MM/dd HH:mm');
    final staff = _users.where((u) => !u.isAdmin).toList();
    final admins = _users.where((u) => u.isAdmin).toList();

    return SettingsScaffold(
      title: 'الموظفون والصلاحيات',
      subtitle: 'حسابات الدخول اليومية وصلاحيات كل موظف',
      icon: Icons.groups_rounded,
      loading: _isLoading,
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              backgroundColor: kSetNavy,
              foregroundColor: Colors.white,
              onPressed: () => _editEmployee(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('موظف جديد', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
      children: _isLoading
          ? null
          : [
              SetHero(
                icon: Icons.groups_rounded,
                title: 'كل من يستخدم البرنامج يدخل باسمه',
                text: 'المدير يملك كل الصلاحيات، وحسابه منفصل عن حساب الترخيص. الموظف يرى الأزرار والشاشات '
                    'التي تسمح بها صلاحياته فقط، وتُسجَّل عملياته باسمه.',
                status: Wrap(spacing: 8, runSpacing: 6, children: [
                  SetStatusPill('${admins.length} مدير', ok: true, icon: Icons.admin_panel_settings_rounded),
                  SetStatusPill('${staff.length} موظف', ok: staff.isNotEmpty, icon: Icons.person_rounded),
                ]),
              ),
              if (admins.isNotEmpty)
                SetCard(
                  title: 'المدير',
                  icon: Icons.admin_panel_settings_rounded,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Column(children: [for (final u in admins) _userTile(u, me, df)]),
                ),
              SetCard(
                title: 'الموظفون',
                subtitle: staff.isEmpty ? null : '${staff.length} حساب',
                icon: Icons.badge_rounded,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                trailing: TextButton.icon(
                  onPressed: () => _editEmployee(),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('إضافة'),
                ),
                child: staff.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 26, horizontal: 8),
                        child: Column(children: [
                          Icon(Icons.person_add_alt_1_rounded, size: 44, color: Color(0xFFB8C2CF)),
                          SizedBox(height: 10),
                          Text('لا يوجد موظفون بعد',
                              style: TextStyle(fontWeight: FontWeight.w800, color: kSetText, fontSize: 15)),
                          SizedBox(height: 4),
                          Text('اضغط «موظف جديد» واختر قالباً مثل «كاشير» ثم عدّل الصلاحيات.',
                              textAlign: TextAlign.center, style: TextStyle(color: kSetMuted)),
                        ]),
                      )
                    : Column(children: [for (final u in staff) _userTile(u, me, df)]),
              ),
              const SizedBox(height: 70), // مساحة للزر العائم
            ],
    );
  }

  Widget _userTile(AppUser u, AppUser? me, DateFormat df) {
    final isMe = me?.id == u.id;
    final tpl = _templateOf(u);
    final (IconData roleIcon, Color c) =
        u.isAdmin ? (Icons.admin_panel_settings_rounded, kSetNavy) : _templateLook(tpl ?? '');
    final initial = u.shownName.trim().isEmpty ? '?' : u.shownName.trim().characters.first;

    final actions = <Widget>[
      if (u.isAdmin && isMe) ...[
        OutlinedButton.icon(
          onPressed: () => _renameSelf(u),
          icon: const Icon(Icons.drive_file_rename_outline_rounded, size: 18),
          label: const Text('اسم الدخول'),
        ),
        OutlinedButton.icon(
          onPressed: () => showChangeOwnPasswordDialog(context),
          icon: const Icon(Icons.password_rounded, size: 18),
          label: const Text('كلمة السر'),
        ),
      ],
      if (!u.isAdmin) ...[
        OutlinedButton.icon(
          onPressed: () => _editEmployee(user: u),
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: const Text('تعديل'),
        ),
        if (!isMe)
          IconButton(
            tooltip: 'حذف',
            style: IconButton.styleFrom(backgroundColor: const Color(0xFFFEF2F2)),
            icon: const Icon(Icons.delete_outline_rounded, color: kSetRed),
            onPressed: () => _deleteUser(u),
          ),
      ],
    ];

    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(u.shownName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kSetText)),
        _chip(u.isAdmin ? 'مدير' : (tpl ?? 'صلاحيات مخصّصة'), c),
        if ((u.jobTitle ?? '').trim().isNotEmpty) _chip(u.jobTitle!.trim(), const Color(0xFF7C3AED)),
        if ((_salaries[u.id] ?? 0) > 0)
          _chip('راتب ${NumberFormat('#,##0', 'en_US').format(_salaries[u.id])}', const Color(0xFF0E7490)),
        if (isMe) _chip('أنت', kSetGreen),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 14, runSpacing: 2, children: [
        _meta(Icons.alternate_email_rounded, u.username),
        _meta(Icons.key_rounded, u.isAdmin ? 'كل الصلاحيات' : '${u.permissions.length} صلاحية'),
        if (u.lastLoginAt != null) _meta(Icons.schedule_rounded, 'آخر دخول ${df.format(u.lastLoginAt!)}'),
      ]),
    ]);

    final avatar = Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c, Color.alphaBlend(Colors.white24, c)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ),
      PositionedDirectional(
        bottom: -4,
        end: -4,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(roleIcon, size: 14, color: c),
        ),
      ),
    ]);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFF8FBFF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isMe ? kSetNavy.withValues(alpha: 0.25) : kSetBorder),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 620;
        if (wide) {
          return Row(children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(child: info),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 8),
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
            ],
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(child: info),
          ]),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
          ],
        ]);
      }),
    );
  }

  static Widget _meta(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 14, color: kSetMuted),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
      ]);

  static Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w800)),
      );
}

/// شريحة قالب جاهز (كاشير، أمين مخزن…).
class _TemplateChip extends StatelessWidget {
  const _TemplateChip({required this.name, required this.selected, required this.onTap});
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, c) = _templateLook(name);
    return Material(
      color: selected ? c : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? c : kSetBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: selected ? Colors.white : c),
            const SizedBox(width: 6),
            Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : kSetText)),
          ]),
        ),
      ),
    );
  }
}

/// مجموعة صلاحيات: عنوان + عدّاد + «تحديد الكل» + شرائح قابلة للتبديل.
class _PermGroup extends StatelessWidget {
  const _PermGroup({
    required this.title,
    required this.icon,
    required this.keys,
    required this.selected,
    required this.onToggle,
    required this.onToggleAll,
  });
  final String title;
  final IconData icon;
  final List<String> keys;
  final Set<String> selected;
  final void Function(String key, bool on) onToggle;
  final ValueChanged<bool> onToggleAll;

  @override
  Widget build(BuildContext context) {
    final n = keys.where(selected.contains).length;
    final all = n == keys.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kSetBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 19, color: kSetNavy),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetNavy)),
          const SizedBox(width: 8),
          Text('$n/${keys.length}', style: const TextStyle(fontSize: 12, color: kSetMuted, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => onToggleAll(!all),
            icon: Icon(all ? Icons.remove_done_rounded : Icons.done_all_rounded, size: 18),
            label: Text(all ? 'إلغاء الكل' : 'تحديد الكل'),
          ),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in keys)
            _PermToggle(
              label: AppPermissions.allPermissions[k] ?? k,
              on: selected.contains(k),
              onTap: () => onToggle(k, !selected.contains(k)),
            ),
        ]),
      ]),
    );
  }
}

class _PermToggle extends StatelessWidget {
  const _PermToggle({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? kSetNavy.withValues(alpha: 0.08) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: on ? kSetNavy.withValues(alpha: 0.55) : kSetBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: on ? kSetNavy : Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: on ? kSetNavy : const Color(0xFFB8C2CF), width: 1.4),
              ),
              child: on ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: on ? kSetNavy : kSetText, fontWeight: on ? FontWeight.w700 : null)),
            ),
          ]),
        ),
      ),
    );
  }
}
