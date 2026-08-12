# af_qa_engine/ui_maps/screens.py
"""
🗺️ خريطة الشاشات (Screen Models)
تمثيل لكل شاشة في التطبيق مع دوال التفاعل
"""
import time
from typing import List, Optional
from automation.driver import AppDriver


class BaseScreen:
    """الشاشة الأساسية"""
    def __init__(self, driver: AppDriver):
        self.driver = driver

    def _log(self, message: str):
        """طباعة رسالة مع تنسيق"""
        print(f"   📱 {message}")


class ReportsScreen(BaseScreen):
    """
    نموذج شاشة التقارير (Reports Screen Model).
    يوفر واجهة للتعامل مع التقارير اليومية والشهرية والسنوية.
    """
    def open(self):
        """فتح شاشة التقارير وإدخال كلمة المرور تلقائياً"""
        self._log("الانتقال إلى شاشة التقارير...")
        self.driver.go_to_reports()
        # محاولة تجاوز حماية كلمة المرور
        try:
            # كلمة السر الافتراضية
            self.driver.set_text("كلمة السر", "2001")
            self.driver.click("تأكيد")
            self.driver._sleep()
        except:
            pass

    def open_daily_report(self):
        """فتح تقرير اليوم (Sales & Profit Today)"""
        self._log("فتح تقرير اليوم...")
        btn = self.driver.find_text_element("تقرير اليوم")
        if btn:
            btn.click_input()
        else:
            print("   ⚠️ لم يتم العثور على زر 'تقرير اليوم'")
            
    def verify_report_loaded(self) -> bool:
        """التحقق من تحميل بيانات التقرير"""
        time.sleep(1)
        texts = self.driver.get_all_texts()
        if any("مبيعات" in t for t in texts):
            self._log("✅ تم تحميل التقرير بنجاح.")
            return True
        return False


class DebtRecordsScreen(BaseScreen):
    """
    نموذج شاشة سجل الديون (Debt Records Model).
    يتيح البحث عن العملاء، عرض التفاصيل، وإدارة المعاملات.
    """
    
    def open(self):
        """فتح شاشة سجل الديون"""
        self._log("الانتقال إلى سجل الديون...")
        try:
            btn = self.driver.window.child_window(title="سجل الديون", control_type="Button")
            if btn.exists():
                btn.click_input()
            else:
                self.driver.go_to_debt_records()
        except:
            self.driver.go_to_debt_records()
        time.sleep(1.5)

    def search_customer(self, name: str):
        """البحث عن عميل بالاسم"""
        self._log(f"البحث عن العميل '{name}'...")
        self.driver.set_text("ابحث عن عميل...", name, is_search=True)
        time.sleep(1.5)  # انتظار الفلترة

    def verify_customer_exists(self, name: str) -> bool:
        """التحقق هل العميل موجود في نتائج البحث"""
        # 1. التحقق من حالة "لا يوجد عملاء"
        if self.driver.find_text_element("لا يوجد عملاء"):
            self._log("النتيجة: القائمة فارغة (لا يوجد عملاء).")
            return False
        
        # 2. التحقق من وجود اسم العميل في العناصر الظاهرة
        if self.driver.find_text_element(name):
            return True
             
        return False

    def select_first_result(self) -> bool:
        """اختيار أول عميل في نتائج البحث بالضغط عليه مباشرة"""
        self._log("اختيار أول نتيجة...")
        
        # التحقق من وجود "لا يوجد عملاء"
        if self.driver.find_text_element("لا يوجد عملاء"):
            print("   ❌ لا يوجد نتائج (قائمة فارغة).")
            return False
        
        # محاولة الضغط على أول عميل ظاهر
        try:
            # البحث عن Group أو ListItem في القائمة
            items = self.driver.window.descendants(control_type="Group")
            for item in items:
                try:
                    rect = item.rectangle()
                    # نريد عناصر في منطقة القائمة (Y > 200 عادة)
                    if rect.top > 200 and rect.height > 30 and rect.height < 150:
                        text = item.window_text()
                        # تجنب الأزرار والعناوين
                        if text and len(text) > 3 and text not in ['رجوع', 'Minimize', 'Maximize', 'Close']:
                            print(f"   🖱️ الضغط على: {text[:30]}...")
                            item.click_input()
                            time.sleep(1)
                            return True
                except:
                    pass
        except Exception as e:
            print(f"   ⚠️ فشل البحث عن العملاء: {e}")
            
        # fallback: استخدام TAB و ENTER
        self.driver.window.type_keys("{TAB}")
        self.driver.window.type_keys("{ENTER}")
        time.sleep(1)
        return True

    def get_customer_total_debt(self) -> str:
        """قراءة المبلغ الإجمالي للعميل من القائمة"""
        try:
            # البحث عن عنصر يحتوي على "IQD" أو أرقام
            texts = self.driver.get_all_texts()
            for text in texts:
                if "IQD" in text or any(c.isdigit() for c in text):
                    # تصفية النصوص التي تبدو كمبالغ
                    if len(text) < 30 and any(c.isdigit() for c in text):
                        return text
        except:
            pass
        return "0"

    def get_total_amount(self) -> str:
        """قراءة المبلغ الإجمالي من شاشة تفاصيل العميل"""
        try:
            # البحث عن عنصر يحتوي على المجموع الكلي
            # عادة يكون قريباً من "المبلغ الإجمالي" أو "المجموع"
            label = self.driver.find_text_element("المبلغ الإجمالي")
            if not label:
                label = self.driver.find_text_element("المجموع")
            
            if label:
                # البحث عن أقرب نص يحتوي على أرقام
                texts = self.driver.get_all_texts()
                for text in texts:
                    if "IQD" in text or (len(text) < 20 and any(c.isdigit() for c in text)):
                        return text
        except:
            pass
        return "0"

    def toggle_view(self, detailed: bool = True):
        """التبديل بين العرض المجمعي والتفصيلي"""
        mode = "عرض تفصيلي" if detailed else "عرض مجمعي"
        self._log(f"التبديل إلى {mode}...")
        self.driver.click(mode)
        time.sleep(0.5)

    def get_detailed_items(self) -> List[str]:
        """قراءة المواد من العرض التفصيلي"""
        items = []
        try:
            texts = self.driver.get_all_texts()
            # تصفية النصوص التي تبدو كأسماء منتجات
            for text in texts:
                # استبعاد العناوين والأزرار المعروفة
                if text not in ["عرض تفصيلي", "عرض مجمعي", "سجل الديون", "رجوع"]:
                    if len(text) > 3 and len(text) < 50:
                        items.append(text)
        except:
            pass
        return items[:20]  # حد أقصى 20 عنصر

    def open_manual_transaction(self):
        """فتح نافذة إضافة معاملة يدوية"""
        self._log("فتح نافذة معاملة يدوية...")
        self.driver.click("معاملة يدوية")


class InvoiceScreen(BaseScreen):
    """
    نموذج شاشة إنشاء الفاتورة (Invoice Creation Model).
    يحاكي عملية الكاشير: اختيار عميل، إضافة منتجات، الدفع.
    """
    
    def open(self):
        """فتح شاشة إنشاء الفاتورة"""
        self._log("الانتقال إلى إنشاء قائمة...")
        self.driver.go_to_create_invoice()
        time.sleep(2)

    def set_customer(self, name: str):
        """تحديد العميل للفاتورة"""
        self._log(f"تحديد العميل: {name}")
        try:
            self.driver.set_text("اسم العميل", name)
        except:
            self.driver.set_value_near_label("اسم العميل", name)

    def enter_invoice_row(self, details: str, quantity: int, price: float):
        """
        إدخال صف واحد في الفاتورة عبر الأسطر مباشرة
        (وليس من شريط البحث العلوي)
        
        الخطوات (حسب تصميم التطبيق):
        1. كتابة التفاصيل (اسم المنتج) في حقل التفاصيل
        2. ENTER للانتقال للعدد (onSubmitted -> _quantityFocusNode)
        3. كتابة العدد
        4. ENTER → يفتح dropdown للوحدة → ثم ينتقل للسعر
        5. كتابة السعر
        6. ENTER للانتقال للصف التالي (onPriceSubmitted)
        """
        from pywinauto.keyboard import send_keys
        
        # 1. كتابة اسم المنتج/التفاصيل
        # نستخدم with_spaces للحفاظ على المسافات في أسماء المنتجات
        send_keys(details, with_spaces=True)
        time.sleep(0.4)
        
        # 2. ENTER للانتقال لحقل العدد
        send_keys("{ENTER}")
        time.sleep(0.3)
        
        # 3. كتابة الكمية
        send_keys(str(quantity))
        time.sleep(0.3)
        
        # 4. ENTER → يفتح dropdown للوحدة (نوع البيع) ثم ننتظر قليلاً
        send_keys("{ENTER}")
        time.sleep(0.5)  # انتظار قائمة dropdown
        
        # 5. ENTER مرة أخرى لتجاوز dropdown والانتقال للسعر
        # أو قد يكون قد انتقل تلقائياً للسعر
        # نكتب السعر مباشرة
        send_keys(str(int(price)))
        time.sleep(0.3)
        
        # 6. ENTER للانتقال للصف التالي
        send_keys("{ENTER}")
        time.sleep(0.5)

    def add_product(self, product_name: str, price: float = None, quantity: int = 1):
        """
        إضافة منتج للفاتورة باستخدام شريط البحث العلوي
        (الطريقة القديمة - للتوافق)
        """
        self._log(f"إضافة منتج: {product_name} | سعر: {price} | كمية: {quantity}")
        
        # البحث عن المنتج واختياره
        self.driver.set_text("أدخل اسم المنتج أو الرمز...", product_name, is_search=True)
        time.sleep(0.5)
        
        # اختيار النتيجة الأولى
        self.driver.window.type_keys("{ENTER}")
        time.sleep(0.5)

        # ضبط الكمية
        if quantity and str(quantity) != "1":
            self.driver.set_value_near_label("الكمية", str(quantity))
        
        # ضبط السعر
        if price:
            self.driver.set_value_near_label("السعر", str(price))
            self.driver.window.type_keys("{ENTER}")
        else:
            self.driver.window.type_keys("{ENTER}")
            
        time.sleep(0.5)

    def set_payment_type(self, type_name: str = "دين"):
        """تحديد نوع الدفع: نقد أو دين"""
        self._log(f"تحديد الدفع: {type_name}")
        self.driver.click(type_name)

    def add_loading_fee(self, amount: str):
        """إضافة أجور نقل/تحميل"""
        self._log(f"إضافة أجور نقل: {amount}")
        self.driver.set_value_near_label("أجور التحميل والنقل", amount)

    def set_discount(self, amount: str):
        """تحديد قيمة الخصم"""
        self._log(f"تحديد الخصم: {amount}")
        self.driver.set_value_near_label("الخصم", amount)

    def set_paid_amount(self, amount: str):
        """تحديد المبلغ المدفوع"""
        self._log(f"تحديد المدفوع: {amount}")
        self.driver.set_value_near_label("المدفوع", amount)

    def save_and_confirm(self):
        """حفظ الفاتورة وتأكيدها"""
        self._log("💾 حفظ الفاتورة...")
        self.driver.click("حفظ الفاتورة")
        time.sleep(1)
        
        # محاولة تأكيد الحوار إذا ظهر
        try:
            self.driver.click("نعم")
        except:
            pass
        try:
            self.driver.click("موافق")
        except:
            pass


class InventoryScreen(BaseScreen):
    """
    نموذج شاشة إدخال البضاعة (Inventory Entry).
    يستخدم لإضافة منتجات جديدة للنظام.
    """
    
    def open(self):
        """فتح شاشة إدخال البضاعة"""
        self._log("الانتقال إلى إدخال بضاعة...")
        try:
            # محاولة الوصول عبر سجل الديون
            btn_debt = self.driver.window.child_window(title="سجل الديون", control_type="Button")
            if btn_debt.exists():
                btn_debt.click_input()
            else:
                self.driver.go_to_debt_records()
             
            time.sleep(1.5)
             
            # زر إدخال البضاعة
            btn_inv = self.driver.window.child_window(title="إدخال بضاعة", control_type="Button")
            if btn_inv.exists():
                btn_inv.click_input()
            else:
                self.driver.click("إدخال بضاعة")
                 
            time.sleep(2)
        except Exception as e:
            print(f"   ❌ فشل الانتقال للمخزن: {e}")
            self.driver.print_hierarchy()

    def add_new_product(self, name: str, barcode: str, purchase_price: float, 
                        sell_price: float, quantity: int):
        """إضافة منتج جديد بكامل تفاصيله"""
        self._log(f"إضافة منتج جديد: {name} ({barcode})")
        
        self.driver.set_value_near_label("اسم المادة", name)
        self.driver.set_value_near_label("الباركود", barcode)
        self.driver.set_value_near_label("سعر الشراء", str(purchase_price))
        self.driver.set_value_near_label("سعر المبيع", str(sell_price))
        self.driver.set_value_near_label("العدد", str(quantity))

        # حفظ
        self._log("حفظ المنتج...")
        try:
            self.driver.click("حفظ")
        except:
            self.driver.click("إضافة")
        
        time.sleep(1)
        
        # التعامل مع رسائل النجاح
        try:
            self.driver.click("موافق")
        except:
            pass


class EditInvoiceScreen(InvoiceScreen):
    """
    نموذج شاشة تعديل الفواتير.
    يرث من InvoiceScreen لأن الحقول متشابهة جداً.
    """
    
    def open(self):
        """فتح شاشة تعديل القوائم"""
        self._log("الانتقال إلى تعديل القوائم...")
        self.driver.navigate_home()
        time.sleep(0.5)
        self.driver.click("تعديل القوائم")
        time.sleep(2)

    def search_invoice_by_customer(self, customer_name: str):
        """البحث عن فاتورة باسم العميل"""
        self._log(f"البحث عن فواتير العميل: {customer_name}")
        
        # البحث في حقل اسم العميل
        try:
            edits = self.driver.window.descendants(control_type="Edit")
            for edit in edits:
                try:
                    text = edit.window_text() or ""
                    if "العميل" in text or "اسم" in text or "بحث" in text:
                        edit.click_input()
                        time.sleep(0.2)
                        from pywinauto.keyboard import send_keys
                        send_keys("^a")  # تحديد الكل
                        send_keys(customer_name, with_spaces=True)
                        time.sleep(1.5)
                        return
                except:
                    pass
            
            # fallback: أول حقل Edit
            if edits:
                edits[0].click_input()
                time.sleep(0.2)
                from pywinauto.keyboard import send_keys
                send_keys(customer_name, with_spaces=True)
                time.sleep(1.5)
        except Exception as e:
            print(f"   ⚠️ فشل البحث: {e}")
    
    def search_invoice(self, search_term: str):
        """البحث عن فاتورة"""
        self._log(f"البحث عن فاتورة: {search_term}")
        self.driver.set_text("بحث باسم العميل", search_term, is_search=True)
        time.sleep(1)

    def select_first_invoice(self):
        """اختيار أول فاتورة للتعديل - الضغط بالماوس على البطاقة"""
        self._log("اختيار آخر فاتورة (الأولى بالقائمة)...")
        
        try:
            # الحصول على موقع النافذة
            window_rect = self.driver.window.rectangle()
            window_x = window_rect.left
            window_y = window_rect.top
            
            # البحث عن بطاقة الفاتورة
            all_elements = self.driver.window.descendants()
            
            # البحث عن نص "محفوظة" أو "معلقة" أو "دينار" - هذه العناصر داخل البطاقة
            for elem in all_elements:
                try:
                    text = elem.window_text() or ""
                    rect = elem.rectangle()
                    
                    # إذا وجدنا عنصر يحتوي على "محفوظة" أو "دينار"، نضغط عليه
                    if ("محفوظة" in text or "معلقة" in text or "دينار" in text) and rect.top > 130:
                        # حساب مركز العنصر
                        center_x = (rect.left + rect.right) // 2
                        center_y = (rect.top + rect.bottom) // 2
                        
                        print(f"   🖱️ الضغط على البطاقة في: X={center_x}, Y={center_y}")
                        
                        # استخدام click_input مع الإحداثيات
                        from pywinauto import mouse
                        mouse.click(coords=(center_x, center_y))
                        time.sleep(2)
                        return True
                except:
                    pass
                    
            # محاولة بديلة: الضغط على موقع ثابت للبطاقة الأولى
            # البطاقة عادة تكون في Y ~ 180 ومنتصف الشاشة X ~ 500
            print("   🔄 استخدام إحداثيات ثابتة للبطاقة...")
            card_x = window_x + 500  # منتصف النافذة تقريباً
            card_y = window_y + 180  # موقع البطاقة الأولى
            
            from pywinauto import mouse
            mouse.click(coords=(card_x, card_y))
            time.sleep(2)
            return True
                    
        except Exception as e:
            print(f"   ⚠️ فشل اختيار الفاتورة: {e}")
            import traceback
            traceback.print_exc()
        
        return False

    def select_invoice_by_id(self, invoice_id: str):
        """اختيار فاتورة برقمها"""
        self._log(f"اختيار الفاتورة رقم: {invoice_id}")
        self.search_invoice(invoice_id)
        time.sleep(1)
        self.select_first_invoice()
    
    def click_edit_button(self):
        """الضغط على زر القلم (✏️) في أعلى اليسار من الـ AppBar"""
        self._log("الضغط على زر التعديل (القلم ✏️)...")
        
        try:
            # الحصول على موقع النافذة
            window_rect = self.driver.window.rectangle()
            window_x = window_rect.left
            window_y = window_rect.top
            
            # زر القلم في أعلى اليسار (حوالي X=40, Y=45 من النافذة)
            # بناءً على الصورة: زر القلم في الـ AppBar
            edit_btn_x = window_x + 40
            edit_btn_y = window_y + 45
            
            print(f"   🖱️ الضغط على زر القلم في: X={edit_btn_x}, Y={edit_btn_y}")
            
            from pywinauto import mouse
            mouse.click(coords=(edit_btn_x, edit_btn_y))
            time.sleep(1)
            return True
                    
        except Exception as e:
            print(f"   ⚠️ فشل العثور على زر التعديل: {e}")
        
        print("   ⚠️ لم يتم العثور على زر القلم")
        return False

    def delete_item(self, index: int = 0):
        """حذف صنف من الفاتورة"""
        self._log(f"حذف الصنف رقم {index + 1}...")
        
        # محاولة الضغط على زر الحذف
        try:
            # البحث عن أزرار الحذف (عادة 🗑️ أو ❌)
            delete_btns = self.driver.window.descendants(title="حذف الصنف")
            if delete_btns:
                delete_btns[min(index, len(delete_btns)-1)].click_input()
            else:
                # محاولة بديلة
                self.driver.click("حذف الصنف")
        except Exception as e:
            print(f"   ⚠️ لم يتم العثور على زر الحذف: {e}")
        
        time.sleep(0.5)
        
        # تأكيد الحذف إذا ظهر حوار
        try:
            self.driver.click("نعم")
        except:
            pass

    def add_product_row(self, name: str, quantity: int, price: float):
        """إضافة صنف جديد للفاتورة في شاشة التعديل"""
        self._log(f"إضافة صنف: {name}")
        
        # استخدام طريقة الإدخال عبر الصفوف
        self.enter_invoice_row(name, quantity, price)

    def delete_invoice(self):
        """حذف الفاتورة بالكامل"""
        self._log("⚠️ حذف الفاتورة بالكامل...")
        self.driver.click("حذف الفاتورة")
        time.sleep(0.5)
        
        # تأكيد الحذف
        try:
            self.driver.click("نعم")
        except:
            self.driver.click("تأكيد")

    def save_and_confirm(self):
        """حفظ تعديلات الفاتورة"""
        self._log("💾 حفظ التعديلات...")
        
        # محاولة الضغط على زر الحفظ
        try:
            self.driver.click("حفظ التعديلات")
        except:
            try:
                self.driver.click("حفظ")
            except:
                self.driver.click("حفظ الفاتورة")
        
        time.sleep(1)
        
        # تأكيد الحوار إذا ظهر
        try:
            self.driver.click("نعم")
        except:
            pass
        try:
            self.driver.click("موافق")
        except:
            pass
