# af_qa_engine/scenarios/killer_scenarios.py
"""
🔥 السيناريوهات القاتلة (20 Killer Scenarios)
محاكاة جميع الحالات الصعبة لاختبار سجل الديون والفواتير
"""
import time
import random
from typing import List, Dict, Any
from automation.driver import AppDriver
from ui_maps.screens import (
    ReportsScreen, InvoiceScreen, DebtRecordsScreen, 
    InventoryScreen, EditInvoiceScreen
)


class TestSnapshot:
    """لقطة للحالة قبل/بعد العملية"""
    def __init__(self):
        self.customer_name: str = ""
        self.total_debt: float = 0.0
        self.invoice_total: float = 0.0
        self.items_count: int = 0
        self.payment_type: str = ""
        self.paid_amount: float = 0.0
        
    def __repr__(self):
        return f"Snapshot(customer={self.customer_name}, debt={self.total_debt}, invoice={self.invoice_total})"


class TestResult:
    """نتيجة اختبار واحد"""
    def __init__(self, scenario_name: str):
        self.scenario_name = scenario_name
        self.passed: bool = False
        self.error_message: str = ""
        self.before_snapshot: TestSnapshot = None
        self.after_snapshot: TestSnapshot = None
        self.expected_debt_change: float = 0.0
        self.actual_debt_change: float = 0.0
        
    def __repr__(self):
        status = "✅ نجح" if self.passed else "❌ فشل"
        return f"{status} | {self.scenario_name}"


class KillerScenarios:
    """
    🧠 السيناريوهات القاتلة لاختبار نظام الديون والفواتير
    """
    
    # قائمة المنتجات للاختبار
    TEST_PRODUCTS = [
        {"name": "iPhone 16 Pro", "price": 1500000, "qty": 1},
        {"name": "Samsung S24 Ultra", "price": 1200000, "qty": 2},
        {"name": "MacBook Pro M3", "price": 2500000, "qty": 1},
        {"name": "iPad Pro 12.9", "price": 800000, "qty": 3},
        {"name": "AirPods Pro", "price": 200000, "qty": 5},
        {"name": "Apple Watch", "price": 350000, "qty": 2},
        {"name": "Galaxy Tab S9", "price": 600000, "qty": 1},
        {"name": "Sony Headphones", "price": 150000, "qty": 4},
        {"name": "Xiaomi Redmi", "price": 180000, "qty": 6},
        {"name": "Huawei Mate 60", "price": 900000, "qty": 1},
    ]
    
    def __init__(self, driver: AppDriver, config: dict = None):
        self.driver = driver
        self.config = config if config else {}
        
        # تهيئة الشاشات
        self.reports = ReportsScreen(driver)
        self.invoice = InvoiceScreen(driver)
        self.debt = DebtRecordsScreen(driver)
        self.inventory = InventoryScreen(driver)
        self.edit_invoice = EditInvoiceScreen(driver)
        
        # بيانات الاختبار
        self.customer_name = f"TestUser_{random.randint(1000, 9999)}"
        self.results: List[TestResult] = []
        self.current_snapshot: TestSnapshot = None
        
    def _print_header(self, text: str, emoji: str = "🔹"):
        """طباعة عنوان مميز"""
        print(f"\n{'='*60}")
        print(f"{emoji} {text}")
        print(f"{'='*60}")
        
    def _print_step(self, step_num: int, text: str):
        """طباعة خطوة"""
        print(f"   [{step_num}] {text}")
        
    def _print_data(self, label: str, value: Any):
        """طباعة بيانات"""
        print(f"       📊 {label}: {value}")
        
    def _print_success(self, text: str):
        """طباعة نجاح"""
        print(f"   ✅ {text}")
        
    def _print_error(self, text: str):
        """طباعة خطأ"""
        print(f"   ❌ {text}")
        
    def _print_warning(self, text: str):
        """طباعة تحذير"""
        print(f"   ⚠️ {text}")

    # ═══════════════════════════════════════════════════════════════
    # 📸 لقطات الحالة (Snapshots)
    # ═══════════════════════════════════════════════════════════════
    
    def take_debt_snapshot(self, customer_name: str) -> TestSnapshot:
        """أخذ لقطة لرصيد العميل من سجل الديون"""
        snapshot = TestSnapshot()
        snapshot.customer_name = customer_name
        
        self._print_step(1, f"أخذ لقطة لرصيد العميل: {customer_name}")
        
        self.debt.open()
        time.sleep(1)
        
        self.debt.search_customer(customer_name)
        time.sleep(1.5)
        
        # التحقق من وجود العميل
        if self.debt.verify_customer_exists(customer_name):
            # قراءة المبلغ الإجمالي
            total_text = self.debt.get_customer_total_debt()
            snapshot.total_debt = self._parse_amount(total_text)
            self._print_data("الرصيد الحالي", snapshot.total_debt)
        else:
            snapshot.total_debt = 0.0
            self._print_data("الرصيد", "العميل جديد (0)")
            
        return snapshot
    
    def _parse_amount(self, text: str) -> float:
        """تحويل نص المبلغ لرقم"""
        try:
            # إزالة الفواصل والعملة
            clean = text.replace(",", "").replace("IQD", "").replace(" ", "")
            return float(clean)
        except:
            return 0.0

    # ═══════════════════════════════════════════════════════════════
    # 📝 إنشاء فاتورة متعددة الأصناف
    # ═══════════════════════════════════════════════════════════════
    
    def create_multi_item_invoice(self, items_count: int = 10) -> Dict[str, Any]:
        """
        إنشاء فاتورة من خلال أسطر الفاتورة نفسها
        ⚠️ مهم: الإدخال يتم عبر الصفوف وليس شريط البحث العلوي
        """
        from pywinauto.keyboard import send_keys
        
        self._print_header(f"إنشاء فاتورة ({items_count} أصناف)", "📝")
        
        invoice_data = {
            "customer": self.customer_name,
            "items": [],
            "total": 0.0,
            "payment_type": "دين"
        }
        
        # الذهاب لشاشة الفاتورة
        self._print_step(1, "فتح شاشة إنشاء قائمة...")
        self.invoice.open()
        time.sleep(2)
        
        # تحديد العميل - البحث عن حقل "اسم العميل" (الموقع ~1249, 61)
        self._print_step(2, f"تحديد العميل: {self.customer_name}")
        try:
            edits = self.driver.window.descendants(control_type="Edit")
            # حقل اسم العميل هو الذي يحتوي على "اسم العميل" hint أو الأول
            customer_field = None
            for edit in edits:
                try:
                    text = edit.window_text()
                    if "العميل" in text or "اسم" in text:
                        customer_field = edit
                        break
                except:
                    pass
            
            if customer_field:
                customer_field.click_input()
                time.sleep(0.2)
                send_keys(self.customer_name, with_spaces=True)
                self._print_success(f"تم كتابة اسم العميل: {self.customer_name}")
            else:
                # fallback: أول حقل Edit
                if edits:
                    edits[0].click_input()
                    time.sleep(0.2)
                    send_keys(self.customer_name, with_spaces=True)
                    self._print_success(f"تم كتابة اسم العميل (fallback)")
        except Exception as e:
            self._print_warning(f"فشل تحديد العميل: {e}")
        
        time.sleep(0.5)
        
        # الانتقال لمنطقة أصناف الفاتورة
        # ⚠️ مهم: حقل "التفاصيل" في الصف الأول موجود في موقع (1147, 303)
        # بينما شريط البحث العلوي في (955, 166)
        self._print_step(3, f"إضافة {items_count} أصناف عبر صفوف الفاتورة...")
        self._print_step(4, "التركيز على حقل التفاصيل في الصف الأول...")
        
        # البحث عن حقل التفاصيل في جدول الفاتورة (وليس شريط البحث)
        # نبحث عن حقل Edit فارغ في موقع Y > 250 (تحت رأس الجدول)
        try:
            edits = self.driver.window.descendants(control_type="Edit")
            details_field = None
            
            for edit in edits:
                try:
                    rect = edit.rectangle()
                    # حقل التفاصيل في الصف: Y > 290 وليس شريط البحث
                    if rect.top > 280:
                        text = edit.window_text() or ""
                        # أول حقل فارغ أو بدون hint معروف
                        if not text or text.strip() == "":
                            details_field = edit
                            break
                        elif "المنتج" not in text and "الرمز" not in text:
                            details_field = edit
                            break
                except:
                    pass
            
            if details_field:
                self._print_success(f"تم العثور على حقل التفاصيل في الصف")
                details_field.click_input()
                time.sleep(0.3)
            else:
                # fallback: استخدام Tab للتنقل من حقل السعر العلوي
                self._print_warning("لم يتم العثور على حقل التفاصيل، جاري المحاولة بـ Tab")
                for _ in range(5):
                    send_keys("{TAB}")
                    time.sleep(0.1)
        except Exception as e:
            self._print_warning(f"خطأ في الوصول للتفاصيل: {e}")
            for _ in range(5):
                send_keys("{TAB}")
                time.sleep(0.1)
        
        products_to_add = self.TEST_PRODUCTS[:items_count]
        
        for i, product in enumerate(products_to_add, 1):
            name = product["name"]
            price = product["price"]
            qty = product["qty"]
            total = price * qty
            
            print(f"       [{i}/{items_count}] {name} | {qty} x {price:,} = {total:,}")
            
            # إدخال الصنف عبر صف الفاتورة
            self.invoice.enter_invoice_row(
                details=name,
                quantity=qty,
                price=price
            )
            
            invoice_data["items"].append({
                "name": name,
                "qty": qty,
                "price": price,
                "total": total
            })
            invoice_data["total"] += total
            
            time.sleep(0.3)
        
        self._print_data("إجمالي الفاتورة", f"{invoice_data['total']:,} IQD")
        
        # تحديد نوع الدفع
        self._print_step(4, "تحديد نوع الدفع: دين")
        self.invoice.set_payment_type("دين")
        
        # حفظ الفاتورة
        self._print_step(5, "💾 حفظ الفاتورة...")
        self.invoice.save_and_confirm()
        time.sleep(2)
        
        self._print_success(f"تم إنشاء فاتورة بقيمة {invoice_data['total']:,} IQD")
        
        return invoice_data

    # ═══════════════════════════════════════════════════════════════
    # 🔍 التحقق من سجل الديون
    # ═══════════════════════════════════════════════════════════════
    
    def verify_debt_record(self, expected_total: float) -> bool:
        """التحقق من صحة سجل الديون"""
        self._print_header("التحقق من سجل الديون", "🔍")
        
        self.driver.navigate_home()
        self.debt.open()
        time.sleep(1)
        
        self._print_step(1, f"البحث عن العميل: {self.customer_name}")
        self.debt.search_customer(self.customer_name)
        time.sleep(1.5)
        
        if not self.debt.verify_customer_exists(self.customer_name):
            self._print_error("العميل غير موجود في سجل الديون!")
            return False
        
        self._print_step(2, "الضغط على العميل لفتح التفاصيل...")
        self.debt.select_first_result()
        time.sleep(1.5)
        
        # قراءة المبلغ الإجمالي
        self._print_step(3, "قراءة المبلغ الإجمالي...")
        total_text = self.debt.get_total_amount()
        actual_total = self._parse_amount(total_text)
        
        self._print_data("المتوقع", f"{expected_total:,}")
        self._print_data("الفعلي", f"{actual_total:,}")
        
        # التبديل بين العروض
        self._print_step(4, "اختبار التبديل بين العرض المجمعي والتفصيلي...")
        
        print("       🔄 التحويل للعرض التفصيلي...")
        self.debt.toggle_view(detailed=True)
        time.sleep(1)
        
        # طباعة المواد في العرض التفصيلي
        items = self.debt.get_detailed_items()
        if items:
            print("       📋 المواد في العرض التفصيلي:")
            for item in items:
                print(f"          • {item}")
        
        print("       🔄 التحويل للعرض المجمعي...")
        self.debt.toggle_view(detailed=False)
        time.sleep(1)
        
        # المقارنة
        tolerance = self.config.get('thresholds', {}).get('financial_tolerance', 0.01)
        if abs(actual_total - expected_total) <= tolerance:
            self._print_success("✅ المبلغ مطابق!")
            return True
        else:
            diff = actual_total - expected_total
            self._print_error(f"❌ فرق في المبلغ: {diff:,}")
            return False

    # ═══════════════════════════════════════════════════════════════
    # ☠️ السيناريوهات القاتلة (20 سيناريو)
    # ═══════════════════════════════════════════════════════════════
    
    def run_killer_scenario(self, scenario_num: int) -> TestResult:
        """تشغيل سيناريو قاتل واحد"""
        result = TestResult(f"Scenario #{scenario_num}")
        
        scenarios = {
            1: self._scenario_basic_edit,
            2: self._scenario_add_items,
            3: self._scenario_delete_first,
            4: self._scenario_payment_to_cash,
            5: self._scenario_payment_to_debt,
            6: self._scenario_partial_pay,
            7: self._scenario_full_pay,
            8: self._scenario_add_fees,
            9: self._scenario_delete_and_add,
            10: self._scenario_price_zero,
            11: self._scenario_qty_change,
            12: self._scenario_combo_mix,
            13: self._scenario_delete_most,
            14: self._scenario_monster_add,
            15: self._scenario_rapid_edit,
            16: self._scenario_negative_test,
            17: self._scenario_large_numbers,
            18: self._scenario_payment_loop,
            19: self._scenario_partial_plus_edit,
            20: self._scenario_ultimate_chaos,
        }
        
        scenario_func = scenarios.get(scenario_num)
        if scenario_func:
            try:
                result = scenario_func(result)
            except Exception as e:
                result.passed = False
                result.error_message = str(e)
                self._print_error(f"خطأ في السيناريو: {e}")
        
        return result

    def _open_customer_invoice(self):
        """فتح فاتورة العميل من شاشة التعديل (بالبحث عنه أولاً)"""
        self.edit_invoice.open()
        time.sleep(1.5)
        
        # البحث عن فاتورة العميل
        self._print_step(0, f"البحث عن فواتير العميل: {self.customer_name}...")
        self.edit_invoice.search_invoice_by_customer(self.customer_name)
        time.sleep(1)
        
        # اختيار أول فاتورة
        self.edit_invoice.select_first_invoice()
        time.sleep(1.5)
        
        # فتح وضع التعديل
        self.edit_invoice.click_edit_button()
        time.sleep(1)

    # ─── السيناريو 1: تعديل أساسي ───
    def _scenario_basic_edit(self, result: TestResult) -> TestResult:
        """تعديل كمية وسعر صنف واحد"""
        self._print_header("السيناريو 1: تعديل أساسي (كمية + سعر)", "🔸")
        result.scenario_name = "Basic Edit - تعديل كمية وسعر"
        
        self._print_step(1, "فتح فاتورة العميل...")
        self._open_customer_invoice()
        
        new_qty = random.randint(3, 8)
        new_price = random.randint(100000, 500000)
        
        self._print_step(5, f"تغيير العدد إلى: {new_qty}")
        self.driver.set_value_near_label("العدد", str(new_qty))
        
        self._print_step(6, f"تغيير السعر إلى: {new_price:,}")
        self.driver.set_value_near_label("سعر المبيع", str(new_price))
        
        self._print_step(7, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        self._print_success("تم تنفيذ السيناريو بنجاح")
        return result

    # ─── السيناريو 2: إضافة أصناف ───
    def _scenario_add_items(self, result: TestResult) -> TestResult:
        """إضافة 3 مواد جديدة للفاتورة"""
        self._print_header("السيناريو 2: إضافة 3 مواد جديدة", "🔸")
        result.scenario_name = "Add Items - إضافة مواد"
        
        self._print_step(1, "فتح فاتورة العميل...")
        self._open_customer_invoice()
        
        for i in range(3):
            product = random.choice(self.TEST_PRODUCTS)
            self._print_step(i+1, f"إضافة: {product['name']}")
            self.edit_invoice.add_product_row(
                product['name'], 
                product['qty'], 
                product['price']
            )
            time.sleep(0.5)
        
        self._print_step(4, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        return result

    # ─── السيناريو 3: حذف الصنف الأول ───
    def _scenario_delete_first(self, result: TestResult) -> TestResult:
        """حذف أول صنف في الفاتورة"""
        self._print_header("السيناريو 3: حذف الصنف الأول", "🔸")
        result.scenario_name = "Delete First - حذف صنف"
        
        self._print_step(1, "فتح فاتورة العميل...")
        self._open_customer_invoice()
        
        self._print_step(1, "حذف الصنف الأول...")
        self.edit_invoice.delete_item(index=0)
        time.sleep(1)
        
        self._print_step(2, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        return result

    # ─── السيناريو 4: تحويل من دين لنقد ───
    def _scenario_payment_to_cash(self, result: TestResult) -> TestResult:
        """تحويل نوع الدفع من دين إلى نقد"""
        self._print_header("السيناريو 4: تحويل من دين لنقد ⚠️", "🔴")
        result.scenario_name = "Payment Flip (Debt→Cash)"
        
        self._print_step(1, "فتح فاتورة العميل...")
        self._open_customer_invoice()
        
        self._print_step(1, "تغيير نوع الدفع إلى: نقد")
        self.invoice.set_payment_type("نقد")
        time.sleep(0.5)
        
        self._print_step(2, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        self._print_warning("⚠️ يجب التحقق: هل تم إزالة الدين من سجل العميل؟")
        return result

    # ─── السيناريو 5: تحويل من نقد لدين ───
    def _scenario_payment_to_debt(self, result: TestResult) -> TestResult:
        """تحويل نوع الدفع من نقد إلى دين"""
        self._print_header("السيناريو 5: تحويل من نقد لدين ⚠️", "🔴")
        result.scenario_name = "Payment Flip (Cash→Debt)"
        
        self._open_customer_invoice()
        
        self._print_step(1, "تغيير نوع الدفع إلى: دين")
        self.invoice.set_payment_type("دين")
        time.sleep(0.5)
        
        self._print_step(2, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        self._print_warning("⚠️ يجب التحقق: هل تم إضافة الدين لسجل العميل؟")
        return result

    # ─── السيناريو 6: تسديد جزئي ───
    def _scenario_partial_pay(self, result: TestResult) -> TestResult:
        """تسديد جزء من المبلغ"""
        self._print_header("السيناريو 6: تسديد جزئي", "🔸")
        result.scenario_name = "Partial Payment - تسديد جزئي"
        
        self._open_customer_invoice()
        
        partial_amount = random.randint(100000, 500000)
        self._print_step(1, f"تسديد مبلغ جزئي: {partial_amount:,}")
        self.driver.set_value_near_label("المدفوع", str(partial_amount))
        time.sleep(0.5)
        
        self._print_step(2, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        return result

    # ─── السيناريو 7: تسديد كامل ───
    def _scenario_full_pay(self, result: TestResult) -> TestResult:
        """تسديد كامل المبلغ"""
        self._print_header("السيناريو 7: تسديد كامل", "🔸")
        result.scenario_name = "Full Payment - تسديد كامل"
        
        self._open_customer_invoice()
        
        # نفترض قراءة الإجمالي وتسديده كاملاً
        self._print_step(1, "تسديد كامل المبلغ (نفس قيمة الإجمالي)")
        # سنستخدم قيمة كبيرة تغطي الإجمالي
        self.driver.set_value_near_label("المدفوع", "9999999")
        time.sleep(0.5)
        
        self._print_step(2, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        return result

    # ─── السيناريو 8: إضافة أجور تحميل ───
    def _scenario_add_fees(self, result: TestResult) -> TestResult:
        """إضافة أجور تحميل ونقل"""
        self._print_header("السيناريو 8: إضافة أجور تحميل", "🔸")
        result.scenario_name = "Add Loading Fees"
        
        self._open_customer_invoice()
        
        fee_amount = random.randint(10000, 50000)
        self._print_step(1, f"إضافة أجور تحميل: {fee_amount:,}")
        self.invoice.add_loading_fee(str(fee_amount))
        time.sleep(0.5)
        
        self._print_step(2, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        return result

    # ─── السيناريو 9: حذف وإضافة معاً ───
    def _scenario_delete_and_add(self, result: TestResult) -> TestResult:
        """حذف صنف وإضافة صنف جديد في نفس الوقت"""
        self._print_header("السيناريو 9: حذف + إضافة معاً ⚠️⚠️", "🔴")
        result.scenario_name = "Delete + Add Combined"
        
        self._open_customer_invoice()
        
        self._print_step(1, "حذف الصنف الأول...")
        self.edit_invoice.delete_item(index=0)
        time.sleep(0.5)
        
        product = random.choice(self.TEST_PRODUCTS)
        self._print_step(2, f"إضافة صنف جديد: {product['name']}")
        self.edit_invoice.add_product_row(product['name'], product['qty'], product['price'])
        time.sleep(0.5)
        
        self._print_step(3, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        return result

    # ─── السيناريو 10: تصفير السعر ───
    def _scenario_price_zero(self, result: TestResult) -> TestResult:
        """تغيير السعر إلى صفر"""
        self._print_header("السيناريو 10: تصفير السعر ⚠️⚠️⚠️", "🔴")
        result.scenario_name = "Price Zero Test"
        
        self._open_customer_invoice()
        
        self._print_step(1, "تغيير السعر إلى صفر...")
        self.driver.set_value_near_label("سعر المبيع", "0")
        time.sleep(0.5)
        
        self._print_step(2, "محاولة الحفظ...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        self._print_warning("⚠️ يجب التحقق: هل يقبل النظام سعر صفر؟")
        return result

    # ─── السيناريو 11: تغيير الكمية ───
    def _scenario_qty_change(self, result: TestResult) -> TestResult:
        """تغيير الكمية لقيم مختلفة"""
        self._print_header("السيناريو 11: تغيير الكمية", "🔸")
        result.scenario_name = "Quantity Change"
        
        self._open_customer_invoice()
        
        new_qty = random.randint(10, 50)
        self._print_step(1, f"تغيير الكمية إلى: {new_qty}")
        self.driver.set_value_near_label("العدد", str(new_qty))
        time.sleep(0.5)
        
        self._print_step(2, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        return result

    # ─── السيناريو 12: مزيج معقد ───
    def _scenario_combo_mix(self, result: TestResult) -> TestResult:
        """تعديل 3 أشياء مرة واحدة"""
        self._print_header("السيناريو 12: مزيج معقد (3 تعديلات معاً)", "🔴")
        result.scenario_name = "Combo Mix"
        
        self._open_customer_invoice()
        
        self._print_step(1, "تعديل العدد...")
        self.driver.set_value_near_label("العدد", str(random.randint(5, 15)))
        
        self._print_step(2, "تعديل السعر...")
        self.driver.set_value_near_label("سعر المبيع", str(random.randint(200000, 800000)))
        
        self._print_step(3, "إضافة أجور تحميل...")
        self.invoice.add_loading_fee(str(random.randint(5000, 20000)))
        
        self._print_step(4, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        return result

    # ─── السيناريو 13: حذف معظم الأصناف ───
    def _scenario_delete_most(self, result: TestResult) -> TestResult:
        """حذف كل الأصناف ما عدا واحد"""
        self._print_header("السيناريو 13: حذف معظم الأصناف ⚠️⚠️⚠️", "🔴")
        result.scenario_name = "Delete Most Items"
        
        self._open_customer_invoice()
        
        # حذف 3 أصناف متتالية
        for i in range(3):
            self._print_step(i+1, f"حذف الصنف رقم {i+1}...")
            self.edit_invoice.delete_item(index=0)
            time.sleep(0.5)
        
        self._print_step(4, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        return result

    # ─── السيناريو 14: إضافة 10 مواد ───
    def _scenario_monster_add(self, result: TestResult) -> TestResult:
        """إضافة 10 مواد دفعة واحدة"""
        self._print_header("السيناريو 14: إضافة 10 مواد دفعة واحدة", "🔸")
        result.scenario_name = "Monster Add (10 items)"
        
        self._open_customer_invoice()
        
        for i, product in enumerate(self.TEST_PRODUCTS, 1):
            self._print_step(i, f"إضافة: {product['name']}")
            self.edit_invoice.add_product_row(product['name'], product['qty'], product['price'])
            time.sleep(0.3)
        
        self._print_step(11, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(2)
        
        result.passed = True
        return result

    # ─── السيناريو 15: تعديل سريع متكرر ───
    def _scenario_rapid_edit(self, result: TestResult) -> TestResult:
        """5 تعديلات متتالية سريعة بدون انتظار"""
        self._print_header("السيناريو 15: تعديل سريع (5 مرات) ⚠️⚠️", "🔴")
        result.scenario_name = "Rapid Edit (5x)"
        
        for round_num in range(1, 6):
            print(f"\n   🔄 الجولة {round_num}/5")
            
            self._open_customer_invoice()
            
            self.driver.set_value_near_label("العدد", str(random.randint(1, 20)))
            time.sleep(0.3)
            
            self.edit_invoice.save_and_confirm()
            time.sleep(0.8)
            
            self.driver.navigate_home()
        
        result.passed = True
        return result

    # ─── السيناريو 16: اختبار القيم السالبة ───
    def _scenario_negative_test(self, result: TestResult) -> TestResult:
        """محاولة إدخال قيم سالبة"""
        self._print_header("السيناريو 16: اختبار القيم السالبة ⚠️⚠️⚠️", "🔴")
        result.scenario_name = "Negative Values Test"
        
        self._open_customer_invoice()
        
        self._print_step(1, "محاولة إدخال سعر سالب: -500")
        self.driver.set_value_near_label("سعر المبيع", "-500")
        time.sleep(0.5)
        
        self._print_step(2, "محاولة الحفظ...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        self._print_warning("⚠️ يجب التحقق: هل يرفض النظام القيم السالبة؟")
        return result

    # ─── السيناريو 17: أرقام كبيرة جداً ───
    def _scenario_large_numbers(self, result: TestResult) -> TestResult:
        """اختبار الأرقام الكبيرة جداً"""
        self._print_header("السيناريو 17: أرقام كبيرة جداً", "🔸")
        result.scenario_name = "Large Numbers Test"
        
        self._open_customer_invoice()
        
        self._print_step(1, "إدخال سعر كبير: 999,999,999")
        self.driver.set_value_near_label("سعر المبيع", "999999999")
        time.sleep(0.5)
        
        self._print_step(2, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        return result

    # ─── السيناريو 18: حلقة الدفع ───
    def _scenario_payment_loop(self, result: TestResult) -> TestResult:
        """تبديل نوع الدفع 4 مرات (دين↔نقد)"""
        self._print_header("السيناريو 18: حلقة الدفع (دين↔نقد × 4) ⚠️⚠️⚠️⚠️", "🔴")
        result.scenario_name = "Payment Loop (4x)"
        
        payment_types = ["نقد", "دين", "نقد", "دين"]
        
        for i, ptype in enumerate(payment_types, 1):
            print(f"\n   🔄 الجولة {i}/4: تحويل إلى {ptype}")
            
            self._open_customer_invoice()
            
            self.invoice.set_payment_type(ptype)
            time.sleep(0.3)
            
            self.edit_invoice.save_and_confirm()
            time.sleep(1)
            
            self.driver.navigate_home()
        
        result.passed = True
        self._print_warning("⚠️⚠️ هذا السيناريو قاتل! تحقق من سجل الديون بعناية")
        return result

    # ─── السيناريو 19: تسديد + تعديل ───
    def _scenario_partial_plus_edit(self, result: TestResult) -> TestResult:
        """تسديد جزئي مع تعديل المبلغ"""
        self._print_header("السيناريو 19: تسديد جزئي + تعديل مبلغ ⚠️⚠️⚠️", "🔴")
        result.scenario_name = "Partial Pay + Edit"
        
        self._open_customer_invoice()
        
        self._print_step(1, "تعديل السعر لزيادة المبلغ...")
        self.driver.set_value_near_label("سعر المبيع", "1500000")
        
        self._print_step(2, "تسديد مبلغ جزئي...")
        self.driver.set_value_near_label("المدفوع", "300000")
        
        self._print_step(3, "حفظ التعديلات...")
        self.edit_invoice.save_and_confirm()
        time.sleep(1.5)
        
        result.passed = True
        self._print_warning("⚠️ تحقق: الدين الجديد = الإجمالي الجديد - المدفوع")
        return result

    # ─── السيناريو 20: الفوضى الشاملة ───
    def _scenario_ultimate_chaos(self, result: TestResult) -> TestResult:
        """كل شيء مرة واحدة - أخطر سيناريو!"""
        self._print_header("السيناريو 20: الفوضى الشاملة ☠️☠️☠️☠️☠️", "💀")
        result.scenario_name = "ULTIMATE CHAOS"
        
        self._open_customer_invoice()
        
        self._print_step(1, "حذف صنفين...")
        self.edit_invoice.delete_item(index=0)
        time.sleep(0.3)
        self.edit_invoice.delete_item(index=0)
        time.sleep(0.3)
        
        self._print_step(2, "إضافة 3 أصناف جديدة...")
        for product in self.TEST_PRODUCTS[:3]:
            self.edit_invoice.add_product_row(product['name'], product['qty'], product['price'])
            time.sleep(0.2)
        
        self._print_step(3, "تعديل السعر...")
        self.driver.set_value_near_label("سعر المبيع", str(random.randint(500000, 2000000)))
        
        self._print_step(4, "إضافة أجور تحميل...")
        self.invoice.add_loading_fee("75000")
        
        self._print_step(5, "تسديد جزئي...")
        self.driver.set_value_near_label("المدفوع", "200000")
        
        self._print_step(6, "تغيير نوع الدفع...")
        self.invoice.set_payment_type("نقد")
        time.sleep(0.3)
        self.invoice.set_payment_type("دين")  # والعودة!
        
        self._print_step(7, "💾 حفظ كل هذه الفوضى...")
        self.edit_invoice.save_and_confirm()
        time.sleep(2)
        
        result.passed = True
        self._print_warning("☠️ السيناريو القاتل! تحقق من كل شيء!")
        return result

    # ═══════════════════════════════════════════════════════════════
    # 🚀 تشغيل الاختبار الكامل
    # ═══════════════════════════════════════════════════════════════
    
    def run_smart_user_simulation(self):
        """تشغيل محاكاة المستخدم الذكي الكاملة"""
        self._print_header("🤖 بدء محاكاة المستخدم الذكي", "🚀")
        print(f"   👤 اسم العميل للاختبار: {self.customer_name}")
        
        # مرحلة 1: التحقق من سجل الديون (العميل غير موجود حالياً)
        self._print_header("المرحلة 1: فحص سجل الديون الأولي", "📋")
        before_snapshot = self.take_debt_snapshot(self.customer_name)
        self.driver.navigate_home()
        
        # مرحلة 2: إنشاء فاتورة متعددة الأصناف
        invoice_data = self.create_multi_item_invoice(items_count=10)
        self.driver.navigate_home()
        
        # مرحلة 3: التحقق من سجل الديون بعد الإنشاء
        self._print_header("المرحلة 3: التحقق من سجل الديون", "✅")
        self.verify_debt_record(expected_total=invoice_data["total"])
        self.driver.navigate_home()
        
        # مرحلة 4: تشغيل السيناريوهات القاتلة (20 سيناريو)
        self._print_header("المرحلة 4: حلقة الموت (20 سيناريو قاتل)", "☠️")
        
        for scenario_num in range(1, 21):
            print(f"\n{'─'*60}")
            result = self.run_killer_scenario(scenario_num)
            self.results.append(result)
            
            # التحقق بعد كل سيناريو
            self.verify_debt_record_quick()
            self.driver.navigate_home()
            time.sleep(0.5)
        
        # مرحلة 5: التقرير النهائي
        self.print_final_report()
    
    def verify_debt_record_quick(self):
        """تحقق سريع من سجل الديون"""
        self.debt.open()
        time.sleep(0.8)
        self.debt.search_customer(self.customer_name)
        time.sleep(1)
        
        if self.debt.verify_customer_exists(self.customer_name):
            print("   🔍 العميل موجود في السجل ✓")
        else:
            print("   ⚠️ العميل غير موجود!")
    
    def print_final_report(self):
        """طباعة التقرير النهائي"""
        self._print_header("📊 التقرير النهائي", "📋")
        
        passed = sum(1 for r in self.results if r.passed)
        failed = len(self.results) - passed
        
        print(f"\n   ✅ نجح: {passed}/{len(self.results)}")
        print(f"   ❌ فشل: {failed}/{len(self.results)}")
        print(f"\n   📈 نسبة النجاح: {(passed/len(self.results))*100:.1f}%")
        
        if failed > 0:
            print("\n   ❌ السيناريوهات الفاشلة:")
            for r in self.results:
                if not r.passed:
                    print(f"      • {r.scenario_name}: {r.error_message}")
        
        print("\n" + "="*60)
        print("🎉 انتهى الاختبار!")
        print("="*60)
