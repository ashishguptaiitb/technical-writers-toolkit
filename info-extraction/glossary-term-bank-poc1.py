#!/usr/bin/env python3
"""
MDX Glossary Term Bank Prototype

Usage:
python glossary_terms.py --input path --output path

Purpose:
    Extract terminology candidates from a handpicked collection of MDX files.

Processing:
    1. Recursively find .mdx files.
    2. Remove MDX/Markdown noise while preserving useful prose.
    3. Preserve headings separately.
    4. Use NLTK POS tagging to identify noun-phrase candidates.
    5. Extract capitalized terms and acronyms.
    6. Aggregate terms across files.
    7. Capture source context for each term.

Outputs:
    term-bank.csv
    term-contexts.csv
    cleaned-text/<relative-path>.txt

This prototype does NOT:
    - compare against an existing glossary
    - score candidates
    - use an LLM
    - generate glossary definitions

Example:
    python glossary_terms.py --input "C:/Docs/agent-platform-term-bank" --output "C:/Docs/glossary-analysis"
"""

import argparse
import csv
import html
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


# ---------------------------------------------------------------------------
# NLTK imports
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# NLTK resource handling
# ---------------------------------------------------------------------------

def resource_available(resource_paths):
    """
    Return True if any of the supplied NLTK resource paths exists.

    NLTK has changed some resource names across versions, so this
    function allows us to support both older and newer layouts.
    """

    for resource_path in resource_paths:
        try:
            nltk.data.find(resource_path)
            return True
        except LookupError:
            continue

    return False


def ensure_nltk_resources():
    """
    Verify that all NLTK datasets required by this script are available.

    This function does not automatically download resources. It reports
    exactly what is missing so the user can install them explicitly.
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

    for package_name, resource_paths in required.items():
        if not resource_available(resource_paths):
            missing.append(package_name)

    if missing:
        print("ERROR: One or more required NLTK resources are missing.")
        print()
        print("Missing resources:")

        for resource in missing:
            print(f"  - {resource}")

        print()
        print("Install them with:")
        print()
        print(
            "python -m nltk.downloader "
            + " ".join(missing)
        )
        print()

        sys.exit(1)

    print("NLTK resources: OK")


def load_stopwords():
    """
    Load English stopwords after resource validation.
    """

    try:
        return set(stopwords.words("english"))
    except LookupError:
        print("ERROR: NLTK stopwords could not be loaded.")
        print()
        print("Run:")
        print("  python -m nltk.downloader stopwords")
        sys.exit(1)


# ---------------------------------------------------------------------------
# MDX preprocessing
# ---------------------------------------------------------------------------

def remove_frontmatter(text):
    """
    Remove YAML frontmatter only when it appears at the beginning
    of the document.
    """

    pattern = r"\A\s*---\s*\n.*?\n---\s*(?:\n|$)"

    return re.sub(
        pattern,
        "",
        text,
        count=1,
        flags=re.DOTALL,
    )


def extract_headings(text):
    """
    Extract Markdown headings before Markdown cleanup.

    Returns a list of heading texts.
    """

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
    """
    Remove fenced code blocks.

    Supports:
        ```
        ```javascript
        ~~~
        ~~~yaml
    """

    pattern = (
        r"(?ms)"
        r"^[ \t]*(`{3,}|~{3,})[^\n]*\n"
        r".*?"
        r"^[ \t]*\1[ \t]*$"
    )

    return re.sub(pattern, "", text)


def remove_imports(text):
    """
    Remove common MDX import/export statements.
    """

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
    """
    Remove Markdown images completely.

    Examples:
        ![alt](image.png)
        ![alt](https://example.com/image.png)
        ![alt][image-reference]
    """

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
    """
    Remove HTTP/HTTPS URLs.
    """

    return re.sub(
        r"https?://[^\s<>)]+",
        "",
        text,
    )


def remove_inline_code(text):
    """
    Remove inline code markers while retaining the visible code text.

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
    """
    Remove JSX comments.
    """

    return re.sub(
        r"\{/\*.*?\*/\}",
        "",
        text,
        flags=re.DOTALL,
    )


def remove_jsx_tags(text):
    """
    Remove JSX and HTML tags while preserving text between tags.

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


def remove_jsx_expressions(text):
    """
    Remove simple JSX expressions such as:

        {variable}
        {condition && <Component />}

    This is intentionally conservative.

    We avoid trying to parse arbitrary JavaScript.
    """

    # Remove simple one-line expressions.
    text = re.sub(
        r"\{[^{}\n]+\}",
        "",
        text,
    )

    return text


def remove_html_entities(text):
    """
    Decode HTML entities such as:
        &amp;
        &lt;
        &quot;
    """

    return html.unescape(text)


def remove_markdown_links(text):
    """
    Preserve Markdown link text but remove its destination.
    """

    # Inline links.
    text = re.sub(
        r"\[([^\]]+)\]\([^)]+\)",
        r"\1",
        text,
    )

    # Reference-style links.
    text = re.sub(
        r"\[([^\]]+)\]\[[^\]]*\]",
        r"\1",
        text,
    )

    return text


def clean_table_syntax(text):
    """
    Remove Markdown table separator rows and cell delimiters.

    Table content itself is retained because it can contain
    useful terminology.
    """

    lines = []

    for line in text.splitlines():

        stripped = line.strip()

        # Example:
        # | --- | --- |
        # | :--- | ---: |
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
    """
    Remove Markdown formatting markers while retaining visible text.
    """

    # Bold + italic.
    text = re.sub(
        r"\*\*\*(.*?)\*\*\*",
        r"\1",
        text,
    )

    # Bold.
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

    # Italic.
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

    # Strikethrough.
    text = re.sub(
        r"~~(.*?)~~",
        r"\1",
        text,
    )

    return text


def remove_markdown_structure(text):
    """
    Remove Markdown structural markers while retaining visible content.
    """

    # Heading markers.
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
    """
    Normalize whitespace while preserving line boundaries.
    """

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
    Execute the complete MDX cleanup pipeline.

    Returns:
        cleaned_text
        headings
    """

    # Extract headings before removing Markdown structure.
    headings = extract_headings(text)

    text = remove_frontmatter(text)
    text = remove_fenced_code(text)
    text = remove_imports(text)
    text = remove_images(text)
    text = remove_urls(text)
    text = remove_inline_code(text)
    text = remove_jsx_tags(text)
    text = remove_jsx_expressions(text)
    text = remove_html_entities(text)
    text = remove_markdown_links(text)
    text = clean_table_syntax(text)
    text = remove_markdown_formatting(text)
    text = remove_markdown_structure(text)

    # Remove any remaining obvious HTML tags.
    text = re.sub(
        r"<[^>]+>",
        "",
        text,
    )

    text = html.unescape(text)

    text = normalize_whitespace(text)

    return text, headings


# ---------------------------------------------------------------------------
# Linguistic processing
# ---------------------------------------------------------------------------

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
    Normalize a candidate term for comparison and aggregation.
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
    """
    Apply basic quality filters to a candidate term.
    """

    if not term:
        return False

    normalized = normalize_term(term)

    if not normalized:
        return False

    words = normalized.split()

    # Reject single-word stopwords.
    if len(words) == 1:

        word = words[0]

        if word in stop_words:
            return False

        if word in GENERIC_TERMS:
            return False

        if len(word) < 3:
            return False

    # Reject phrases containing only generic/stop words.
    if all(
        word in GENERIC_TERMS or word in stop_words
        for word in words
    ):
        return False

    # Reject obvious syntax.
    if "://" in term:
        return False

    if re.search(
        r"[{}<>=$]",
        term,
    ):
        return False

    return True


def build_phrase(tokens):
    """
    Build a clean phrase from POS-tagged tokens.
    """

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


def extract_noun_phrases(text, stop_words):
    """
    Extract noun-phrase candidates using NLTK POS tagging.

    This intentionally uses transparent POS patterns rather than
    a black-box semantic model.
    """

    if not text.strip():
        return []

    try:
        tokens = word_tokenize(text)
    except LookupError as exc:
        print()
        print("ERROR: NLTK tokenizer resource is unavailable.")
        print(str(exc))
        print()
        print(
            "Run: python -m nltk.downloader "
            "punkt punkt_tab"
        )
        sys.exit(1)

    if not tokens:
        return []

    try:
        tagged = pos_tag(tokens)
    except LookupError as exc:
        print()
        print("ERROR: NLTK POS tagger resource is unavailable.")
        print(str(exc))
        print()
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

            phrase = build_phrase(current)

            if is_valid_term(
                phrase,
                stop_words,
            ):
                candidates.append(phrase)

            current = []

    # Flush final phrase.
    if current:

        phrase = build_phrase(current)

        if is_valid_term(
            phrase,
            stop_words,
        ):
            candidates.append(phrase)

    return candidates


def extract_capitalized_terms(text, stop_words):
    """
    Extract likely product terms based on capitalization.

    Example:
        Agent Runtime
        Model Context Protocol
    """

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
            candidates.append(term)

    return candidates


def extract_acronyms(text):
    """
    Extract likely acronyms such as API, SDK, NLP, and LLM.
    """

    candidates = []

    for match in re.finditer(
        r"\b[A-Z]{2,8}(?:-[A-Z0-9]{1,8})?\b",
        text,
    ):

        candidates.append(
            match.group(0)
        )

    return candidates


# ---------------------------------------------------------------------------
# Context extraction
# ---------------------------------------------------------------------------

def split_sentences(text):
    """
    Split cleaned text into sentences.
    """

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


def find_term_contexts(
    term,
    text,
    max_contexts=5,
):
    """
    Find sentences containing a term.

    Returns at most max_contexts unique sentences for a term
    within a single source file.
    """

    contexts = []

    normalized_term = normalize_term(term)

    for sentence in split_sentences(text):

        if normalized_term in normalize_term(sentence):

            sentence = sentence.strip()

            if (
                sentence
                and sentence not in contexts
            ):
                contexts.append(sentence)

        if len(contexts) >= max_contexts:
            break

    return contexts


# ---------------------------------------------------------------------------
# File processing
# ---------------------------------------------------------------------------

def process_file(
    file_path,
    input_root,
    cleaned_root,
    stop_words,
):
    """
    Read, clean, and extract terminology from one MDX file.
    """

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

        return None

    cleaned_text, headings = clean_mdx(
        text
    )

    relative_path = file_path.relative_to(
        input_root
    )

    cleaned_path = (
        cleaned_root
        / relative_path.with_suffix(".txt")
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
            f"WARNING: Could not write cleaned "
            f"file {cleaned_path}: {exc}"
        )

    noun_phrases = extract_noun_phrases(
        cleaned_text,
        stop_words,
    )

    capitalized_terms = extract_capitalized_terms(
        cleaned_text,
        stop_words,
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

    return {
        "file": str(
            relative_path
        ).replace("\\", "/"),

        "cleaned_text": cleaned_text,

        "headings": headings,

        "noun_phrases": noun_phrases,

        "capitalized_terms": capitalized_terms,

        "acronyms": acronyms,

        "heading_terms": heading_terms,
    }


# ---------------------------------------------------------------------------
# Term-bank generation
# ---------------------------------------------------------------------------

def get_display_term(
    normalized_term,
    results,
):
    """
    Recover the most common readable capitalization/formatting
    for a normalized term.
    """

    variants = Counter()

    for result in results:

        all_terms = (
            result["noun_phrases"]
            + result["capitalized_terms"]
            + result["acronyms"]
            + result["heading_terms"]
        )

        for term in all_terms:

            if (
                normalize_term(term)
                == normalized_term
            ):
                variants[term] += 1

    if variants:
        return variants.most_common(1)[0][0]

    return normalized_term


def build_term_bank(results):
    """
    Aggregate terminology across the complete corpus.
    """

    term_occurrences = Counter()

    term_files = defaultdict(set)

    term_types = defaultdict(set)

    term_heading_counts = Counter()

    for result in results:

        file_name = result["file"]

        term_sources = [
            (
                "noun_phrase",
                result["noun_phrases"],
            ),
            (
                "capitalized_term",
                result["capitalized_terms"],
            ),
            (
                "acronym",
                result["acronyms"],
            ),
        ]

        for term_type, terms in term_sources:

            for term in terms:

                normalized = normalize_term(
                    term
                )

                if not normalized:
                    continue

                term_occurrences[
                    normalized
                ] += 1

                term_files[
                    normalized
                ].add(file_name)

                term_types[
                    normalized
                ].add(term_type)

        for term in result["heading_terms"]:

            normalized = normalize_term(
                term
            )

            if normalized:

                term_heading_counts[
                    normalized
                ] += 1

    rows = []

    for normalized_term, frequency in (
        term_occurrences.items()
    ):

        files = sorted(
            term_files[
                normalized_term
            ]
        )

        display_term = get_display_term(
            normalized_term,
            results,
        )

        rows.append(
            {
                "Term": display_term,
                "NormalizedTerm": normalized_term,
                "TermType": "; ".join(
                    sorted(
                        term_types[
                            normalized_term
                        ]
                    )
                ),
                "Frequency": frequency,
                "DocumentCount": len(files),
                "HeadingCount": (
                    term_heading_counts.get(
                        normalized_term,
                        0,
                    )
                ),
                "SourceFiles": "; ".join(
                    files
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


def build_context_rows(
    results,
    term_rows,
):
    """
    Build term + source file + context records.
    """

    rows = []

    for term_row in term_rows:

        term = term_row["Term"]

        normalized_term = normalize_term(
            term
        )

        for result in results:

            all_terms = (
                result["noun_phrases"]
                + result["capitalized_terms"]
                + result["acronyms"]
                + result["heading_terms"]
            )

            matching_count = sum(
                1
                for candidate in all_terms
                if normalize_term(candidate)
                == normalized_term
            )

            if matching_count == 0:
                continue

            contexts = find_term_contexts(
                term,
                result["cleaned_text"],
                max_contexts=5,
            )

            for context in contexts:

                rows.append(
                    {
                        "Term": term,
                        "MDXFile": result["file"],
                        "OccurrenceCount": (
                            matching_count
                        ),
                        "Context": context,
                    }
                )

    return rows


# ---------------------------------------------------------------------------
# CSV output
# ---------------------------------------------------------------------------

def write_csv(
    path,
    rows,
    fieldnames,
):
    """
    Write UTF-8 CSV with BOM for convenient Excel handling.
    """

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
            f"ERROR: Could not write CSV "
            f"{path}: {exc}"
        )

        sys.exit(1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

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

    try:

        cleaned_root.mkdir(
            parents=True,
            exist_ok=True,
        )

    except Exception as exc:

        print(
            f"ERROR: Could not create cleaned-text folder:\n"
            f"  {cleaned_root}\n"
            f"  {exc}"
        )

        sys.exit(1)

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

    # Validate NLTK before loading stopwords.
    ensure_nltk_resources()

    stop_words = load_stopwords()

    print(
        f"English stopwords loaded: "
        f"{len(stop_words)}"
    )

    # Find MDX files recursively.
    mdx_files = sorted(
        input_root.rglob("*.mdx")
    )

    if not mdx_files:

        print()
        print(
            "ERROR: No .mdx files were found "
            "under the input folder."
        )

        sys.exit(1)

    print(
        f"MDX files found: "
        f"{len(mdx_files)}"
    )
    print()

    results = []

    for index, file_path in enumerate(
        mdx_files,
        start=1,
    ):

        percent = int(
            index
            / len(mdx_files)
            * 100
        )

        bar_length = 40

        filled = int(
            bar_length
            * index
            / len(mdx_files)
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
            f"{file_path.name:<50}",
            end="",
            flush=True,
        )

        result = process_file(
            file_path,
            input_root,
            cleaned_root,
            stop_words,
        )

        if result:
            results.append(result)

    print()
    print()

    if not results:

        print(
            "ERROR: No MDX files could be processed."
        )

        sys.exit(1)

    print(
        "Building term bank..."
    )

    term_rows = build_term_bank(
        results
    )

    print(
        "Building term contexts..."
    )

    context_rows = build_context_rows(
        results,
        term_rows,
    )

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

    print()
    print(
        "Completed successfully."
    )
    print()
    print(
        f"MDX files processed : "
        f"{len(results)}"
    )
    print(
        f"Terms extracted     : "
        f"{len(term_rows)}"
    )
    print(
        f"Context records     : "
        f"{len(context_rows)}"
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