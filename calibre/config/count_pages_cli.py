#!/usr/bin/env python3
"""
Compute page and word counts for a Calibre book using Count Pages plugin algorithms.

Usage (inside container):
    calibre-debug -e /config/count_pages_cli.py <book_id>

Prints structured output consumed by the watcher script:
    BOOK_PAGES=249
    BOOK_WORDS=95672

The watcher then writes these to the library via calibredb set_custom (GUI-connected),
so Calibre's UI updates immediately without a restart or manual refresh.
"""

import sys
import os


def main():
    if len(sys.argv) < 2:
        print("Usage: calibre-debug -e /config/count_pages_cli.py <book_id>")
        sys.exit(1)

    book_id = int(sys.argv[1])
    library_path = '/config/library'

    from calibre.db.cache import Cache
    from calibre.db.backend import DB

    db = DB(library_path)
    cache = Cache(db)
    cache.init()

    formats = cache.formats(book_id)
    if not formats:
        print(f"ERROR: No formats found for book ID {book_id}", file=sys.stderr)
        sys.exit(1)

    print(f"Book {book_id} formats: {formats}", file=sys.stderr)

    # Prefer EPUB, then PDF, then MOBI
    book_path = None
    for fmt in ['EPUB', 'PDF', 'MOBI']:
        if fmt in formats:
            book_path = cache.format_abspath(book_id, fmt)
            break

    db.close()

    if not book_path:
        print(f"ERROR: No supported format (EPUB/PDF/MOBI) found for book {book_id}", file=sys.stderr)
        sys.exit(1)

    print(f"Processing: {book_path}", file=sys.stderr)
    ext = os.path.splitext(book_path)[1].lower()

    from calibre_plugins.count_pages.statistics import get_page_count, get_word_count
    from calibre.ebooks.oeb.iterator.book import EbookIterator

    word_count = None
    page_count = None

    try:
        if ext == '.epub':
            iterator = EbookIterator(book_path)
            iterator.__enter__(only_input_plugin=True, run_char_count=True, read_anchor_map=False)

            # Word count
            iterator, word_count = get_word_count(iterator, book_path, False)

            # Page count — algorithm 2 = Adobe Digital Editions (ADE)
            iterator, page_count = get_page_count(iterator, book_path, 2, 0)

            iterator.__exit__(None, None, None)

        elif ext == '.pdf':
            from calibre_plugins.count_pages.statistics import get_pdf_page_count
            page_count = get_pdf_page_count(book_path)

        else:
            print(f"Unsupported format: {ext} — skipping count", file=sys.stderr)

        # Print machine-readable values on stdout for the watcher to parse
        if page_count is not None:
            print(f"BOOK_PAGES={int(page_count)}")
        if word_count is not None:
            print(f"BOOK_WORDS={word_count}")

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
