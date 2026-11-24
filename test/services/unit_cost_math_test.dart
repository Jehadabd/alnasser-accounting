import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/unit_cost_math.dart';

void main() {
  final h3 = jsonEncode([
    {'unit_name': 'علبة', 'quantity': 12},
    {'unit_name': 'كرتون', 'quantity': 10},
  ]);

  group('معامل التحويل التراكمي', () {
    test('الأساس = 1 باسمه الداخلي والمعروض', () {
      expect(UnitCostMath.factorOf(baseUnit: 'piece', unit: 'قطعة', hierarchy: h3), 1);
      expect(UnitCostMath.factorOf(baseUnit: 'piece', unit: 'piece', hierarchy: h3), 1);
    });
    test('كرتون = 10 علب × 12 = 120 لا 10', () {
      expect(UnitCostMath.factorOf(baseUnit: 'piece', unit: 'علبة', hierarchy: h3), 12);
      expect(UnitCostMath.factorOf(baseUnit: 'piece', unit: 'كرتون', hierarchy: h3), 120);
    });
    test('أساس غير القطعة (كغم، متر) يعمل بالهرم نفسه', () {
      final h = jsonEncode([{'unit_name': 'كيس', 'quantity': 25}]);
      expect(UnitCostMath.factorOf(baseUnit: 'كغم', unit: 'كيس', hierarchy: h), 25);
      final roll = jsonEncode([{'unit_name': 'لفة', 'quantity': 100}]);
      expect(UnitCostMath.factorOf(baseUnit: 'meter', unit: 'لفة', hierarchy: roll), 100);
    });
    test('طول اللفة المسجّل يسبق الهرم', () {
      expect(UnitCostMath.factorOf(baseUnit: 'meter', unit: 'لفة', lengthPerUnit: 50), 50);
    });
    test('وحدة مجهولة أو سلسلة مكسورة ⇒ null لا تخمين', () {
      expect(UnitCostMath.factorOf(baseUnit: 'piece', unit: 'طرد', hierarchy: h3), isNull);
      final broken = jsonEncode([
        {'unit_name': 'علبة', 'quantity': 0},
        {'unit_name': 'كرتون', 'quantity': 10},
      ]);
      expect(UnitCostMath.factorOf(baseUnit: 'piece', unit: 'كرتون', hierarchy: broken), isNull);
    });
    test('JSON بعلامات مفردة وكمية نصية', () {
      const h = "[{'unit_name': 'كرتون', 'quantity': '24'}]";
      expect(UnitCostMath.factorOf(baseUnit: 'piece', unit: 'كرتون', hierarchy: h), 24);
    });
  });

  group('الكلفة', () {
    test('جدول unit_costs لكل الوحدات ولأي أساس', () {
      final m = UnitCostMath.unitCosts(baseUnit: 'piece', baseCost: 500, hierarchy: h3);
      expect(m, {'قطعة': 500.0, 'علبة': 6000.0, 'كرتون': 60000.0});
      final k = UnitCostMath.unitCosts(baseUnit: 'كغم', baseCost: 1000, hierarchy: jsonEncode([{'unit_name': 'كيس', 'quantity': 25}]));
      expect(k, {'كغم': 1000.0, 'كيس': 25000.0});
    });
    test('كلفة الأساس من سعر شراء الكرتون: 60,000 ÷ 120 = 500', () {
      expect(UnitCostMath.baseCostFromBuy(baseUnit: 'piece', buyUnit: 'كرتون', buyCost: 60000, hierarchy: h3), 500);
      expect(UnitCostMath.baseCostFromBuy(baseUnit: 'piece', buyUnit: 'قطعة', buyCost: 500, hierarchy: h3), 500);
      expect(UnitCostMath.baseCostFromBuy(baseUnit: 'piece', buyUnit: 'طرد', buyCost: 1, hierarchy: h3), isNull);
    });
    test('ذهاب وإياب: الكلفة من الأساس ثم الأساس من الكلفة', () {
      final c = UnitCostMath.costOf(baseUnit: 'piece', unit: 'كرتون', baseCost: 750, hierarchy: h3)!;
      expect(UnitCostMath.baseCostFromBuy(baseUnit: 'piece', buyUnit: 'كرتون', buyCost: c, hierarchy: h3), 750);
    });
  });
}
