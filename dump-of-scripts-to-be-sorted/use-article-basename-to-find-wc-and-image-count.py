import os
import csv
import re

def audit_markdown_files(list_file_path, search_directory, output_csv):
    # 1. Clean paths to remove accidental quotes from copy-pasting
    list_file_path = list_file_path.strip('"').strip("'")
    search_directory = search_directory.strip('"').strip("'")
    output_csv = output_csv.strip('"').strip("'")

    img_tag_pattern = re.compile(r'<img [^>]*src=["\']([^"\']+)["\']', re.IGNORECASE)
    
    # 2. Load the partial names to search for
    with open(list_file_path, 'r', encoding='utf-8') as f:
        partial_names = [line.strip() for line in f if line.strip()]

    results = []

    # 3. Recursive Search using os.walk
    # This creates a "map" of every file in every subfolder
    all_md_files = []
    for root, dirs, files in os.walk(search_directory):
        for file in files:
            if file.endswith('.md'):
                # Store the absolute path so we can open it later
                all_md_files.append(os.path.join(root, file))

    # 4. Match and Analyze
    for partial in partial_names:
        # Find the first file path where the partial name exists in the filename
        match_path = next((path for path in all_md_files if partial in os.path.basename(path)), None)
        
        if match_path:
            try:
                with open(match_path, 'r', encoding='utf-8') as md_file:
                    content = md_file.read()
                    word_count = len(content.split())
                    image_count = len(img_tag_pattern.findall(content))
                    
                    results.append([match_path, word_count, image_count])
            except Exception as e:
                print(f"Error reading {match_path}: {e}")
        else:
            print(f"Warning: No file found containing '{partial}' in any subfolder.")

    # 5. Write to CSV
    with open(output_csv, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['File Path', 'Word Count', 'Image Count'])
        writer.writerows(results)

    print(f"\nSuccess! Audit complete. Results saved to: {output_csv}")

# --- RUN SCRIPT ---
if __name__ == "__main__":
    print("--- Markdown Recursive Auditor ---")
    list_txt = input("Paste path to your .txt list: ")
    search_dir = input("Paste the root folder path to search: ")
    out_file = input("Enter output CSV name (e.g., results.csv): ")
    
    audit_markdown_files(list_txt, search_dir, out_file)