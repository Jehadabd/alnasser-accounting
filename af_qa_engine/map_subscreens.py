# af_qa_engine/map_subscreens.py
import sys
import os
import time

current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

from automation.driver import AppDriver

def map_subscreens():
    print("🗺️ Mapping Sub-screens (Inventory & Invoice)...")
    config_path = os.path.join(current_dir, "config.yaml")
    driver = AppDriver(config_path)
    driver.connect()
    
    if not driver.window or not driver.window.exists():
        driver.launch()
        time.sleep(5)

    # 1. Map Create Invoice
    print("\n📝 Navigating to Create Invoice...")
    driver.navigate_home()
    driver.click("إنشاء قائمة")
    time.sleep(2)
    
    dump(driver, "hierarchy_create_invoice.txt")
    driver.navigate_home()

    # 2. Map Enter Inventory (via Debt Records)
    print("\n📦 Navigating to Enter Inventory...")
    driver.go_to_debt_records()
    time.sleep(1)
    
    # Try different click strategies
    print("   Attempting to click 'إدخال بضاعة'...")
    try:
        # Strategy 1: Find by text and click input
        btn = driver.find_text_element("إدخال بضاعة")
        if btn:
            print("   Found button by text, clicking input...")
            btn.click_input()
        else:
            print("   Button not found by find_text_element, trying generic click...")
            driver.click("إدخال بضاعة")
    except Exception as e:
        print(f"   Click failed: {e}")
        
    time.sleep(3) # Wait for animation
    dump(driver, "hierarchy_enter_inventory.txt")
    
    driver.navigate_home()

def dump(driver, filename):
    print(f"   📸 Saving {filename}...")
    try:
        with open(filename, "w", encoding="utf-8") as f:
            from io import StringIO
            old_stdout = sys.stdout
            sys.stdout = mystdout = StringIO()
            driver.print_hierarchy()
            sys.stdout = old_stdout
            f.write(mystdout.getvalue())
        print(f"   ✅ Saved {filename}")
    except Exception as e:
        print(f"   ❌ Error saving {filename}: {e}")

if __name__ == "__main__":
    map_subscreens()
