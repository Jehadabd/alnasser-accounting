import os
import glob
import json

TARGET_DIR = r"training_data"
TEMPLATE = {
    "TOTAL": "",
    "DATE": "",
    "VENDOR": "",
    "INVOICE_NUM": ""
}

def create_templates():
    files = glob.glob(os.path.join(TARGET_DIR, "*.png"))
    print(f"Found {len(files)} images.")

    for img_path in files:
        txt_path = img_path.replace(".png", ".txt")
        # Only create if doesn't exist to avoid overwriting work
        if not os.path.exists(txt_path):
            with open(txt_path, "w", encoding="utf-8") as f:
                json.dump(TEMPLATE, f, indent=4, ensure_ascii=False)
            print(f"Created key file: {os.path.basename(txt_path)}")
        else:
            print(f"Skipped existing: {os.path.basename(txt_path)}")

if __name__ == "__main__":
    create_templates()
