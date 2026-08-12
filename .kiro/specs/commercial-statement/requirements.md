# Requirements Document

## Introduction

كشف الحساب التجاري هو ميزة جديدة تُضاف إلى شاشة تفاصيل العميل في سجل الديون. تختلف عن كشف الحساب العادي بأنها تجمع كل المعاملات المرتبطة بنفس الفاتورة في سطر واحد بدلاً من عرض كل معاملة بشكل منفصل. هذا يوفر رؤية مبسطة وواضحة للحساب التجاري للعميل.

## Glossary

- **Commercial_Statement_System**: نظام كشف الحساب التجاري الذي يجمع المعاملات المرتبطة بالفواتير
- **Consolidated_Invoice_Entry**: سطر مجمع يمثل فاتورة واحدة مع كل تعديلاتها وتسديداتها
- **Manual_Transaction**: معاملة يدوية غير مرتبطة بفاتورة (دفعة نقدية أو دين يدوي)
- **Opening_Balance**: الرصيد الافتتاحي في بداية الفترة المختارة
- **Period_Filter**: فلتر الفترة الزمنية (شامل، سنوي، شهري)
- **Statement_Summary**: ملخص إحصائي للكشف يشمل إجمالي الفواتير والمسدد والمتبقي

## Requirements

### Requirement 1

**User Story:** As a store owner, I want to access commercial account statement from customer details screen, so that I can view a simplified summary of customer transactions.

#### Acceptance Criteria

1. WHEN a user opens customer details screen THEN the Commercial_Statement_System SHALL display a button labeled "كشف الحساب التجاري"
2. WHEN a user clicks the commercial statement button THEN the Commercial_Statement_System SHALL display a dialog with period selection options
3. WHEN the period selection dialog opens THEN the Commercial_Statement_System SHALL show two main options: "كشف حساب شامل" and yearly options starting from the earliest transaction year

### Requirement 2

**User Story:** As a store owner, I want to select different time periods for the commercial statement, so that I can view transactions for specific periods.

#### Acceptance Criteria

1. WHEN a user selects "كشف حساب شامل" THEN the Commercial_Statement_System SHALL generate a statement containing all transactions since the customer started dealing with the store
2. WHEN a user selects a specific year THEN the Commercial_Statement_System SHALL expand to show monthly options (1-12) plus "السنة كاملة" option
3. WHEN a user selects a specific month THEN the Commercial_Statement_System SHALL generate a statement for that month only
4. WHEN a user selects "السنة كاملة" THEN the Commercial_Statement_System SHALL generate a statement for the entire selected year

### Requirement 3

**User Story:** As a store owner, I want invoice-related transactions to be consolidated into single entries, so that I can see the net effect of each invoice clearly.

#### Acceptance Criteria

1. WHEN generating the commercial statement THEN the Commercial_Statement_System SHALL group all transactions with the same invoice_id into a single Consolidated_Invoice_Entry
2. WHEN consolidating invoice transactions THEN the Commercial_Statement_System SHALL calculate the net amount by summing all amount_changed values for that invoice
3. WHEN displaying a Consolidated_Invoice_Entry THEN the Commercial_Statement_System SHALL show the invoice number, date of first transaction, and net amount
4. WHEN a user taps on a Consolidated_Invoice_Entry THEN the Commercial_Statement_System SHALL display a breakdown showing original amount, adjustments, and payments

### Requirement 4

**User Story:** As a store owner, I want manual transactions to appear separately in the statement, so that I can distinguish between invoice-related and manual transactions.

#### Acceptance Criteria

1. WHEN a transaction has no invoice_id THEN the Commercial_Statement_System SHALL display it as a separate Manual_Transaction entry
2. WHEN displaying a Manual_Transaction THEN the Commercial_Statement_System SHALL show the transaction date, type, amount, and note if available

### Requirement 5

**User Story:** As a store owner, I want to see the opening balance for the selected period, so that I can understand the starting point of the statement.

#### Acceptance Criteria

1. WHEN generating a statement for a specific period THEN the Commercial_Statement_System SHALL calculate and display the Opening_Balance at the start of the period
2. WHEN the selected period is "كشف حساب شامل" THEN the Commercial_Statement_System SHALL set Opening_Balance to zero
3. WHEN displaying Opening_Balance THEN the Commercial_Statement_System SHALL show it as the first entry in the statement

### Requirement 6

**User Story:** As a store owner, I want to see quick statistics summary, so that I can get an overview of the customer's account status.

#### Acceptance Criteria

1. WHEN displaying the commercial statement THEN the Commercial_Statement_System SHALL show a Statement_Summary section at the top
2. WHEN calculating Statement_Summary THEN the Commercial_Statement_System SHALL include: total number of invoices, total invoice amounts, total payments received, and remaining balance
3. WHEN the remaining balance is positive THEN the Commercial_Statement_System SHALL display it in red indicating debt
4. WHEN the remaining balance is negative or zero THEN the Commercial_Statement_System SHALL display it in green indicating credit or settled

### Requirement 7

**User Story:** As a store owner, I want to export the commercial statement as a simplified PDF, so that I can print or share it with customers.

#### Acceptance Criteria

1. WHEN viewing the commercial statement THEN the Commercial_Statement_System SHALL provide an export to PDF button
2. WHEN exporting to PDF THEN the Commercial_Statement_System SHALL generate a simplified document with consolidated entries
3. WHEN generating PDF THEN the Commercial_Statement_System SHALL include: customer name, period, Opening_Balance, consolidated entries, Statement_Summary, and final balance
4. IF the platform is Windows THEN the Commercial_Statement_System SHALL save the PDF and open it automatically
5. IF the platform is not Windows THEN the Commercial_Statement_System SHALL use the printing dialog for preview and printing

### Requirement 8

**User Story:** As a store owner, I want the statement to show running balance after each entry, so that I can track how the balance changed over time.

#### Acceptance Criteria

1. WHEN displaying each entry in the statement THEN the Commercial_Statement_System SHALL calculate and show the running balance after that entry
2. WHEN calculating running balance THEN the Commercial_Statement_System SHALL start from Opening_Balance and add/subtract each entry's net amount chronologically
3. WHEN the final running balance differs from customer's current balance by more than 1 dinar THEN the Commercial_Statement_System SHALL display a warning message

