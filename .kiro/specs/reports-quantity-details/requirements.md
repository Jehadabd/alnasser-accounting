# Requirements Document

## Introduction

تحسين تقارير الأشخاص والبضاعة بإضافة تفاصيل الكميات المشتراة مع النظام الهرمي للوحدات، وإمكانية الترتيب حسب الكمية أو الربح.

## Glossary

- **النظام الهرمي (Unit Hierarchy)**: تسلسل الوحدات للمنتج (قطعة → كرتون، متر → لفة)
- **التحويل الهرمي**: تحويل الكمية من الوحدة الأساسية للوحدة الأكبر
- **الأكثر سحباً**: الترتيب حسب الكمية المشتراة (تنازلياً)
- **الأكثر ربحاً**: الترتيب حسب قيمة الربح (تنازلياً)
- **تقارير الأشخاص**: شاشة عرض بيانات العملاء ومشترياتهم
- **تقارير البضاعة**: شاشة عرض بيانات المنتجات ومبيعاتها

## Requirements

### Requirement 1

**User Story:** As a user, I want to see the profit margin percentage for each customer in the people reports, so that I can quickly assess customer profitability.

#### Acceptance Criteria

1. WHEN a user views the people reports list THEN the system SHALL display the profit margin percentage for each customer alongside existing metrics
2. WHEN calculating profit margin THEN the system SHALL compute it as (totalProfit / totalSales * 100) with one decimal place precision
3. WHEN total sales is zero THEN the system SHALL display 0% as the profit margin

### Requirement 2

**User Story:** As a user, I want to view all products purchased by a specific customer with quantities and hierarchical unit conversion, so that I can understand their purchasing patterns.

#### Acceptance Criteria

1. WHEN a user taps on a customer card in people reports THEN the system SHALL display a clickable button labeled "المنتجات المشتراة"
2. WHEN a user taps the "المنتجات المشتراة" button THEN the system SHALL display a dialog or screen showing all products purchased by that customer
3. WHEN displaying product list THEN the system SHALL show for each product: product name, quantity (with hierarchical conversion), total amount, and profit
4. WHEN displaying quantity THEN the system SHALL show the base unit quantity followed by the hierarchical conversion in the same field (e.g., "500 متر = 5 لفات")
5. WHEN a product has no unit hierarchy (single unit only) THEN the system SHALL display only the base quantity (e.g., "10 قطعة")
6. WHEN displaying the product list THEN the system SHALL sort by quantity (most purchased) by default

### Requirement 3

**User Story:** As a user, I want to sort the customer's purchased products list by quantity, amount, or profit, so that I can analyze their purchases from different perspectives.

#### Acceptance Criteria

1. WHEN viewing the purchased products list THEN the system SHALL provide a toggle or dropdown with three options: "الأكثر سحباً (كمية)", "الأكثر سحباً (مبلغ)", and "الأكثر ربحاً"
2. WHEN user selects "الأكثر سحباً (كمية)" THEN the system SHALL sort products by total quantity in descending order
3. WHEN user selects "الأكثر سحباً (مبلغ)" THEN the system SHALL sort products by total amount in descending order
4. WHEN user selects "الأكثر ربحاً" THEN the system SHALL sort products by profit amount in descending order
5. WHEN sort option changes THEN the system SHALL immediately update the list order without requiring a refresh

### Requirement 4

**User Story:** As a user, I want to view all customers who purchased a specific product with quantities and hierarchical conversion, so that I can understand product demand distribution.

#### Acceptance Criteria

1. WHEN a user views a product card in product reports THEN the system SHALL display a clickable button labeled "العملاء المشترين"
2. WHEN a user taps the "العملاء المشترين" button THEN the system SHALL display a dialog or screen showing all customers who purchased that product
3. WHEN displaying customer list THEN the system SHALL show for each customer: customer name, quantity (with hierarchical conversion), total amount paid, and profit generated
4. WHEN displaying quantity THEN the system SHALL show the base unit quantity followed by the hierarchical conversion in the same field (e.g., "200 متر = 2 لفات")
5. WHEN displaying the customer list THEN the system SHALL sort by quantity (most purchased) by default

### Requirement 5

**User Story:** As a user, I want to sort the product's customer list by quantity, amount, or profit, so that I can identify top customers by volume or profitability.

#### Acceptance Criteria

1. WHEN viewing the customers list for a product THEN the system SHALL provide a toggle with three options: "الأكثر سحباً (كمية)", "الأكثر سحباً (مبلغ)", and "الأكثر ربحاً"
2. WHEN user selects "الأكثر سحباً (كمية)" THEN the system SHALL sort customers by quantity purchased in descending order
3. WHEN user selects "الأكثر سحباً (مبلغ)" THEN the system SHALL sort customers by total amount in descending order
4. WHEN user selects "الأكثر ربحاً" THEN the system SHALL sort customers by profit generated in descending order

### Requirement 6

**User Story:** As a user, I want the same product/customer details available at yearly and monthly levels, so that I can analyze data for specific time periods.

#### Acceptance Criteria

1. WHEN viewing a customer's yearly details THEN the system SHALL provide access to "المنتجات المشتراة" for that specific year
2. WHEN viewing a customer's monthly details THEN the system SHALL provide access to "المنتجات المشتراة" for that specific month
3. WHEN viewing a product's yearly details THEN the system SHALL provide access to "العملاء المشترين" for that specific year
4. WHEN viewing a product's monthly details THEN the system SHALL provide access to "العملاء المشترين" for that specific month
5. WHEN filtering by year or month THEN the system SHALL only include transactions from that time period in calculations

### Requirement 7

**User Story:** As a user, I want the hierarchical conversion to respect each product's defined unit structure, so that conversions are accurate for different product types.

#### Acceptance Criteria

1. WHEN converting quantities THEN the system SHALL use the product's defined unit hierarchy from the database
2. WHEN a product uses meters with rolls THEN the system SHALL convert using the product's lengthPerUnit value
3. WHEN a product uses pieces with cartons THEN the system SHALL convert using the product's unitsInLargeUnit value
4. WHEN a product has multiple hierarchy levels THEN the system SHALL display conversion to the immediate larger unit
5. WHEN conversion results in a decimal THEN the system SHALL display up to one decimal place (e.g., "1.5 لفة")
