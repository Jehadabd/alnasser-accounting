import os
print("Starting Model Export...")

try:
    from optimum.onnxruntime import ORTModelForTokenClassification
    from transformers import LayoutLMv3Processor
except ImportError:
    print("Error: Libraries not installed. Please run 'pip install optimum[onnxruntime] transformers'")
    exit(1)

# Exporting LOCALLY trained model
MODEL_ID = "best_model_arabic"
OUTPUT_DIR = "assets/models/exported_onnx"
FINAL_MODEL = "assets/models/model.onnx"

print(f"Loading local model from: {MODEL_ID} ...")
model = ORTModelForTokenClassification.from_pretrained(MODEL_ID, export=True)
processor = LayoutLMv3Processor.from_pretrained(MODEL_ID, apply_ocr=False) # Important: apply_ocr=False

print(f"Exporting to ONNX at {OUTPUT_DIR} ...")
model.save_pretrained(OUTPUT_DIR)
processor.save_pretrained(OUTPUT_DIR)

# Rename/Move for simplicity
import shutil
if os.path.exists(f"{OUTPUT_DIR}/model.onnx"):
    if not os.path.exists("assets/models"):
        os.makedirs("assets/models")
    shutil.copy(f"{OUTPUT_DIR}/model.onnx", FINAL_MODEL)
    print(f"✅ SUCCESS: Model saved to {FINAL_MODEL}")
else:
    print("❌ ERROR: ONNX file not found after export.")
