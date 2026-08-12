# af_qa_engine/inspect_create_invoice.py
"""
سكربت لتحليل شاشة إنشاء الفاتورة والتعرف على الحقول
"""
import sys
import os
import time

# Fix encoding for Windows console
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from automation.driver import AppDriver
from pywinauto.keyboard import send_keys

def inspect_screen():
    print("Inspecting Create Invoice Screen...")
    
    driver = AppDriver("config.yaml")
    driver.connect()
    
    if not driver.window:
        print("App not connected")
        return
    
    # Navigate to Create Invoice screen - click on text element
    print("Navigating to Create Invoice screen...")
    
    try:
        # Find the text element and click it
        texts = driver.window.descendants(control_type="Text", title="إنشاء قائمة")
        if texts:
            print(f"Found 'Create Invoice' text at: {texts[0].rectangle()}")
            texts[0].click_input()
            time.sleep(3)
        else:
            print("Text not found, trying coordinates...")
            # Based on hierarchy: (568, 140)
            import pywinauto.mouse as mouse
            mouse.click(coords=(568, 155))
            time.sleep(3)
    except Exception as e:
        print(f"Error navigating: {e}")
        return
    
    # Save hierarchy to file
    print("Saving hierarchy to file...")
    with open("hierarchy_invoice.txt", "w", encoding="utf-8") as f:
        # Get all descendants
        try:
            for elem in driver.window.descendants():
                try:
                    ctrl_type = elem.element_info.control_type
                    name = elem.window_text() or ""
                    rect = elem.rectangle()
                    line = f"{ctrl_type:20} | {name[:40]:40} | ({rect.left}, {rect.top})\n"
                    f.write(line)
                except:
                    pass
        except Exception as e:
            f.write(f"Error: {e}\n")
    
    print("Done! Check hierarchy_invoice.txt")

if __name__ == "__main__":
    inspect_screen()
