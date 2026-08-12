import os
import glob
import json
import torch
import easyocr
import numpy as np
from PIL import Image
from transformers import LayoutLMv3Processor, LayoutLMv3ForTokenClassification, TrainingArguments, Trainer
from datasets import Dataset, Features, Sequence, ClassLabel, Value, Image as DatasetImage

# 1. Setup
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
if DEVICE == "cpu":
    # Use 90% of CPU cores as requested
    import multiprocessing
    torch.set_num_threads(int(multiprocessing.cpu_count() * 0.9))
    print(f"⚙️ Using {torch.get_num_threads()} CPU threads (90% capacity)")
else:
    print(f"🚀 Using GPU: {torch.cuda.get_device_name(0)}")

MODEL_ID = "microsoft/layoutlmv3-base"
TRAIN_DIR = "training_data"
LABEL_LIST = [
    "O", "B-TOTAL", "I-TOTAL", "B-DATE", "I-DATE", "B-VENDOR", "I-VENDOR", 
    "B-INVOICE_NUM", "I-INVOICE_NUM", "B-DESC", "I-DESC", "B-QTY", "I-QTY", 
    "B-PRICE", "I-PRICE", "B-LINE_TOTAL", "I-LINE_TOTAL"
]
id2label = {k: v for k, v in enumerate(LABEL_LIST)}
label2id = {v: k for k, v in enumerate(LABEL_LIST)}

processor = LayoutLMv3Processor.from_pretrained(MODEL_ID, apply_ocr=False) 
reader = easyocr.Reader(['ar', 'en'], gpu=torch.cuda.is_available())

# 1.5 System Resource Management (90% capacity as requested)
import multiprocessing
CPU_CORES = multiprocessing.cpu_count()
THREADS_TO_USE = max(1, int(CPU_CORES * 0.9))
torch.set_num_threads(THREADS_TO_USE)

print(f"⚙️ System Optimization: Using {THREADS_TO_USE}/{CPU_CORES} CPU threads.")
if torch.cuda.is_available():
    print(f"🚀 GPU Acceleration ENABLED: {torch.cuda.get_device_name(0)}")
else:
    print("⚠️ GPU not found/compatible. Falling back to High-Performance CPU Training.")

import cv2

def get_training_data():
    examples = []
    images = glob.glob(os.path.join(TRAIN_DIR, "*.png")) + glob.glob(os.path.join(TRAIN_DIR, "*.jpg"))
    
    for img_path in images:
        txt_path = img_path.rsplit('.', 1)[0] + ".txt"
        if not os.path.exists(txt_path): continue
        
        with open(txt_path, 'r', encoding='utf-8') as f:
            targets = json.load(f)
            
        # 1. Get OCR Layout (Cashed for CPU performance)
        ocr_cache_path = img_path.rsplit('.', 1)[0] + ".ocr.json"
        results = []
        if os.path.exists(ocr_cache_path):
            try:
                with open(ocr_cache_path, 'r', encoding='utf-8') as f:
                    results_raw = json.load(f)
                    for r in results_raw:
                        results.append([r['box'], r['text'], r['conf']])
            except (json.JSONDecodeError, ValueError, KeyError):
                print(f"⚠️ Corrupted or incompatible cache found for {os.path.basename(img_path)}. Regenerating...")
                results = [] # Force fallback to OCR
        
        if not results:
            img_array = np.fromfile(img_path, np.uint8)
            image_cv = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
            if image_cv is None: continue
            
            print(f"🔍 Running OCR for {os.path.basename(img_path)}...")
            results = reader.readtext(image_cv) 
            
            # Save to cache (Convert numpy int32 to standard int for JSON serialization)
            cache_data = []
            for r in results:
                box = [[int(coord) for coord in point] for point in r[0]]
                cache_data.append({"box": box, "text": r[1], "conf": float(r[2])})
                
            with open(ocr_cache_path, 'w', encoding='utf-8') as f:
                json.dump(cache_data, f, ensure_ascii=False)

        # Convert to PIL/Image array for further processing
        img_array = np.fromfile(img_path, np.uint8)
        image_cv = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
        image_pil = Image.fromarray(cv2.cvtColor(image_cv, cv2.COLOR_BGR2RGB))
        
        words = []
        bboxes = []
        labels = []
        
        width, height = image_pil.size

        # 2. Assign Labels based on Targets
        for res in results:
            box, text, conf = res
            words.append(text)
            
            # Normalize Bounding Boxes [0, 1000]
            x1 = min([p[0] for p in box])
            y1 = min([p[1] for p in box])
            x2 = max([p[0] for p in box])
            y2 = max([p[1] for p in box])
            
            # Clamp and normalize
            x1 = int((max(0, min(x1, width)) / width) * 1000)
            y1 = int((max(0, min(y1, height)) / height) * 1000)
            x2 = int((max(0, min(x2, width)) / width) * 1000)
            y2 = int((max(0, min(y2, height)) / height) * 1000)
            
            bboxes.append([x1, y1, x2, y2])
            
            assigned_label = "O"
            cleaned_text = text.strip()
            
            # Check Global Fields
            for key in ["VENDOR", "DATE", "INVOICE_NUM", "TOTAL"]:
                val = str(targets.get(key, ""))
                if val and val in cleaned_text:
                    assigned_label = f"B-{key}"
                    break
            
            # Check Item Fields (Nested)
            if assigned_label == "O":
                for item in targets.get("ITEMS", []):
                    matched = False
                    for ikey in ["DESC", "QTY", "PRICE", "LINE_TOTAL"]:
                        ival = str(item.get(ikey, ""))
                        if ival and (cleaned_text in ival or ival in cleaned_text) and len(cleaned_text) > 1:
                            assigned_label = f"B-{ikey}"
                            matched = True
                            break
                    if matched: break

            labels.append(label2id.get(assigned_label, 0))

        examples.append({
            "image": image_pil,
            "tokens": words,
            "bboxes": bboxes,
            "ner_tags": labels
        })
    
    return examples

# 2. Preprocessing
def preprocess_data(examples):
    images = [ex["image"] for ex in examples]
    words = [ex["tokens"] for ex in examples]
    boxes = [ex["bboxes"] for ex in examples]
    word_labels = [ex["ner_tags"] for ex in examples]

    encoding = processor(images, words, boxes=boxes, word_labels=word_labels,
                         truncation=True, padding="max_length")
    return encoding

# 3. Main Training Loop
def train():
    print("Loading Dataset...")
    raw_data = get_training_data()
    if not raw_data:
        print("No training data found! Please fill .txt files in training_data/")
        return

    features = Features({
        'pixel_values': DatasetImage(),
        'input_ids': Sequence(feature=Value(dtype='int64')),
        'attention_mask': Sequence(feature=Value(dtype='int64')),
        'bbox': Sequence(feature=Sequence(feature=Value(dtype='int64'), length=4)),
        'labels': Sequence(feature=ClassLabel(names=LABEL_LIST)),
    })
    
    # We apply preprocessing directly during dataset creation for simplicity locally
    encoded_data = preprocess_data(raw_data)
    dataset = Dataset.from_dict(encoded_data)

    print(f"Starting Training on {DEVICE}...")
    model = LayoutLMv3ForTokenClassification.from_pretrained(
        MODEL_ID,
        num_labels=len(LABEL_LIST),
        id2label=id2label,
        label2id=label2id
    )

    training_args = TrainingArguments(
        output_dir="checkpoints_arabic",
        max_steps=1000, # Increased for high-capacity training
        per_device_train_batch_size=2 if DEVICE == "cuda" else 1, # Better utilization
        gradient_accumulation_steps=2, 
        learning_rate=5e-5,
        save_total_limit=1,
        logging_steps=5,
        dataloader_num_workers=4 if DEVICE == "cuda" else 0, # Maximize throughput
        fp16=True if DEVICE == "cuda" else False, # Speed up on GPU
    )

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=dataset,
    )

    trainer.train()
    
    print("Training Done! Exporting to ONNX...")
    # (Simplified Export logic for brevity, ideally use optimum-cli)
    model.save_pretrained("best_model_arabic")
    processor.save_pretrained("best_model_arabic")
    
    print("Success! Now run 'python export_local.py' manually to generate the new model.onnx")

if __name__ == "__main__":
    train()
