import 'package:alnaser/models/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _u(List<String> p) =>
    AppUser(username: 'x', passwordHash: '', role: 'accountant', createdAt: DateTime(2026), permissions: p);

void main() {
  test('old employee with debt register keeps every button except repair', () {
    final u = _u([AppPermissions.debtRegister]);
    for (final k in AppPermissions.debtKeys) {
      expect(u.hasPermission(k), k != AppPermissions.drRepair, reason: k);
    }
  });

  test('old employee with accounting also keeps repair', () {
    final u = _u([AppPermissions.debtRegister, AppPermissions.accounting]);
    expect(u.hasPermission(AppPermissions.drRepair), isTrue);
  });

  test('explicit buttons: only what was chosen', () {
    final u = _u([AppPermissions.debtRegister, AppPermissions.drView, AppPermissions.drPayment]);
    expect(u.hasPermission(AppPermissions.drPayment), isTrue);
    expect(u.hasPermission(AppPermissions.drAddDebt), isFalse);
    expect(u.hasPermission(AppPermissions.drDeleteCustomer), isFalse);
  });

  test('view-only employee (register + view marker) gets no buttons', () {
    final u = _u([AppPermissions.debtRegister, AppPermissions.drView]);
    for (final k in AppPermissions.debtKeys) {
      expect(u.hasPermission(k), isFalse, reason: k);
    }
  });

  test('no debt register: no debt buttons', () {
    final u = _u([AppPermissions.createInvoice]);
    expect(u.hasPermission(AppPermissions.drPayment), isFalse);
  });

  test('expandLegacy writes the old powers explicitly', () {
    final s = AppPermissions.expandLegacy([AppPermissions.debtRegister]);
    expect(s, contains(AppPermissions.drView));
    expect(s, contains(AppPermissions.drAddDebt));
    expect(s, isNot(contains(AppPermissions.drRepair)));
  });

  test('every template that opens the register carries the view marker', () {
    for (final t in AppPermissions.roleTemplates.entries) {
      if (t.value.contains(AppPermissions.debtRegister)) {
        expect(t.value, contains(AppPermissions.drView), reason: t.key);
      }
    }
  });
}
