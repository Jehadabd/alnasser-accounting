# af_qa_engine/inspect_ui.py
import sys
import os
import time

# Add current directory to path
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

from automation.driver import AppDriver

def main():
    print("🔍 Inspecting UI Hierarchy...")
    config_path = os.path.join(current_dir, "config.yaml")
    
    driver = AppDriver(config_path)
    driver.connect()
    
    if not driver.window.exists():
        print("❌ App not found. Please open the app first.")
        return

    print("\n🌲 UI Tree Structure:")
    print("==================================================")
    driver.print_hierarchy()
    print("==================================================")

if __name__ == "__main__":
    main()
