import os
import fitz  # PyMuPDF
import glob

# Paths
SOURCE_DIRS = [
    r"C:\Users\jihad\Documents\invoices",
    r"C:\Users\jihad\Documents\فواتير_PDF_2025-12-13_17-23"
]
TARGET_DIR = r"training_data"

# Ensure target exists
os.makedirs(TARGET_DIR, exist_ok=True)

def convert_pdfs():
    count = 0
    limit = 20 # Limit to 20 images for now to start small
    
    print(f"Starting conversion...")
    
    for folder in SOURCE_DIRS:
        # Find PDFs
        pdfs = glob.glob(os.path.join(folder, "*.pdf"))
        print(f"Found {len(pdfs)} PDFs in {folder}")
        
        for pdf_path in pdfs:
            if count >= limit:
                break
                
            try:
                # Open PDF
                doc = fitz.open(pdf_path)
                if len(doc) < 1:
                    continue
                    
                # Load First Page
                page = doc.load_page(0)
                
                # Render to Image (Zoom=2 for better quality)
                mat = fitz.Matrix(2, 2)
                pix = page.get_pixmap(matrix=mat)
                
                # Save
                filename = os.path.basename(pdf_path).replace(".pdf", ".png")
                save_path = os.path.join(TARGET_DIR, filename)
                pix.save(save_path)
                
                print(f"✅ Converted: {filename}")
                count += 1
                
            except Exception as e:
                print(f"❌ Failed {pdf_path}: {e}")
        
        if count >= limit:
            break

    print(f"Done! Converted {count} images to '{TARGET_DIR}'.")

if __name__ == "__main__":
    convert_pdfs()
