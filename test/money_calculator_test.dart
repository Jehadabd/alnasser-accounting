import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/utils/money_calculator.dart';

void main() {
  group('MoneyCalculator Tests', () {
    test('Addition should be precise', () {
      // 0.1 + 0.2 normally equals 0.30000000000000004 in double
      expect(MoneyCalculator.add(0.1, 0.2), 0.3);
    });

    test('Subtraction should be precise', () {
      expect(MoneyCalculator.subtract(0.3, 0.1), 0.2);
    });

    test('Multiplication should be precise', () {
      expect(MoneyCalculator.multiply(10.2, 3), 30.6);
      expect(MoneyCalculator.multiply(100.05, 100), 10005.0);
    });

    test('Division should be precise', () {
      expect(MoneyCalculator.divide(10, 3), 3.333); // Default precision is 3
    });

    test('Sum list should be precise', () {
      final numbers = [0.1, 0.1, 0.1];
      expect(MoneyCalculator.sum(numbers), 0.3);
    });
    
    test('Complex calculation scenario', () {
      // Scenario: Invoice Total
      double total = 0.0;
      total = MoneyCalculator.add(total, 100.05); // Item 1
      total = MoneyCalculator.add(total, 200.10); // Item 2
      expect(total, 300.15);
      
      double discount = 0.15;
      double finalTotal = MoneyCalculator.subtract(total, discount);
      expect(finalTotal, 300.0);
    });
  });
}
