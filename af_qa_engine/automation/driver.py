# af_qa_engine/automation/driver.py
import time
import yaml
from pywinauto.application import Application
from pywinauto.findwindows import ElementNotFoundError
from pywinauto.keyboard import send_keys

class AppDriver:
    """
    محرك التحكم في التطبيق (Automation Driver).
    محسن للتعامل مع واجهات Flutter Desktop.
    """
    def __init__(self, config_path="config.yaml"):
        with open(config_path, "r", encoding="utf-8") as f:
            self.config = yaml.safe_load(f)
        
        self.app = None
        self.window = None
        self.timeout = 20
        self.slow_mode = self.config['testing'].get('action_delay', 0.5)

    def launch(self):
        """تشغيل التطبيق"""
        exe_path = self.config['app']['exe_path']
        print(f"🚀 تشغيل التطبيق من: {exe_path}")
        self.app = Application(backend="uia").start(exe_path)
        self.wait_for_window()

    def connect(self):
        """الاتصال بتطبيق مفتوح"""
        try:
            self.app = Application(backend="uia").connect(title_re=self.config['app']['window_title'])
            self.wait_for_window()
            print("✅ تم الاتصال بالتطبيق بنجاح")
        except ElementNotFoundError:
            print("❌ التطبيق غير مفتوح")

    def wait_for_window(self):
        title = self.config['app']['window_title']
        for _ in range(self.timeout):
            try:
                self.window = self.app.window(title_re=f".*{title}.*")
                if self.window.exists():
                    self.window.wait('visible', timeout=5)
                    return
            except:
                time.sleep(1)
        raise TimeoutError("لم يتم العثور على النافذة الرئيسية")

    def _sleep(self):
        time.sleep(self.slow_mode)

    def print_hierarchy(self):
        """طباعة شجرة العناصر للتشخيص"""
        self.window.print_control_identifiers()

    def click(self, name_or_id, retries=3):
        """ضغط زر بالاسم أو المعرف"""
        print(f"🖱️ ضغط: {name_or_id}")
        last_err = None
        for attempt in range(retries):
            try:
                # محاولة 1: زر صريح
                btn = self.window.descendants(control_type="Button", title=name_or_id)
                
                # محاولة 2: عنصر نصي (في Flutter أحياناً يكون النص هو الظاهر)
                if not btn:
                     btn = self.window.descendants(title=name_or_id, control_type="Text")
                
                # محاولة 3: بحث عام بالعنوان
                if not btn:
                     btn = self.window.descendants(title=name_or_id)

                if btn:
                    # نضغط العنصر (أو الأول إذا كان قائمة)
                    # يفضل الضغط على المركز لضمان الاستجابة
                    btn[0].click_input()
                    self._sleep()
                    return
            except Exception as e:
                last_err = e
                time.sleep(1)
        
        print(f"⚠️ فشل العثور على العنصر '{name_or_id}': {last_err}")

    def set_text(self, label, value, is_search=False):
        """كتابة نص في حقل"""
        print(f"⌨️ كتابة '{value}' في حقل '{label}'")
        try:
            # البحث عن Edit control
            # في Flutter Semantic، أحياناً يكون الاسم هو الـ Label
            field = self.window.descendants(control_type="Edit", title=label)
            
            # إذا لم نجد، نبحث عن جميع الـ Edits ونحاول التخمين (خطر لكن مفيد للتجربة)
            if not field and is_search:
                all_edits = self.window.descendants(control_type="Edit")
                if all_edits:
                    field = [all_edits[0]] # نفترض الأول هو البحث

            if field:
                field[0].click_input()
                send_keys('^a') 
                send_keys('{DELETE}')
                self._sleep()
                send_keys(str(value))
                self._sleep()
                if not is_search:
                     send_keys('{TAB}') # للخروج من الحقل
                self._sleep()
            else:
                print(f"⚠️ لم يتم العثور على حقل الإدخال: {label}")
        except Exception as e:
            print(f"❌ خطأ في الكتابة: {e}")

    def get_all_texts(self):
        """إرجاع كل النصوص الظاهرة في الشاشة للتفتيش"""
        texts = []
        try:
            elements = self.window.descendants(control_type="Text")
            for el in elements:
                t = el.window_text()
                if t: texts.append(t)
        except:
            pass
        return texts

    def find_text_element(self, content):
        """البحث عن عنصر نصي يحتوي على النص"""
        try:
            elements = self.window.descendants(control_type="Text", title=content)
            if elements: return elements[0]
            # بحث جزئي
            elements = self.window.descendants(control_type="Text")
            for el in elements:
                if content in el.window_text():
                    return el
        except:
            pass
        return None

    # --- Navigation Helpers ---
    def navigate_home(self):
        # محاولة الضغط على زر الرجوع أو ESC
        print("🏠 العودة للرئيسية...")
        try:
             # 1. استخدام ESC عدة مرات (أقوى طريقة)
             for _ in range(3):
                 send_keys('{ESC}')
                 self._sleep()
                 
                 # التحقق من أننا في الرئيسية (وجود زر سجل الديون)
                 if self.window.child_window(title="سجل الديون", control_type="Button").exists():
                     print("   ✅ تم الوصول للرئيسية")
                     return

             # 2. محاولة البحث عن زر الرجوع
             back_btns = self.window.descendants(title="Back") or self.window.descendants(title="رجوع")
             if back_btns:
                 back_btns[0].click_input()
                 
        except:
             pass

    def set_value_near_label(self, label_text, value):
        """كتابة قيمة في الحقل المجاور للتسمية"""
        print(f"⌨️ كتابة '{value}' بجوار '{label_text}'")
        try:
            # 1. العثور على التسمية
            label_el = self.window.descendants(control_type="Text", title=label_text)
            if not label_el:
                 # بحث جزئي
                 all_texts = self.window.descendants(control_type="Text")
                 label_el = [t for t in all_texts if label_text in t.window_text()]
            
            if not label_el:
                print(f"⚠️ لم يتم العثور على التسمية: {label_text}")
                return

            # 2. البحث عن أقرب Edit control
            # نفترض أنه يأتي بعده في الشجرة (Sibling) أو قريب في الإحداثيات
            # سنبحث عن كل الـ Edits ونأخذ الأقرب مسافة
            target_label = label_el[0]
            lbl_rect = target_label.rectangle()
            
            edits = self.window.descendants(control_type="Edit")
            best_edit = None
            min_dist = 99999
            
            for edit in edits:
                edit_rect = edit.rectangle()
                # يجب أن يكون الـ Edit أسفل أو بجوار الـ Label
                # المسافة العمودية
                dy = abs(edit_rect.top - lbl_rect.bottom)
                # المسافة الأفقية
                dx = abs(edit_rect.left - lbl_rect.left)
                
                dist = dy + dx
                if dist < min_dist:
                    min_dist = dist
                    best_edit = edit
            
            if best_edit:
                best_edit.click_input()
                send_keys('^a')
                send_keys('{DELETE}')
                self._sleep()
                send_keys(str(value))
                self._sleep()
            else:
                 print(f"⚠️ لم يتم العثور على حقل Edit قريب من {label_text}")

        except Exception as e:
            print(f"❌ خطأ في set_value_near_label: {e}")
            
    def go_to_create_invoice(self):
        self.click("إنشاء قائمة") # تم التعديل


    def go_to_debt_records(self):
        self.click("سجل الديون")

    def go_to_reports(self):
        self.click("التقارير")
