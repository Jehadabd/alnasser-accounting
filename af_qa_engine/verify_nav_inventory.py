# af_qa_engine/verify_nav_inventory.py
import sys
import os
import time

current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

from automation.driver import AppDriver

def debug_inventory_nav():
    print("🐞 Debugging Inventory Navigation...")
    config_path = os.path.join(current_dir, "config.yaml")
    driver = AppDriver(config_path)
    driver.connect()
    
    if not driver.window or not driver.window.exists():
        driver.launch()
        time.sleep(5)

    print("🏠 Ensuring Home...")
    driver.navigate_home()
    time.sleep(1)

    # 1. Click Debt Records
    print("👉 Clicking 'سجل الديون'...")
    try:
        # Try generic click first
        driver.click("سجل الديون") 
    except:
        print("   Click failed, trying alternate...")
        # Try specific known ID from previous dump or finding element by text
        try:
             # Using the underlying pywinauto window to find by text property
             btn = driver.window.descendants(control_type="Button", title="سجل الديون")[0]
             btn.click_input()
        except Exception as e:
             print(f"   Matches failed: {e}")
             # Last resort: coordinates? No, too risky.
             return

    time.sleep(2)

    # 2. Click Enter Inventory
    print("👉 Clicking 'إدخال بضاعة'...")
    try:
        # Direct pywinauto call (More robust)
        btn = driver.window.child_window(title="إدخال بضاعة", control_type="Button")
        if btn.exists():
            print("   Found button directly, clicking...")
            btn.click_input()
        else:
            print("   Button not found via child_window, trying generic click...")
            driver.click("إدخال بضاعة")
    except Exception as e:
        print(f"   Click failed: {e}")

    time.sleep(3)
    
    print("📸 Saving Inventory Hierarchy...")
    try:
        with open("hierarchy_inventory_debug.txt", "w", encoding="utf-8") as f:
            from io import StringIO
            old_stdout = sys.stdout
            sys.stdout = mystdout = StringIO()
            driver.print_hierarchy()
            sys.stdout = old_stdout
            f.write(mystdout.getvalue())
        print("✅ Saved hierarchy_inventory_debug.txt")
    except Exception as e:
        print(f"❌ Error saving: {e}")

if __name__ == "__main__":
    debug_inventory_nav()
