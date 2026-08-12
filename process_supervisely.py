import os
import json
import shutil
import re

# Paths
SOURCE_DIR = r"C:\Users\jihad\Desktop\Invoice"
TARGET_DIR = r"c:\Users\jihad\Desktop\shop-maniger-MBmain\training_data"

def process():
    img_dir = os.path.join(SOURCE_DIR, "img")
    ann_dir = os.path.join(SOURCE_DIR, "ann")
    
    if not os.path.exists(TARGET_DIR):
        os.makedirs(TARGET_DIR)

    json_files = [f for f in os.listdir(ann_dir) if f.endswith(".json")]
    print(f"🚀 Processing {len(json_files)} new invoices...")

    for f in json_files:
        with open(os.path.join(ann_dir, f), 'r', encoding='utf-8') as jf:
            data = json.load(jf)
        
        # Target format for our training script
        target_info = {
            "VENDOR": "Unknown",
            "DATE": "",
            "INVOICE_NUM": f.replace(".json", ""),
            "TOTAL": 0.0,
            "ITEMS": []
        }

        # Simple Logic to Map generic text to fields via keywords
        # In a real scenario, we'd use a regex or a small NER, but here we prioritize training speed
        for obj in data.get("objects", []):
            transcription = ""
            for tag in obj.get("tags", []):
                if tag.get("name") == "Transcription":
                    transcription = tag.get("value", "")
            
            if not transcription: continue

            # Heuristics for Field Mapping
            if any(k in transcription for k in ["إجمالي", "المجموع", "مجموع"]):
                # Extract number
                nums = re.findall(r"[\d.,]+", transcription)
                if nums: target_info["TOTAL"] = nums[-1]
            
            if any(k in transcription for k in ["التاريخ", "تاريخ"]):
                 target_info["DATE"] = transcription
            
            if obj.get("classTitle") == "Title":
                 target_info["VENDOR"] = transcription

        # Save the structured label
        txt_name = f.replace(".json", ".txt")
        with open(os.path.join(TARGET_DIR, txt_name), 'w', encoding='utf-8') as out:
            json.dump(target_info, out, ensure_ascii=False, indent=4)
        
        # Copy image
        img_name = f.replace(".json", ".jpg")
        if os.path.exists(os.path.join(img_dir, img_name)):
            shutil.copy(os.path.join(img_dir, img_name), os.path.join(TARGET_DIR, img_name))

    print(f"✅ Successfully integrated {len(json_files)} invoices into {TARGET_DIR}")

if __name__ == "__main__":
    process()
