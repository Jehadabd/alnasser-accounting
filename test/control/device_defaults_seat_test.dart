// test/control/device_defaults_seat_test.dart
//
// صندوق ومخزن كل شاشة على الحاسبة الواحدة: الشاشة الأولى على المفتاح القديم،
// وغير المضبوطة ترث إعداد الأولى (نفس السلوك السابق)، و«بلا» صريحة لا ترث.

import 'package:alnaser/erp/device_defaults.dart';
import 'package:alnaser/services/seat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SeatService.seat = 1;
  });

  test('الإعداد القديم (مفتاح بلا رقم شاشة) يبقى للشاشة الأولى', () async {
    SharedPreferences.setMockInitialValues({'erp_device_cash_box_id': 3, 'erp_device_warehouse_id': 2});
    expect(await DeviceDefaults.cashBoxId(), 3);
    expect(await DeviceDefaults.warehouseId(), 2);
  });

  test('شاشة غير مضبوطة ترث الأولى، ثم تُضبط وحدها', () async {
    await DeviceDefaults.set(cashBoxId: 5, warehouseId: 1); // الشاشة 1
    expect(await DeviceDefaults.cashBoxId(seat: 2), 5);
    var all = await DeviceDefaults.allSeats(3);
    expect(all.map((s) => s.inherited), [false, true, true]);

    await DeviceDefaults.set(seat: 2, cashBoxId: 7, warehouseId: 1);
    expect(await DeviceDefaults.cashBoxId(seat: 2), 7);
    expect(await DeviceDefaults.cashBoxId(seat: 1), 5);
    expect(await DeviceDefaults.cashBoxId(seat: 3), 5);

    // «بلا» للشاشة 3 = الصندوق الافتراضي، لا إعداد الأولى
    await DeviceDefaults.set(seat: 3);
    expect(await DeviceDefaults.cashBoxId(seat: 3), isNull);
    expect(await DeviceDefaults.warehouseId(seat: 3), isNull);
    all = await DeviceDefaults.allSeats(3);
    expect(all.map((s) => s.cashBoxId), [5, 7, null]);
    expect(all.map((s) => s.inherited), [false, false, false]);

    // «بلا» للأولى تحذف مفتاحها كما كانت
    await DeviceDefaults.set(seat: 1);
    expect(await DeviceDefaults.cashBoxId(seat: 1), isNull);
    expect((await SharedPreferences.getInstance()).containsKey('erp_device_cash_box_id'), isFalse);
  });

  test('بلا رقم: الشاشة الحالية', () async {
    SeatService.seat = 2;
    await DeviceDefaults.set(cashBoxId: 9);
    expect(await DeviceDefaults.cashBoxId(), 9);
    expect(await DeviceDefaults.cashBoxId(seat: 1), isNull);
  });
}
