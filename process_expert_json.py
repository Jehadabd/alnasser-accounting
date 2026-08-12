import os
import json
import fitz  # PyMuPDF
import glob

# Paths
JSON_PATH = r"C:\Users\jihad\Downloads\deepseek_json_20260128_ba7725.json"
SOURCE_DIRS = [
    r"C:\Users\jihad\Documents\invoices",
    r"C:\Users\jihad\Documents\فواتير_PDF_2025-12-13_17-23"
]
TARGET_DIR = "training_data"

os.makedirs(TARGET_DIR, exist_ok=True)

def robust_json_load(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        print("⚠️ JSON is truncated. Attempting recovery...")
        # Find the last valid closing bracket of an object
        last_bracket = content.rfind("},")
        if last_bracket == -1:
            last_bracket = content.rfind("}")
            
        if last_bracket != -1:
            fixed_content = content[:last_bracket+1] + "]"
            try:
                data = json.loads(fixed_content)
                print(f"✅ Successfully recovered {len(data)} objects.")
                return data
            except Exception as e:
                print(f"❌ Recovery failed: {e}")
        return []

def process():
    if not os.path.exists(JSON_PATH):
        print(f"❌ JSON file not found at {JSON_PATH}")
        return

    expert_data = robust_json_load(JSON_PATH)
    if not expert_data:
        print("❌ No data could be loaded/recovered.")
        return

    print(f"📂 Processing {len(expert_data)} entries.")

    for entry in expert_data:
        file_name = entry.get("file_name")
        if not file_name:
            continue
            
        found = False
        
        # 1. Find PDF
        for folder in SOURCE_DIRS:
            pdf_path = os.path.join(folder, file_name)
            if os.path.exists(pdf_path):
                # 2. Convert to Image
                try:
                    doc = fitz.open(pdf_path)
                    page = doc.load_page(0)
                    mat = fitz.Matrix(2, 2)
                    pix = page.get_pixmap(matrix=mat)
                    
                    # Save image as PNG
                    stem = os.path.splitext(file_name)[0]
                    png_name = f"{stem}.png"
                    pix.save(os.path.join(TARGET_DIR, png_name))
                    
                    # 3. Create Label TXT (JSON format for models)
                    txt_name = f"{stem}.txt"
                    
                    # Enhanced labels for Ensemble training
                    label_data = {
                        "VENDOR": entry.get("customer_name") or entry.get("company_info", {}).get("name", ""),
                        "DATE": entry.get("date", ""),
                        "INVOICE_NUM": entry.get("invoice_number", ""),
                        "TOTAL": str(entry.get("subtotal") or entry.get("total", "")),
                        "CURRENCY": "IQD",
                        "ITEMS": []
                    }
                    
                    # Map line items
                    for item in entry.get("items", []):
                        label_data["ITEMS"].append({
                            "DESC": item.get("description", ""),
                            "QTY": str(item.get("quantity", "")),
                            "PRICE": str(item.get("unit_price", "")),
                            "LINE_TOTAL": str(item.get("total", ""))
                        })
                    
                    with open(os.path.join(TARGET_DIR, txt_name), "w", encoding="utf-8") as f:
                        json.dump(label_data, f, indent=4, ensure_ascii=False)
                    
                    print(f"✅ Processed: {file_name} -> {png_name} & {txt_name}")
                    found = True
                    break
                except Exception as e:
                    print(f"❌ Error processing {file_name}: {e}")
        
        if not found:
            print(f"⚠️ Could not find {file_name} in source directories.")

if __name__ == "__main__":
    process()
