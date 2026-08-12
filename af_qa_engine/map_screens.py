# af_qa_engine/map_screens.py
import sys
import os
import time

# Add current directory to path
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

from automation.driver import AppDriver

def dump_hierarchy(driver, filename):
    print(f"   📸 Saving hierarchy to {filename}...")
    try:
        with open(filename, "w", encoding="utf-8") as f:
            # Capture stdout
            from io import StringIO
            old_stdout = sys.stdout
            sys.stdout = mystdout = StringIO()
            driver.print_hierarchy()
            sys.stdout = old_stdout
            f.write(mystdout.getvalue())
        print(f"   ✅ Saved {filename}")
    except Exception as e:
        print(f"   ❌ Failed to save {filename}: {e}")

def map_screens():
    print("🗺️ Starting Screen Mapping Sequence...")
    config_path = os.path.join(current_dir, "config.yaml")
    driver = AppDriver(config_path)
    print("🗺️ Starting Screen Mapping Sequence...")
    config_path = os.path.join(current_dir, "config.yaml")
    driver = AppDriver(config_path)
    driver.connect()
    
    # Check connection safely
    is_connected = False
    try:
        if driver.window and driver.window.exists():
            is_connected = True
    except:
        pass

    if not is_connected:
        print("❌ App not found/connected. Launching...")
        driver.launch()
        time.sleep(5)
    
    if not driver.window or not driver.window.exists():
         print("❌ Fatal: Could not connect to app.")
         return

    # 1. Map Reports Screen (Inside) -> Daily Report
    print("\n📍 Navigating to Reports Screen...")
    driver.navigate_home()
    driver.go_to_reports()
    
    # Handle Password
    try:
         driver.set_text("كلمة السر", "2001")
         driver.click("تأكيد")
         driver._sleep()
         driver._sleep()
    except:
         pass
    
    # Dump Main Reports Menu
    dump_hierarchy(driver, "hierarchy_reports_menu.txt")

    # Enter Daily Report
    print("   👉 Clicking Daily Report...")
    driver.click("تقرير اليوم", retries=3)
    driver._sleep()
    dump_hierarchy(driver, "hierarchy_daily_report.txt")
    driver.navigate_home()

    # 2. Map Debt Records Screen -> Customer Details (if possible)
    print("\n📍 Navigating to Debt Records Screen...")
    driver.go_to_debt_records()
    time.sleep(2)
    dump_hierarchy(driver, "hierarchy_debt_list.txt")

    # Search and Enter (Try a known user or first user)
    # We will try to click the first "Text" element that looks like a name (not header)
    # Or just search 'TestUser' created previously if exists
    print("   👉 Entering Customer Details (Attempt)...")
    try:
        driver.set_text("ابحث عن عميل...", "TestUser", is_search=True)
        time.sleep(1)
        # Click the first result if available. 
        # Since we don't know the exact name, we might just look for *any* result text or "0 د.ع" which usually appears near names.
        # Let's try to click a point relative to the list or use hierarchy analysis manually later.
        # For now, let's just dump the list. If we created a user in the previous run, we can search it.
        # driver.click("TestUser_...") 
        pass 
    except:
        pass
    
    driver.navigate_home()
    print("\n🎉 Mapping Complete.")

if __name__ == "__main__":
    map_screens()
