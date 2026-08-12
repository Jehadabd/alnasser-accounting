# af_qa_engine/main.py
import os
import sys
import time
import yaml

# إضافة المجلد الحالي للمسار
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

from automation.driver import AppDriver
from scenarios.killer_scenarios import KillerScenarios

def main():
    print("🤖 بدء تشغيل محرك الاختبار الذاتي (AF-QA Engine)...")
    
    config_path = os.path.join(current_dir, "config.yaml")
    if not os.path.exists(config_path):
        print("❌ ملف الإعدادات ناقص")
        return

    try:
        # 1. تهيئة والاتصال
        driver = AppDriver(config_path)
        
        # محاولة الاتصال بتطبيق مفتوح
        try:
            driver.connect()
        except Exception as e:
            print(f"⚠️ فشل الاتصال: {e}")
        
        # التحقق من نجاح الاتصال
        is_connected = False
        try:
            if driver.window and driver.window.exists():
                is_connected = True
        except:
            pass

        if not is_connected:
            print("🚀 لم يتم العثور على التطبيق. جاري التشغيل...")
            try:
                driver.launch()
            except Exception as e:
                print(f"❌ فشل تشغيل التطبيق: {e}")
                print("⏳ الانتظار 5 ثوان ثم إعادة المحاولة...")
                time.sleep(5)
                driver.launch()
            
            # الانتظار للتحميل الكامل
            print("⏳ انتظار تحميل التطبيق...")
            time.sleep(15)
            
            # إعادة الاتصال بعد التشغيل
            try:
                driver.connect()
            except:
                pass

        # تحميل الإعدادات لتمريرها للسيناريو
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)

        # 2. تشغيل السيناريو الذكي
        scenario = KillerScenarios(driver, config)
        scenario.run_smart_user_simulation()

    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"\n❌ حدث خطأ:\n{str(e)}")
        # طباعة الهرمية للمساعدة في التصحيح
        if 'driver' in locals() and driver.window:
            print("\n🔍 هيكلية الواجهة الحالية (للتشخيص):")
            try:
                driver.print_hierarchy()
            except:
                pass

if __name__ == "__main__":
    main()
