import os
import pytesseract
import pandas as pd
from PIL import Image, ImageOps

IMAGE_ROOT = "C:/Users/Ashish.Gupta/Documents/GitHub/agent-platform-stage/docs/xo/administration/"
WORD_LIST_FILE = "C:/Users/Ashish.Gupta/Documents/GitHub/agent-platform-stage/docs/words-to-rebrand-for-inception.txt"
OUTPUT_CSV = "ocr-matches-using-python.csv"

with open(WORD_LIST_FILE, "r", encoding="utf-8") as f:
    words = [w.strip().lower() for w in f if w.strip()]

rows = []

for root, _, files in os.walk(IMAGE_ROOT):
    for name in files:
        if not name.lower().endswith((".png", ".jpg", ".jpeg", ".gif")):
            continue

        full_path = os.path.join(root, name)
        rel_path = os.path.relpath(full_path, IMAGE_ROOT)

        img = Image.open(full_path)
        img = ImageOps.grayscale(img)
        img = img.resize((img.width * 2, img.height * 2))

        data = pytesseract.image_to_data(
            img,
            output_type=pytesseract.Output.DATAFRAME
        )

        data = data.dropna(subset=["text"])

        for _, row in data.iterrows():
            text = str(row["text"]).lower()
            conf = row["conf"]

            for word in words:
                if word in text:
                    rows.append({
                        "ImagePath": rel_path,
                        "Match": word,
                        "OCRText": row["text"],
                        "Confidence": conf
                    })

df = pd.DataFrame(rows)
df.to_csv(OUTPUT_CSV, index=False, encoding="utf-8")
