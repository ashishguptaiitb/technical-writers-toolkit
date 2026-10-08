#!/usr/bin/env python3
"""
MDX Glossary Term Bank Prototype

Purpose:
    Extract terminology candidates from a handpicked collection of MDX files.

Pipeline:
    1. Recursively find .mdx files.
    2. Clean MDX/Markdown content.
    3. Preserve headings separately.
    4. Extract noun phrases using NLTK POS tagging.
    5. Extract capitalized terms.
    6. Extract acronyms.
    7. Build terminology indexes incrementally while processing files.
    8. Capture source-file and sentence context information.
    9. Write term-bank.csv and term-contexts.csv.

This prototype does NOT:
    - compare against an existing glossary
    - score candidates
    - use an LLM
    - generate definitions

Example:

    python glossary_terms.py --input "C:/Docs/agent-platform-term-bank" --output "C:/Docs/glossary-analysis"
"""

import argparse
import csv
import html
import re
import sys
import time

from collections import Counter, defaultdict
from pathlib import Path


# ============================================================================
# NLTK
# ============================================================================

try:
    import nltk
    from nltk import pos_tag, word_tokenize
    from nltk.corpus import stopwords
except ImportError:
    print("ERROR: NLTK is not installed.")
    print()
    print("Install it with:")
    print("  python -m pip install nltk")
    sys.exit(1)


# ============================================================================
# NLTK RESOURCE CHECKING
# ============================================================================

def resource_available(resource_paths):
    """Return True if at least one NLTK resource path exists."""

    for resource_path in resource_paths:
        try:
            nltk.data.find(resource_path)
            return True
        except LookupError:
            continue

    return False


def ensure_nltk_resources():
    """
    Verify all NLTK datasets required by this script.

    Supports resource names used by both older and newer NLTK versions.
    """

    required = {
        "stopwords": [
            "corpora/stopwords",
            "corpora/stopwords.zip",
        ],

        "punkt": [
            "tokenizers/punkt",
            "tokenizers/punkt.zip",
        ],

        "punkt_tab": [
            "tokenizers/punkt_tab",
            "tokenizers/punkt_tab.zip",
        ],

        "averaged_perceptron_tagger": [
            "taggers/averaged_perceptron_tagger",
            "taggers/averaged_perceptron_tagger.zip",
        ],

        "averaged_perceptron_tagger_eng": [
            "taggers/averaged_perceptron_tagger_eng",
            "taggers/averaged_perceptron_tagger_eng.zip",
        ],
    }

    missing = []

    for package_name, paths in required.items():

        if not resource_available(paths):
            missing.append(package_name)

    if missing:

        print()
        print("ERROR: Required NLTK resources are missing.")
        print()
        print("Missing:")

        for resource in missing:
            print(f"  - {resource}")

        print()
        print("Install them with:")
        print()
        print(
            "python -m nltk.downloader "
            + " ".join(missing)
        )

        sys.exit(1)

    print("NLTK resources: OK")


def load_stopwords():
    """Load English stopwords after resource validation."""

    try:
        return set(stopwords.words("english"))

    except LookupError:

        print()
        print("ERROR: NLTK stopwords could not be loaded.")
        print()
        print(
            "Run: python -m nltk.downloader stopwords"
        )

        sys.exit(1)


# ============================================================================
# MDX CLEANUP
# ============================================================================

def remove_frontmatter(text):
    """Remove YAML frontmatter from the beginning of the document."""

    pattern = r"\A\s*---\s*\n.*?\n---\s*(?:\n|$)"

    return re.sub(
        pattern,
        "",
        text,
        count=1,
        flags=re.DOTALL,
    )


def extract_headings(text):
    """Extract Markdown headings before Markdown cleanup."""

    headings = []

    pattern = (
        r"(?m)^\s{0,3}"
        r"#{1,6}"
        r"\s+"
        r"(.+?)"
        r"\s*#*\s*$"
    )

    for match in re.finditer(pattern, text):

        heading = match.group(1).strip()

        if heading:
            headings.append(heading)

    return headings


def remove_fenced_code(text):
    """Remove fenced code blocks."""

    pattern = (
        r"(?ms)"
        r"^[ \t]*(`{3,}|~{3,})[^\n]*\n"
        r".*?"
        r"^[ \t]*\1[ \t]*$"
    )

    return re.sub(pattern, "", text)


def remove_imports(text):
    """Remove common MDX import/export statements."""

    text = re.sub(
        r"(?m)^\s*import\s+.*?;\s*$",
        "",
        text,
    )

    text = re.sub(
        r"(?m)^\s*import\s+.*?$",
        "",
        text,
    )

    text = re.sub(
        r"(?m)^\s*export\s+.*?;\s*$",
        "",
        text,
    )

    text = re.sub(
        r"(?m)^\s*export\s+.*?$",
        "",
        text,
    )

    return text


def remove_images(text):
    """Remove Markdown images."""

    text = re.sub(
        r"!\[[^\]]*\]\([^)]+\)",
        "",
        text,
    )

    text = re.sub(
        r"!\[[^\]]*\]\[[^\]]*\]",
        "",
        text,
    )

    return text


def remove_urls(text):
    """Remove HTTP and HTTPS URLs."""

    return re.sub(
        r"https?://[^\s<>)]+",
        "",
        text,
    )


def remove_inline_code(text):
    """
    Remove inline code markers while preserving the code text.

    Example:
        `agentId`
        becomes:
        agentId
    """

    return re.sub(
        r"`([^`\n]+)`",
        r"\1",
        text,
    )


def remove_jsx_comments(text):
    """Remove JSX comments."""

    return re.sub(
        r"\{/\*.*?\*/\}",
        "",
        text,
        flags=re.DOTALL,
    )


def remove_jsx_tags(text):
    """
    Remove JSX/HTML tags while preserving visible text.

    Example:

        <Note>
        Important information.
        </Note>

    becomes:

        Important information.
    """

    text = remove_jsx_comments(text)

    return re.sub(
        r"</?[A-Za-z][^>]*?>",
        "",
        text,
    )


def remove_simple_jsx_expressions(text):
    """
    Remove simple JSX expressions.

    This intentionally does not attempt to parse arbitrary JavaScript.
    """

    return re.sub(
        r"\{[^{}\n]+\}",
        "",
        text,
    )


def remove_html_entities(text):
    """Decode HTML entities."""

    return html.unescape(text)


def remove_markdown_links(text):
    """Preserve link text while removing destinations."""

    text = re.sub(
        r"\[([^\]]+)\]\([^)]+\)",
        r"\1",
        text,
    )

    text = re.sub(
        r"\[([^\]]+)\]\[[^\]]*\]",
        r"\1",
        text,
    )

    return text


def clean_table_syntax(text):
    """
    Remove Markdown table separator rows and cell delimiters.

    Table content is retained because tables may contain terminology.
    """

    lines = []

    for line in text.splitlines():

        stripped = line.strip()

        if re.fullmatch(
            r"\|?\s*:?-{2,}:?\s*"
            r"(\|\s*:?-{2,}:?\s*)+\|?",
            stripped,
        ):
            continue

        line = line.replace("|", " ")

        lines.append(line)

    return "\n".join(lines)


def remove_markdown_formatting(text):
    """Remove Markdown formatting markers."""

    text = re.sub(
        r"\*\*\*(.*?)\*\*\*",
        r"\1",
        text,
    )

    text = re.sub(
        r"\*\*(.*?)\*\*",
        r"\1",
        text,
    )

    text = re.sub(
        r"__(.*?)__",
        r"\1",
        text,
    )

    text = re.sub(
        r"(?<!\w)\*(.*?)\*(?!\w)",
        r"\1",
        text,
    )

    text = re.sub(
        r"(?<!\w)_(.*?)_(?!\w)",
        r"\1",
        text,
    )

    text = re.sub(
        r"~~(.*?)~~",
        r"\1",
        text,
    )

    return text


def remove_markdown_structure(text):
    """Remove Markdown structural markers."""

    # Headings.
    text = re.sub(
        r"(?m)^\s{0,3}#{1,6}\s+",
        "",
        text,
    )

    # Blockquotes.
    text = re.sub(
        r"(?m)^\s*>\s?",
        "",
        text,
    )

    # Unordered lists.
    text = re.sub(
        r"(?m)^\s*[-*+]\s+",
        "",
        text,
    )

    # Ordered lists.
    text = re.sub(
        r"(?m)^\s*\d+[.)]\s+",
        "",
        text,
    )

    return text


def normalize_whitespace(text):
    """Normalize whitespace while preserving line boundaries."""

    lines = []

    for line in text.splitlines():

        line = re.sub(
            r"[ \t]+",
            " ",
            line,
        )

        line = line.strip()

        if line:
            lines.append(line)

    return "\n".join(lines)


def clean_mdx(text):
    """
    Execute the MDX cleanup pipeline.

    Returns:
        cleaned_text
        headings
    """

    headings = extract_headings(text)

    text = remove_frontmatter(text)
    text = remove_fenced_code(text)
    text = remove_imports(text)
    text = remove_images(text)
    text = remove_urls(text)
    text = remove_inline_code(text)
    text = remove_jsx_tags(text)
    text = remove_simple_jsx_expressions(text)
    text = remove_html_entities(text)
    text = remove_markdown_links(text)
    text = clean_table_syntax(text)
    text = remove_markdown_formatting(text)
    text = remove_markdown_structure(text)

    text = re.sub(
        r"<[^>]+>",
        "",
        text,
    )

    text = html.unescape(text)

    text = normalize_whitespace(text)

    return text, headings


# ============================================================================
# TERM EXTRACTION
# ============================================================================

GENERIC_TERMS = {
    "example",
    "examples",
    "information",
    "section",
    "page",
    "article",
    "option",
    "options",
    "value",
    "values",
    "field",
    "fields",
    "parameter",
    "parameters",
    "property",
    "properties",
    "request",
    "response",
    "method",
    "methods",
    "type",
    "types",
    "name",
    "names",
    "user",
    "users",
    "system",
    "data",
    "file",
    "files",
    "folder",
    "folders",
    "configuration",
    "settings",
    "content",
    "text",
}


NOUN_PHRASE_TAGS = {
    "NN",
    "NNS",
    "NNP",
    "NNPS",
    "JJ",
    "JJR",
    "JJS",
    "VBG",
}


def normalize_term(term):
    """
    Normalize a term for dictionary/index lookups.

    This function is intentionally simple because it is called
    frequently during extraction.
    """

    term = term.strip()

    term = re.sub(
        r"\s+",
        " ",
        term,
    )

    term = term.strip(
        ".,;:!?()[]{}<>\"'"
    )

    return term.lower()


def is_valid_term(term, stop_words):
    """Apply basic quality filters."""

    if not term:
        return False

    normalized = normalize_term(term)

    if not normalized:
        return False

    words = normalized.split()

    if len(words) == 1:

        word = words[0]

        if word in stop_words:
            return False

        if word in GENERIC_TERMS:
            return False

        if len(word) < 3:
            return False

    if all(
        word in GENERIC_TERMS
        or word in stop_words
        for word in words
    ):
        return False

    if "://" in term:
        return False

    if re.search(
        r"[{}<>=$]",
        term,
    ):
        return False

    return True


def build_phrase(tokens):
    """Build a phrase from POS-tagged tokens."""

    words = [
        word
        for word, _ in tokens
    ]

    phrase = " ".join(words)

    phrase = re.sub(
        r"\s*-\s*",
        "-",
        phrase,
    )

    return phrase.strip()


def extract_noun_phrases(
    text,
    stop_words,
):
    """Extract noun-phrase candidates using NLTK POS tagging."""

    if not text.strip():
        return []

    try:

        tokens = word_tokenize(text)

    except LookupError:

        print()
        print(
            "ERROR: NLTK tokenizer resource is unavailable."
        )
        print(
            "Run: python -m nltk.downloader punkt punkt_tab"
        )

        sys.exit(1)

    if not tokens:
        return []

    try:

        tagged = pos_tag(tokens)

    except LookupError:

        print()
        print(
            "ERROR: NLTK POS tagger resource is unavailable."
        )
        print(
            "Run: python -m nltk.downloader "
            "averaged_perceptron_tagger "
            "averaged_perceptron_tagger_eng"
        )

        sys.exit(1)

    candidates = []

    current = []

    for word, tag in tagged:

        if tag in NOUN_PHRASE_TAGS:

            current.append(
                (word, tag)
            )

            continue

        # Allow hyphens within compound terms.
        if word == "-" and current:

            current.append(
                (word, tag)
            )

            continue

        if current:

            phrase = build_phrase(
                current
            )

            if is_valid_term(
                phrase,
                stop_words,
            ):
                candidates.append(
                    phrase
                )

            current = []

    if current:

        phrase = build_phrase(
            current
        )

        if is_valid_term(
            phrase,
            stop_words,
        ):
            candidates.append(
                phrase
            )

    return candidates


def extract_capitalized_terms(
    text,
    stop_words,
):
    """Extract likely product terminology based on capitalization."""

    candidates = []

    pattern = (
        r"\b"
        r"(?:[A-Z][A-Za-z0-9-]*\s+)"
        r"{1,5}"
        r"[A-Z][A-Za-z0-9-]*"
        r"\b"
    )

    for match in re.finditer(
        pattern,
        text,
    ):

        term = match.group(0).strip()

        if is_valid_term(
            term,
            stop_words,
        ):
            candidates.append(
                term
            )

    return candidates


def extract_acronyms(text):
    """Extract likely acronyms."""

    return re.findall(
        r"\b[A-Z]{2,8}(?:-[A-Z0-9]{1,8})?\b",
        text,
    )


# ============================================================================
# SENTENCE / CONTEXT HANDLING
# ============================================================================

def split_sentences(text):
    """Split text into sentences."""

    if not text.strip():
        return []

    try:

        return nltk.sent_tokenize(text)

    except LookupError:

        # Conservative fallback.
        return re.split(
            r"(?<=[.!?])\s+",
            text,
        )


def build_context_index(
    text,
    extracted_terms,
):
    """
    Build contexts only for terms actually found in the document.

    Returns:

        {
            normalized_term: [context1, context2, ...]
        }
    """

    term_set = {
        normalize_term(term)
        for term in extracted_terms
    }

    context_index = defaultdict(list)

    if not term_set:
        return context_index

    sentences = split_sentences(text)

    for sentence in sentences:

        sentence = sentence.strip()

        if not sentence:
            continue

        normalized_sentence = normalize_term(
            sentence
        )

        # Only check terms occurring in this document.
        for term in term_set:

            if term in normalized_sentence:

                contexts = context_index[
                    term
                ]

                if sentence not in contexts:

                    contexts.append(
                        sentence
                    )

                    # Limit contexts stored per term per file.
                    if len(contexts) >= 5:
                        continue

    return context_index


# ============================================================================
# INCREMENTAL TERM INDEX
# ============================================================================

class TermIndex:
    """
    Global terminology index.

    All information is updated as each MDX file is processed.

    This avoids repeatedly scanning the entire corpus later.
    """

    def __init__(self):

        self.frequency = Counter()

        self.files = defaultdict(set)

        self.types = defaultdict(set)

        self.heading_count = Counter()

        self.variants = defaultdict(Counter)

        self.contexts = defaultdict(
            lambda: defaultdict(list)
        )

    def add_term(
        self,
        term,
        term_type,
        file_name,
    ):
        """Add one extracted term occurrence."""

        normalized = normalize_term(
            term
        )

        if not normalized:
            return

        self.frequency[
            normalized
        ] += 1

        self.files[
            normalized
        ].add(file_name)

        self.types[
            normalized
        ].add(term_type)

        self.variants[
            normalized
        ][term] += 1

    def add_heading_term(
        self,
        term,
    ):
        """Record a heading occurrence."""

        normalized = normalize_term(
            term
        )

        if normalized:
            self.heading_count[
                normalized
            ] += 1

    def add_contexts(
        self,
        term,
        file_name,
        contexts,
    ):
        """Store contexts for a term in one source file."""

        normalized = normalize_term(
            term
        )

        if not normalized:
            return

        target = self.contexts[
            normalized
        ][file_name]

        for context in contexts:

            if context not in target:

                target.append(
                    context
                )

                if len(target) >= 5:
                    break

    def display_term(
        self,
        normalized_term,
    ):
        """Return the most common source representation."""

        variants = self.variants.get(
            normalized_term
        )

        if not variants:
            return normalized_term

        return variants.most_common(
            1
        )[0][0]

    def build_term_rows(self):
        """Build rows for term-bank.csv."""

        rows = []

        for normalized_term, frequency in (
            self.frequency.items()
        ):

            files = sorted(
                self.files[
                    normalized_term
                ]
            )

            rows.append(
                {
                    "Term": self.display_term(
                        normalized_term
                    ),

                    "NormalizedTerm": (
                        normalized_term
                    ),

                    "TermType": "; ".join(
                        sorted(
                            self.types[
                                normalized_term
                            ]
                        )
                    ),

                    "Frequency": frequency,

                    "DocumentCount": len(
                        files
                    ),

                    "HeadingCount": (
                        self.heading_count.get(
                            normalized_term,
                            0,
                        )
                    ),

                    "SourceFiles": (
                        "; ".join(files)
                    ),
                }
            )

        rows.sort(
            key=lambda row: (
                -row["DocumentCount"],
                -row["Frequency"],
                -row["HeadingCount"],
                row["Term"].lower(),
            )
        )

        return rows

    def build_context_rows(self):
        """Build rows for term-contexts.csv."""

        rows = []

        for normalized_term in self.frequency:

            display_term = self.display_term(
                normalized_term
            )

            file_contexts = self.contexts.get(
                normalized_term,
                {},
            )

            for file_name in sorted(
                file_contexts
            ):

                contexts = file_contexts[
                    file_name
                ]

                occurrence_count = (
                    self._count_term_in_file(
                        normalized_term,
                        file_name,
                    )
                )

                for context in contexts:

                    rows.append(
                        {
                            "Term": display_term,

                            "MDXFile": file_name,

                            "OccurrenceCount": (
                                occurrence_count
                            ),

                            "Context": context,
                        }
                    )

        return rows

    def _count_term_in_file(
        self,
        normalized_term,
        file_name,
    ):
        """
        Return an approximate occurrence count based on
        extracted-term occurrences for the source file.

        This avoids rereading MDX files.
        """

        # We don't maintain per-file occurrence counts separately
        # in this first prototype, so use the number of contexts
        # as the safe diagnostic value.
        contexts = self.contexts.get(
            normalized_term,
            {},
        ).get(
            file_name,
            [],
        )

        return len(contexts)


# ============================================================================
# FILE PROCESSING
# ============================================================================

def process_file(
    file_path,
    input_root,
    cleaned_root,
    stop_words,
    term_index,
):
    """Process one MDX file."""

    try:

        text = file_path.read_text(
            encoding="utf-8",
            errors="replace",
        )

    except Exception as exc:

        print()
        print(
            f"WARNING: Could not read "
            f"{file_path}: {exc}"
        )

        return False

    cleaned_text, headings = clean_mdx(
        text
    )

    relative_path = file_path.relative_to(
        input_root
    )

    relative_name = str(
        relative_path
    ).replace("\\", "/")

    cleaned_path = (
        cleaned_root
        / relative_path.with_suffix(
            ".txt"
        )
    )

    cleaned_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    try:

        cleaned_path.write_text(
            cleaned_text,
            encoding="utf-8",
        )

    except Exception as exc:

        print()
        print(
            f"WARNING: Could not write "
            f"{cleaned_path}: {exc}"
        )

    # ---------------------------------------------------------------
    # Extract terminology.
    # ---------------------------------------------------------------

    noun_phrases = extract_noun_phrases(
        cleaned_text,
        stop_words,
    )

    capitalized_terms = (
        extract_capitalized_terms(
            cleaned_text,
            stop_words,
        )
    )

    acronyms = extract_acronyms(
        cleaned_text
    )

    heading_terms = []

    for heading in headings:

        heading_terms.extend(
            extract_noun_phrases(
                heading,
                stop_words,
            )
        )

        heading_terms.extend(
            extract_capitalized_terms(
                heading,
                stop_words,
            )
        )

    # ---------------------------------------------------------------
    # Add all extracted terms to global index.
    # ---------------------------------------------------------------

    for term in noun_phrases:

        term_index.add_term(
            term,
            "noun_phrase",
            relative_name,
        )

    for term in capitalized_terms:

        term_index.add_term(
            term,
            "capitalized_term",
            relative_name,
        )

    for term in acronyms:

        term_index.add_term(
            term,
            "acronym",
            relative_name,
        )

    for term in heading_terms:

        term_index.add_heading_term(
            term
        )

    # ---------------------------------------------------------------
    # Build context index for terms in this document only.
    # ---------------------------------------------------------------

    all_terms = (
        noun_phrases
        + capitalized_terms
        + acronyms
        + heading_terms
    )

    # Remove duplicates while retaining representation.
    unique_terms = {}

    for term in all_terms:

        normalized = normalize_term(
            term
        )

        if normalized:

            unique_terms[
                normalized
            ] = term

    context_index = build_context_index(
        cleaned_text,
        unique_terms.values(),
    )

    for normalized_term, contexts in (
        context_index.items()
    ):

        term_index.add_contexts(
            normalized_term,
            relative_name,
            contexts,
        )

    return True


# ============================================================================
# CSV OUTPUT
# ============================================================================

def write_csv(
    path,
    rows,
    fieldnames,
):
    """Write UTF-8 CSV with BOM."""

    try:

        with path.open(
            "w",
            encoding="utf-8-sig",
            newline="",
        ) as handle:

            writer = csv.DictWriter(
                handle,
                fieldnames=fieldnames,
            )

            writer.writeheader()

            writer.writerows(rows)

    except Exception as exc:

        print()
        print(
            f"ERROR: Could not write "
            f"{path}: {exc}"
        )

        sys.exit(1)


# ============================================================================
# MAIN
# ============================================================================

def main():

    parser = argparse.ArgumentParser(
        description=(
            "Extract a terminology bank from "
            "a selected MDX documentation corpus."
        )
    )

    parser.add_argument(
        "--input",
        required=True,
        help=(
            "Root folder containing the "
            "handpicked MDX files."
        ),
    )

    parser.add_argument(
        "--output",
        required=True,
        help=(
            "Folder where reports and "
            "cleaned text will be written."
        ),
    )

    args = parser.parse_args()

    input_root = Path(
        args.input
    ).expanduser().resolve()

    output_root = Path(
        args.output
    ).expanduser().resolve()

    # ---------------------------------------------------------------
    # Validate paths.
    # ---------------------------------------------------------------

    if not input_root.exists():

        print(
            f"ERROR: Input folder does not exist:\n"
            f"  {input_root}"
        )

        sys.exit(1)

    if not input_root.is_dir():

        print(
            f"ERROR: Input path is not a folder:\n"
            f"  {input_root}"
        )

        sys.exit(1)

    try:

        output_root.mkdir(
            parents=True,
            exist_ok=True,
        )

    except Exception as exc:

        print(
            f"ERROR: Could not create output folder:\n"
            f"  {output_root}\n"
            f"  {exc}"
        )

        sys.exit(1)

    cleaned_root = (
        output_root
        / "cleaned-text"
    )

    cleaned_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    # ---------------------------------------------------------------
    # Header.
    # ---------------------------------------------------------------

    print()
    print(
        "MDX Glossary Term Bank Prototype"
    )
    print(
        "================================="
    )
    print(
        f"Input : {input_root}"
    )
    print(
        f"Output: {output_root}"
    )
    print()

    # ---------------------------------------------------------------
    # NLTK.
    # ---------------------------------------------------------------

    ensure_nltk_resources()

    stop_words = load_stopwords()

    print(
        f"English stopwords loaded: "
        f"{len(stop_words)}"
    )

    # ---------------------------------------------------------------
    # Discover files.
    # ---------------------------------------------------------------

    print()
    print(
        "Discovering MDX files..."
    )

    mdx_files = sorted(
        input_root.rglob("*.mdx")
    )

    if not mdx_files:

        print()
        print(
            "ERROR: No .mdx files were found."
        )

        sys.exit(1)

    print(
        f"MDX files found: "
        f"{len(mdx_files)}"
    )

    # ---------------------------------------------------------------
    # Initialize global index.
    # ---------------------------------------------------------------

    term_index = TermIndex()

    # ---------------------------------------------------------------
    # Process files.
    # ---------------------------------------------------------------

    print()
    print(
        "Stage 1/3: Cleaning and extracting terms"
    )
    print()

    start_time = time.perf_counter()

    successful = 0
    failed = 0

    total_files = len(
        mdx_files
    )

    for index, file_path in enumerate(
        mdx_files,
        start=1,
    ):

        success = process_file(
            file_path,
            input_root,
            cleaned_root,
            stop_words,
            term_index,
        )

        if success:
            successful += 1
        else:
            failed += 1

        percent = int(
            index
            / total_files
            * 100
        )

        bar_length = 40

        filled = int(
            bar_length
            * index
            / total_files
        )

        bar = (
            "#"
            * filled
            + "-"
            * (
                bar_length
                - filled
            )
        )

        print(
            f"\r[{bar}] "
            f"{percent:3d}% "
            f"{index}/{total_files} "
            f"{file_path.name:<45}",
            end="",
            flush=True,
        )

    elapsed = (
        time.perf_counter()
        - start_time
    )

    print()
    print()

    print(
        f"Files processed : {successful}"
    )

    print(
        f"Files failed    : {failed}"
    )

    print(
        f"Extraction time : {elapsed:.1f} seconds"
    )

    print(
        f"Unique terms    : {len(term_index.frequency):,}"
    )

    # ---------------------------------------------------------------
    # Build term bank.
    # ---------------------------------------------------------------

    print()
    print(
        "Stage 2/3: Building term-bank report"
    )

    start_time = time.perf_counter()

    term_rows = (
        term_index.build_term_rows()
    )

    term_elapsed = (
        time.perf_counter()
        - start_time
    )

    print(
        f"Terms written: "
        f"{len(term_rows):,}"
    )

    print(
        f"Report preparation time: "
        f"{term_elapsed:.1f} seconds"
    )

    # ---------------------------------------------------------------
    # Build context report.
    # ---------------------------------------------------------------

    print()
    print(
        "Stage 3/3: Building context report"
    )

    start_time = time.perf_counter()

    context_rows = (
        term_index.build_context_rows()
    )

    context_elapsed = (
        time.perf_counter()
        - start_time
    )

    print(
        f"Context records: "
        f"{len(context_rows):,}"
    )

    print(
        f"Context preparation time: "
        f"{context_elapsed:.1f} seconds"
    )

    # ---------------------------------------------------------------
    # Write CSVs.
    # ---------------------------------------------------------------

    term_bank_path = (
        output_root
        / "term-bank.csv"
    )

    context_path = (
        output_root
        / "term-contexts.csv"
    )

    write_csv(
        term_bank_path,
        term_rows,
        [
            "Term",
            "NormalizedTerm",
            "TermType",
            "Frequency",
            "DocumentCount",
            "HeadingCount",
            "SourceFiles",
        ],
    )

    write_csv(
        context_path,
        context_rows,
        [
            "Term",
            "MDXFile",
            "OccurrenceCount",
            "Context",
        ],
    )

    # ---------------------------------------------------------------
    # Final report.
    # ---------------------------------------------------------------

    print()
    print(
        "Completed successfully."
    )
    print()
    print(
        f"MDX files processed : "
        f"{successful}"
    )
    print(
        f"Unique terms        : "
        f"{len(term_rows):,}"
    )
    print(
        f"Context records     : "
        f"{len(context_rows):,}"
    )
    print()
    print(
        f"Term bank           : "
        f"{term_bank_path}"
    )
    print(
        f"Term contexts       : "
        f"{context_path}"
    )
    print(
        f"Cleaned text        : "
        f"{cleaned_root}"
    )
    print()


if __name__ == "__main__":
    main()