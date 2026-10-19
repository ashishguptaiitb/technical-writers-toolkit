#!/usr/bin/env python3
"""
Markdown Duplicate Content Detection Script
Finds pairs of Markdown files with >20% overlapping content. Can configure this overlap percentage.

usage: duplicate_content_detection.py [-h] [--threshold THRESHOLD] [--method {basic,shingle}] [--output OUTPUT]
                                      [--shingle-size SHINGLE_SIZE]
                                      repo_path

positional arguments:
  repo_path             Path to the repository

options:
  -h, --help            show this help message and exit
  --threshold, -t THRESHOLD
                        Similarity threshold (0.0-1.0, default: 0.2)
  --method, -m {basic,shingle}
                        Detection method (default: basic)
  --output, -o OUTPUT   Path of the output report file
  --shingle-size SHINGLE_SIZE
                        Shingle size for shingle method (default: 5)
"""

import os
import re
import hashlib
from pathlib import Path
from collections import defaultdict
from difflib import SequenceMatcher
import argparse
from typing import List, Tuple, Dict

class MarkdownDeduplicator:
    def __init__(self, repo_path: str, similarity_threshold: float = 0.2):
        self.repo_path = Path(repo_path)
        self.similarity_threshold = similarity_threshold
        
    def extract_content(self, file_path: Path) -> str:
        """Extract meaningful content from Markdown file, excluding metadata"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError:
            with open(file_path, 'r', encoding='latin-1') as f:
                content = f.read()
        
        # Remove YAML frontmatter
        content = re.sub(r'^---\s*\n.*?\n---\s*\n', '', content, flags=re.MULTILINE | re.DOTALL)
        
        # Remove HTML comments
        content = re.sub(r'<!--.*?-->', '', content, flags=re.DOTALL)
        
        # Remove code blocks (keep inline code)
        content = re.sub(r'```.*?```', '', content, flags=re.DOTALL)
        
        # Remove images and links but keep alt text and link text
        content = re.sub(r'!\[([^\]]*)\]\([^\)]*\)', r'\1', content)  # Images
        content = re.sub(r'\[([^\]]*)\]\([^\)]*\)', r'\1', content)   # Links
        
        # Remove Markdown formatting
        content = re.sub(r'[#*_`]', '', content)
        
        # Normalize whitespace
        content = re.sub(r'\s+', ' ', content).strip()
        
        return content.lower()
    
    def get_markdown_files(self) -> List[Path]:
        """Find all Markdown files in the repository"""
        md_files = []
        for ext in ['*.md', '*.markdown']:
            md_files.extend(self.repo_path.rglob(ext))
        return md_files
    
    def calculate_similarity(self, content1: str, content2: str) -> float:
        """Calculate similarity ratio between two content strings"""
        return SequenceMatcher(None, content1, content2).ratio()
    
    def find_duplicate_pairs(self) -> List[Tuple[Path, Path, float]]:
        """Find pairs of files with similarity above threshold"""
        md_files = self.get_markdown_files()
        duplicates = []
        
        print(f"Analyzing {len(md_files)} Markdown files...")
        
        # Compare each file with every other file
        for i, file1 in enumerate(md_files):
            if i % 10 == 0:
                print(f"Progress: {i}/{len(md_files)} files processed")
                
            content1 = self.extract_content(file1)
            if len(content1) < 10:  # Skip very short files
                continue
                
            for file2 in md_files[i+1:]:
                content2 = self.extract_content(file2)
                if len(content2) < 10:  # Skip very short files
                    continue
                    
                similarity = self.calculate_similarity(content1, content2)
                
                if similarity >= self.similarity_threshold:
                    duplicates.append((file1, file2, similarity))
        
        return sorted(duplicates, key=lambda x: x[2], reverse=True)

    def find_near_duplicates_with_shingling(self, shingle_size: int = 5) -> List[Tuple[Path, Path, float]]:
        """More advanced duplicate detection using shingling technique"""
        md_files = self.get_markdown_files()
        file_shingles = {}
        
        print(f"Creating shingles for {len(md_files)} files...")
        
        # Create shingles for each file
        for file_path in md_files:
            content = self.extract_content(file_path)
            words = content.split()
            
            if len(words) < shingle_size:
                continue
                
            shingles = set()
            for i in range(len(words) - shingle_size + 1):
                shingle = ' '.join(words[i:i+shingle_size])
                shingle_hash = hashlib.md5(shingle.encode()).hexdigest()
                shingles.add(shingle_hash)
            
            file_shingles[file_path] = shingles
        
        # Compare shingle sets
        duplicates = []
        file_list = list(file_shingles.keys())
        
        for i, file1 in enumerate(file_list):
            if i % 10 == 0:
                print(f"Comparing: {i}/{len(file_list)} files processed")
                
            shingles1 = file_shingles[file1]
            
            for file2 in file_list[i+1:]:
                shingles2 = file_shingles[file2]
                
                if not shingles1 or not shingles2:
                    continue
                
                # Jaccard similarity
                intersection = len(shingles1.intersection(shingles2))
                union = len(shingles1.union(shingles2))
                similarity = intersection / union if union > 0 else 0
                
                if similarity >= self.similarity_threshold:
                    duplicates.append((file1, file2, similarity))
        
        return sorted(duplicates, key=lambda x: x[2], reverse=True)

    def analyze_content_overlap(self, file1: Path, file2: Path) -> Dict:
        """Detailed analysis of what content overlaps between two files"""
        content1 = self.extract_content(file1)
        content2 = self.extract_content(file2)
        
        # Find common sentences
        sentences1 = [s.strip() for s in content1.split('.') if len(s.strip()) > 20]
        sentences2 = [s.strip() for s in content2.split('.') if len(s.strip()) > 20]
        
        common_sentences = []
        for s1 in sentences1:
            for s2 in sentences2:
                similarity = SequenceMatcher(None, s1, s2).ratio()
                if similarity > 0.8:  # Very similar sentences
                    common_sentences.append((s1, s2, similarity))
        
        return {
            'file1_length': len(content1.split()),
            'file2_length': len(content2.split()),
            'common_sentences_count': len(common_sentences),
            'common_sentences': common_sentences[:5],  # Show top 5
            'overlap_percentage': len(common_sentences) / min(len(sentences1), len(sentences2)) * 100 if sentences1 and sentences2 else 0
        }

    def generate_report(self, duplicates: List[Tuple[Path, Path, float]], output_file: str = None):
        """Generate a detailed report of duplicate content"""
        report_lines = [
            "# Duplicate Content Analysis Report",
            f"\nFound {len(duplicates)} pairs of files with >{self.similarity_threshold*100}% similarity\n",
            "## Summary by Similarity Level",
        ]
        
        # Categorize by similarity level
        high_similarity = [d for d in duplicates if d[2] >= 0.7]
        medium_similarity = [d for d in duplicates if 0.4 <= d[2] < 0.7]
        low_similarity = [d for d in duplicates if d[2] < 0.4]
        
        report_lines.extend([
            f"- High similarity (70%+): {len(high_similarity)} pairs",
            f"- Medium similarity (40-69%): {len(medium_similarity)} pairs", 
            f"- Low similarity (20-39%): {len(low_similarity)} pairs",
            "\n## Detailed Results\n"
        ])
        
        for file1, file2, similarity in duplicates:
            rel_path1 = file1.relative_to(self.repo_path)
            rel_path2 = file2.relative_to(self.repo_path)
            
            report_lines.extend([
                f"### Similarity: {similarity:.1%}",
                f"- **File 1:** `{rel_path1}`",
                f"- **File 2:** `{rel_path2}`",
            ])
            
            # Add detailed overlap analysis
            overlap_analysis = self.analyze_content_overlap(file1, file2)
            report_lines.extend([
                f"- **File 1 length:** {overlap_analysis['file1_length']} words",
                f"- **File 2 length:** {overlap_analysis['file2_length']} words",
                f"- **Common sentences:** {overlap_analysis['common_sentences_count']}",
                f"- **Estimated overlap:** {overlap_analysis['overlap_percentage']:.1f}%",
                ""
            ])
        
        report_content = '\n'.join(report_lines)
        
        if output_file:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(report_content)
            print(f"Report saved to: {output_file}")
        else:
            print(report_content)


def main():
    parser = argparse.ArgumentParser(description='Find duplicate content in Markdown files')
    parser.add_argument('repo_path', help='Path to the repository')
    parser.add_argument('--threshold', '-t', type=float, default=0.2, 
                       help='Similarity threshold (0.0-1.0, default: 0.2)')
    parser.add_argument('--method', '-m', choices=['basic', 'shingle'], default='basic',
                       help='Detection method (default: basic)')
    parser.add_argument('--output', '-o', help='Output report file')
    parser.add_argument('--shingle-size', type=int, default=5,
                       help='Shingle size for shingle method (default: 5)')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.repo_path):
        print(f"Error: Repository path '{args.repo_path}' does not exist")
        return 1
    
    deduplicator = MarkdownDeduplicator(args.repo_path, args.threshold)
    
    print(f"Searching for duplicate content with {args.threshold:.0%} similarity threshold...")
    print(f"Using {args.method} method")
    
    if args.method == 'basic':
        duplicates = deduplicator.find_duplicate_pairs()
    else:
        duplicates = deduplicator.find_near_duplicates_with_shingling(args.shingle_size)
    
    if duplicates:
        print(f"\nFound {len(duplicates)} pairs of similar files:")
        deduplicator.generate_report(duplicates, args.output)
    else:
        print("No duplicate content found above the threshold.")
    
    return 0


if __name__ == "__main__":
    exit(main())
