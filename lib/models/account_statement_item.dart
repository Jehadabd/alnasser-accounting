// models/account_statement_item.dart
import 'invoice.dart';
import 'transaction.dart';

class AccountStatementItem {
  final DateTime date;
  final String description;
  final double amount;
  final String type; // 'invoice' or 'transaction'
  final Invoice? invoice;
  final DebtTransaction? transaction;

  double balanceBefore = 0.0;
  double balanceAfter = 0.0;

  AccountStatementItem({
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    this.invoice,
    this.transaction,
  });

  String get formattedAmount {
    if (amount >= 0) {
      return amount.toStringAsFixed(2);
    } else {
      return '(${amount.abs().toStringAsFixed(2)})';
    }
  }

  String get formattedBalanceBefore {
    return balanceBefore.toStringAsFixed(2);
  }

  String get formattedBalanceAfter {
    return balanceAfter.toStringAsFixed(2);
  }

  String get formattedDate {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}
