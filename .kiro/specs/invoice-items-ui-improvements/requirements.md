# Requirements Document

## Introduction

تحسينات تجميلية ووظيفية لشاشة إنشاء الفاتورة، تشمل محاذاة أعمدة جدول أصناف الفاتورة، تحسين شكل حقول الإدخال، وتحسين سلوك التنقل بين الحقول باستخدام مفتاح Enter.

## Glossary

- **Invoice Items Table**: جدول أصناف الفاتورة الذي يعرض الأصناف المضافة للفاتورة
- **Sale Type Dropdown**: قائمة منسدلة لاختيار نوع البيع (قطعة، باكيت، لفة، إلخ)
- **Column Headers**: عناوين الأعمدة في جدول أصناف الفاتورة (ت، المبلغ، ID، التفاصيل، العدد، نوع البيع، السعر، عدد الوحدات)
- **Input Fields**: حقول الإدخال في صفوف الجدول (ID، التفاصيل، العدد، السعر)
- **Smallest Unit**: أصغر وحدة بيع متاحة للمنتج (مثل قطعة أو متر)

## Requirements

### Requirement 1

**User Story:** As a user, I want the column headers to be properly aligned with their corresponding input fields, so that the interface looks professional and is easy to use.

#### Acceptance Criteria

1. WHEN the invoice items table is displayed THEN the system SHALL align each column header directly above its corresponding input field
2. WHEN the "نوع البيع" (Sale Type) header is displayed THEN the system SHALL position it directly above the sale type dropdown
3. WHEN the "السعر" (Price) header is displayed THEN the system SHALL position it directly above the price input field
4. WHEN the "عدد الوحدات" (Units Count) header is displayed THEN the system SHALL position it directly above the units count field

### Requirement 2

**User Story:** As a user, I want the input fields (ID, Details, Quantity, Price) to have visible borders, so that they look consistent with other form elements and are easier to identify.

#### Acceptance Criteria

1. WHEN input fields are displayed in the invoice items table THEN the system SHALL render them with visible rectangular borders
2. WHEN the ID field is displayed THEN the system SHALL show it with a border matching the surrounding container style
3. WHEN the Details field is displayed THEN the system SHALL show it with a border matching the surrounding container style
4. WHEN the Quantity field is displayed THEN the system SHALL show it with a border matching the surrounding container style
5. WHEN the Price field is displayed THEN the system SHALL show it with a border matching the surrounding container style

### Requirement 3

**User Story:** As a user, I want pressing Enter in the Quantity field to automatically select the smallest available unit and move focus to the Price field, so that I can enter invoice items faster using only the keyboard.

#### Acceptance Criteria

1. WHEN a user presses Enter in the Quantity field THEN the system SHALL open the Sale Type dropdown
2. WHEN the Sale Type dropdown is open and the user presses Enter THEN the system SHALL select the smallest available unit (e.g., "قطعة" or "متر")
3. WHEN the smallest unit is selected THEN the system SHALL immediately move focus to the Price field
4. WHEN the product has multiple unit options THEN the system SHALL identify the smallest unit as the first option in the hierarchy (base unit)
5. WHEN the user presses Enter twice from the Quantity field THEN the system SHALL complete the unit selection and focus the Price field within 200 milliseconds
