# Implementation Plan

- [x] 1. Implement CommercialStatementService

  - [x] 1.1 Create service file and basic structure
    - Create `lib/services/commercial_statement_service.dart`
    - Add DatabaseService dependency
    - All data will be returned as Map<String, dynamic> instead of classes
    - _Requirements: 1.1_

  - [x] 1.2 Implement getAvailableYears method
    - Query transactions table to get distinct years for customer
    - Return sorted list of years from earliest to latest
    - _Requirements: 1.3_

  - [x] 1.3 Implement consolidateTransactions method
    - Group transactions by invoice_id
    - Calculate net amount for each invoice group
    - Keep manual transactions (null invoice_id) separate
    - Return List<Map<String, dynamic>>
    - _Requirements: 3.1, 3.2, 4.1_

  - [x] 1.4 Implement calculateOpeningBalance method
    - Sum all amount_changed for transactions before period start date
    - Return 0 for comprehensive statement
    - _Requirements: 5.1, 5.2_

  - [x] 1.5 Implement calculateSummary method
    - Count invoice entries
    - Sum positive amounts (debts)
    - Sum negative amounts (payments)
    - Calculate remaining balance
    - Return Map<String, dynamic>
    - _Requirements: 6.2_

  - [x] 1.6 Implement getCommercialStatement method
    - Fetch transactions for customer within date range
    - Calculate opening balance
    - Consolidate transactions
    - Calculate running balances for each entry
    - Calculate summary
    - Return complete Map<String, dynamic> with all data
    - _Requirements: 2.1, 2.3, 2.4, 8.1, 8.2_

- [x] 2. Implement UI Components

  - [x] 2.1 Create PeriodSelectionDialog widget
    - Create dialog showing "كشف حساب شامل" option
    - Show available years from service
    - When year selected, expand to show months 1-12 and "السنة كاملة"
    - Return selected period (null for comprehensive, or start/end dates)
    - _Requirements: 1.2, 1.3, 2.2_

  - [x] 2.2 Create CommercialStatementScreen
    - Create `lib/screens/commercial_statement_screen.dart`
    - Accept customer and period parameters
    - Display loading state while fetching data
    - _Requirements: 1.1_

  - [x] 2.3 Implement StatementSummary widget section
    - Display summary section at top of screen
    - Show total invoices, total amounts, total payments, remaining balance
    - Color remaining balance red if positive (debt), green if zero or negative
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x] 2.4 Implement statement entries list
    - Show consolidated invoice entries with invoice number and net amount
    - Show manual transactions separately
    - Display running balance after each entry
    - Columns: التاريخ | البيان | المبلغ | الدين قبل | الدين بعد
    - _Requirements: 3.3, 4.2, 5.3, 8.1_

  - [x] 2.5 Implement balance discrepancy warning
    - Check if final balance differs from customer's current_total_debt
    - Display warning banner if difference > 1 dinar
    - _Requirements: 8.3_

- [x] 3. Integrate with CustomerDetailsScreen

  - [x] 3.1 Add commercial statement button to app bar
    - Add IconButton with appropriate icon
    - Add tooltip "كشف الحساب التجاري"
    - _Requirements: 1.1_

  - [x] 3.2 Implement button action
    - Show PeriodSelectionDialog when button pressed
    - Navigate to CommercialStatementScreen with selected period
    - _Requirements: 1.2_

- [x] 4. Implement PDF Export

  - [x] 4.1 Create generateCommercialStatement function
    - Add function to existing pdf_service.dart
    - Load Arabic font (Amiri)
    - _Requirements: 7.1_

  - [x] 4.2 Implement PDF generation logic
    - Create PDF document with customer name and period
    - Add consolidated entries table
    - Add summary section
    - Add final balance
    - Columns: الدين بعد | الدين قبل | المبلغ | البيان | التاريخ
    - _Requirements: 7.2, 7.3_

  - [x] 4.3 Add export button to CommercialStatementScreen
    - Add PDF export button in app bar
    - Handle Windows platform (save and open)
    - Handle other platforms (printing dialog)
    - _Requirements: 7.1, 7.4, 7.5_

- [x] 5. Final Testing
  - Test the complete flow manually
  - Verify consolidation works correctly
  - Verify PDF export works on Windows

## ✅ Implementation Complete

All tasks have been implemented:
- Service: `lib/services/commercial_statement_service.dart`
- Screen: `lib/screens/commercial_statement_screen.dart`
- PDF: `lib/services/pdf_service.dart` (generateCommercialStatement function)
- Integration: `lib/screens/customer_details_screen.dart` (_showCommercialStatement function)

