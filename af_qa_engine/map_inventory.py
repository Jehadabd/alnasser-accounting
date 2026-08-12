# af_qa_engine/map_inventory.py
import sys
import os
import time

current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

from automation.driver import AppDriver

def map_inventory():
    print("🗺️ Mapping Inventory Screen...")
    config_path = os.path.join(current_dir, "config.yaml")
    driver = AppDriver(config_path)
    driver.connect()
    
    # Auto-launch if needed
    if not driver.window or not driver.window.exists():
        print("🚀 Launching app...")
        driver.launch()
        time.sleep(5)
        
    if not driver.window or not driver.window.exists():
        print("❌ App not connected.")
        return

    driver.navigate_home()
    
    print("   � Going to Debt Records first...")
    driver.go_to_debt_records()
    time.sleep(1)

    print("   �📦 Clicking 'إدخال بضاعة'...")
    driver.click("إدخال بضاعة")
    time.sleep(2)
    
    print("   📸 Saving hierarchy...")
    try:
        with open("hierarchy_inventory.txt", "w", encoding="utf-8") as f:
            from io import StringIO
            old_stdout = sys.stdout
            sys.stdout = mystdout = StringIO()
            driver.print_hierarchy()
            sys.stdout = old_stdout
            f.write(mystdout.getvalue())
        print("   ✅ Saved hierarchy_inventory.txt")
    except Exception as e:
        print(f"❌ Error: {e}")

    driver.navigate_home()

if __name__ == "__main__":
    map_inventory()
