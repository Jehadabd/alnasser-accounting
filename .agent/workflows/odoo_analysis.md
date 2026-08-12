---
description: Workflow for analyzing Odoo source code and converting it to Flutter
---

# Odoo to Flutter Analysis Workflow

This workflow defines how to handle requests related to analyzing Odoo functionality and porting it to Flutter.

## 1. Odoo Reference Path
**Absolute Path:** `C:\Users\jihad\Desktop\odoo-19.0`
This path is the SINGLE SOURCE OF TRUTH for Odoo logic.

## 2. Analysis Pattern (Trigger: "Ask Odoo" / "اسأل أودو")
When the user asks to "Ask Odoo" about a feature (e.g., "Ask Odoo about Supplier Invoice", "كيف يحسب أودو الضريبة؟"):

1.  **Search Odoo Source**:
    *   Use `find_by_name` and `grep_search` within `C:\Users\jihad\Desktop\odoo-19.0` to locate relevant models (`.py`), views (`.xml`), and logic (`.js`).
    *   *Keywords to look for:* Model definitions, `def action_`, `<field name=...>`, `depends`, `compute`.

2.  **Analyze & Summarize (Mental Sandbox)**:
    *   Do NOT generate Flutter code yet.
    *   Read the Odoo code to understand:
        *   **Data Model**: Fields, types, relationships (One2many, Many2one).
        *   **Business Logic**: Compute methods, `onchange` events, button actions.
        *   **UI Structure**: Grouping, tabs, tree views vs form views.
    *   **Output**: Provide a comprehensive summary in Arabic/English explaining *exactly* how Odoo handles this feature. Use technical terms (e.g., "Odoo uses a computed field `amount_total` dependent on `tax_ids`").

3.  **Validation**:
    *   Ask the user: "This is how Odoo does it [Summary]. Do you want to implement this in Flutter now?"

## 3. Implementation Pattern (Trigger: "Create Flutter" / "انشئ فلتر")
When the user confirms "Create Flutter" or "Implement this":

1.  **Recall Design**: Use the internal understanding from the Analysis step.
2.  **Flutter Translation**:
    *   **Models**: Create Dart models matching Odoo's schema structure (adapted for local SQLite/Provider).
    *   **Logic**: Port Python `def` logic to Dart Service methods.
    *   **UI**: Map Odoo XML views to Flutter Widgets (`Form` -> `Column/ListView`, `Tree` -> `DataTable/ListView`, `Notebook` -> `TabBar`).
    *   **Architecture**: Follow the project's Clean Architecture standards (Provider, Service, Screen).

## Example Interaction
**User:** "اسأل أودو كيف يعمل زر 'Confirm Vote'؟"
**AI:** *Searches Odoo code...* "في أودو، زر 'Confirm Vote' يستدعي الدالة `action_confirm` التي تقوم بتغيير الحالة `state` من 'draft' إلى 'posted' وتنشئ قيود اليومية. هل تريد تطبيق هذا المنطق في تطبيقنا؟"
**User:** "نعم، انشئ فلتر."
**AI:** *Generates Flutter code implementing `action_confirm` logic in Dart.*
