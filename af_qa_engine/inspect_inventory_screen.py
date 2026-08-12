# af_qa_engine/inspect_inventory_screen.py
import sys
import os
import time
from automation.driver import AppDriver

def inspect():
    current_dir = os.path.dirname(os.path.abspath(__file__))
    config_path = os.path.join(current_dir, "config.yaml")
    
    driver = AppDriver(config_path)
    driver.connect()
    
    print("🏠 Going Home...")
    driver.navigate_home()
    time.sleep(2)
    
    print("📒 Going to Debt Records...")
    # Using the robust logic from screens.py logic manually
    try:
        btn = driver.window.child_window(title="سجل الديون", control_type="Button")
        if btn.exists():
            btn.click_input()
        else:
            driver.click("سجل الديون")
    except:
        pass
    time.sleep(2)
    
    print("📦 Clicking Enter Inventory...")
    try:
        btn = driver.window.child_window(title="إدخال بضاعة", control_type="Button")
        if btn.exists():
            btn.click_input()
        else:
            driver.click("إدخال بضاعة")
    except:
        pass
        
    time.sleep(3)
    
    print("📸 Dumping Hierarchy...")
    # Force output to file with explicit UTF-8 encoding to avoid console encoding errors
    try:
        with open("hierarchy_real_inventory.txt", "w", encoding="utf-8") as f:
            old_stdout = sys.stdout
            sys.stdout = f
            try:
                driver.window.print_control_identifiers()
            finally:
                sys.stdout = old_stdout
        print("✅ Done. Check hierarchy_real_inventory.txt")
    except Exception as e:
        print(f"❌ Error dumping hierarchy: {e}")

if __name__ == "__main__":
    inspect()
