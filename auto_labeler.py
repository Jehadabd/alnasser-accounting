import os
import glob
import json
import easyocr
import re

TARGET_DIR = r"training_data"
# Keywords for extraction
TOTAL_KEYS = ["المجموع", "صافي", "القيمة", "الاجمالي", "total", "net", "amount", "sum"]
DATE_KEYS = ["التاريخ", "تاريخ", "date"]
NUM_KEYS = ["رقم", "الفاتورة", "inv", "no", "num"]

import cv2
import numpy as np

def extract_meta(image_path, reader):
    print(f"  Scanning: {os.path.basename(image_path)}...")
    
    # Robust read for non-ASCII paths on Windows
    img_array = np.fromfile(image_path, np.uint8)
    image = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
    
    if image is None:
        print(f"  ❌ Error: Could not read {image_path}")
        return {}

    results = reader.readtext(image) # Pass image array instead of path
    
    full_text = " ".join([r[1] for r in results])
    
    # Defaults
    data = {
        "TOTAL": "",
        "DATE": "",
        "VENDOR": "",
        "INVOICE_NUM": ""
    }

    # 1. Vendor (Usually first few lines)
    if len(results) > 0:
        data["VENDOR"] = results[0][1]

    # 2. Date Regex
    date_pattern = r"(\d{1,4}[-/]\d{1,2}[-/]\d{1,4})"
    dates = re.findall(date_pattern, full_text)
    if dates:
        data["DATE"] = dates[0]

    # 3. Total (Look for largest number near keywords)
    price_pattern = r"(\d+[\.,]\d{2})"
    prices = re.findall(price_pattern, full_text)
    if prices:
        # Heuristic: Take the largest one as potential total
        float_prices = [float(p.replace(",", "")) for p in prices]
        data["TOTAL"] = str(max(float_prices))

    # 4. Invoice Number
    num_pattern = r"(?:inv|no|رقم)[:\s]*(\w+)"
    nums = re.findall(num_pattern, full_text.lower())
    if nums:
        data["INVOICE_NUM"] = nums[0]

    return data

def run_auto_label():
    reader = easyocr.Reader(['ar', 'en'], gpu=False) # Use CPU for stability
    images = glob.glob(os.path.join(TARGET_DIR, "*.png"))
    
    print(f"Auto-Labeling {len(images)} images...")
    
    for img_path in images:
        txt_path = img_path.replace(".png", ".txt")
        
        # We always attempt to improve empty files
        existing_data = {}
        if os.path.exists(txt_path):
            try:
                with open(txt_path, 'r', encoding='utf-8') as f:
                    existing_data = json.load(f)
            except: pass
            
        # Only process if fields are empty
        if not existing_data.get("TOTAL"):
            new_data = extract_meta(img_path, reader)
            # Merge (don't overwrite user changes if they made any)
            for k in ["TOTAL", "DATE", "VENDOR", "INVOICE_NUM"]:
                if not existing_data.get(k):
                    existing_data[k] = new_data[k]
                    
            with open(txt_path, "w", encoding="utf-8") as f:
                json.dump(existing_data, f, indent=4, ensure_ascii=False)
            print(f"  ✅ Updated {os.path.basename(txt_path)}")
        else:
            print(f"  ⏭️ Skipping {os.path.basename(txt_path)} (already contains data)")

if __name__ == "__main__":
    run_auto_label()
