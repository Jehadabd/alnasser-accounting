# af_qa_engine/map_edit_screen.py
import sys
import os
import time

current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

from automation.driver import AppDriver

def map_edit_screen():
    print("🗺️ Mapping Edit Invoice Screen...")
    config_path = os.path.join(current_dir, "config.yaml")
    driver = AppDriver(config_path)
    driver.connect()
    
    if not driver.window or not driver.window.exists():
        driver.launch()
        time.sleep(5)

    driver.navigate_home()
    
    # 1. Click "Edit Lists" (تعديل القوائم)
    print("   ✏️ Clicking 'تعديل القوائم'...")
    driver.click("تعديل القوائم")
    time.sleep(2)
    
    # Dump list hierarchy
    dump(driver, "hierarchy_edit_list.txt")

    # 2. Select first item (if exists) -> Simulated
    # Usually list items are Buttons or Panes. We check for any clickable item.
    # For now, we assume user clicks manually or we find a way.
    # Let's try to click a generic coordinates or find a list item pattern if mapped.
    
    print("   👉 Attempting to select first invoice...")
    # This is speculative, assuming a list item exists or taking a screenshot to decide.
    # We will just dump the hierarchy of the list screen for now to analyze how to select.

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
    map_edit_screen()
