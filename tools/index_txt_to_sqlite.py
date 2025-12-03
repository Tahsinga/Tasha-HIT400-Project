#!/usr/bin/env python3
"""
index_txt_to_sqlite.py

Simple terminal tool to split a text file into small chunks and insert them into
an SQLite database that follows the `VectorDB` schema used by the Flutter app.

This script does NOT compute embeddings. It inserts rows into the `chunks`
table only (and leaves `embeddings` empty). This allows testing the indexing
and retrieval logic from the app using text-only fallback.

Usage:
  python tools/index_txt_to_sqlite.py --txt assets/txt_books/edliz 2020.txt --db ./test_rag_vectors.db --book "edliz 2020" --chunk-size 500 --overlap 50

Arguments:
  --txt PATH       Path to the input text file to index.
  --db PATH        Path to the sqlite DB file to create/append (default: ./rag_vectors.db)
  --book NAME      Book id/name to store in `chunks.book` (default: basename of txt file)
  --chunk-size N   Target chunk size in WORDS (not chars). Default: 500 words per chunk.
  --overlap N      Overlap between chunks in WORDS. Default: 50 words.

Note: Chunking is word-based for efficiency. 
      Recommended: chunk-size=500-1000 words, overlap=50-100 words.
      For fast testing: chunk-size=100, overlap=10.
"""

import argparse
import os
import sqlite3
import sys
from pathlib import Path


def ensure_schema(conn: sqlite3.Connection):
    c = conn.cursor()
    # Create minimal tables needed: chunks and embeddings
    c.execute('''
    CREATE TABLE IF NOT EXISTS chunks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book TEXT,
      start_page INTEGER,
      end_page INTEGER,
      text TEXT
    );
    ''')
    c.execute('''
    CREATE TABLE IF NOT EXISTS embeddings (
      chunk_id INTEGER PRIMARY KEY,
      embedding BLOB
    );
    ''')
    conn.commit()


def chunk_text(text: str, chunk_size: int, overlap: int):
    """
    Split text into chunks by WORDS sequentially (NO overlap to avoid duplication).
    chunk_size = number of words per chunk (simple, predictable)
    This is the fastest and most straightforward approach.
    """
    if chunk_size <= 0:
        raise ValueError('chunk_size must be > 0')
    
    # Split into words
    words = text.split()
    if not words:
        return []
    
    print(f'  Text has {len(words)} words. Creating chunks of {chunk_size} words (no overlap)...', flush=True)
    
    chunks = []
    for i in range(0, len(words), chunk_size):
        end = min(i + chunk_size, len(words))
        chunk_words = words[i:end]
        chunk_text = ' '.join(chunk_words)
        if chunk_text.strip():
            chunks.append((i, end, chunk_text))
        
        # Print progress every 50 chunks
        if len(chunks) % 50 == 0:
            pct = int(100 * end / len(words))
            print(f'    Progress: {len(chunks)} chunks, {pct}% done...', flush=True)
    
    print(f'  Created {len(chunks)} chunks total.', flush=True)
    return chunks



def insert_chunks(conn: sqlite3.Connection, book: str, chunks):
    c = conn.cursor()
    inserted = 0
    total = len(chunks)
    print(f'  Inserting {total} chunks into DB...', flush=True)
    for i, (start, end, chunk) in enumerate(chunks):
        # Using start_page/end_page placeholders (1-based chunk index)
        sp = i + 1
        ep = sp
        c.execute('INSERT INTO chunks (book, start_page, end_page, text) VALUES (?, ?, ?, ?)', (book, sp, ep, chunk))
        inserted += 1
        # Print progress every 10% and commit in batches to avoid memory buildup
        if (i + 1) % max(1, total // 10) == 0:
            pct = int(100 * (i + 1) / total)
            print(f'    Inserted {i + 1}/{total} ({pct}%)...', flush=True)
            conn.commit()  # Commit batch to prevent huge transaction
    conn.commit()
    print(f'  Completed: inserted {inserted} chunks.', flush=True)
    return inserted


def main():
    p = argparse.ArgumentParser(description='Index a txt file into an sqlite DB (chunks only)')
    p.add_argument('--txt', required=True, help='Path to txt file')
    p.add_argument('--db', default='rag_vectors.db', help='Path to sqlite DB file')
    p.add_argument('--book', default=None, help='Book id/name to use in DB')
    p.add_argument('--chunk-size', type=int, default=800, help='Target chunk size (chars)')
    p.add_argument('--overlap', type=int, default=120, help='Overlap between chunks (chars)')

    args = p.parse_args()

    txt_path = Path(args.txt)
    if not txt_path.exists():
        print(f'ERROR: txt file not found: {txt_path}', file=sys.stderr)
        sys.exit(2)

    book = args.book or txt_path.stem
    db_path = Path(args.db)

    print(f'Indexing {txt_path} -> {db_path} as book="{book}" chunk_size={args.chunk_size} overlap={args.overlap}')
    print('Step 1: Reading text file...')
    text = txt_path.read_text(encoding='utf-8', errors='ignore')
    if not text.strip():
        print('ERROR: input text is empty', file=sys.stderr)
        sys.exit(3)
    print(f'  Read {len(text)} characters.')

    print('Step 2: Creating chunks...')
    chunks = chunk_text(text, args.chunk_size, args.overlap)
    print(f'Generated {len(chunks)} chunks (approx).')

    print('Step 3: Opening/creating database...')
    conn = sqlite3.connect(str(db_path))
    try:
        print('  Ensuring schema...')
        ensure_schema(conn)
        print('Step 4: Inserting chunks...')
        inserted = insert_chunks(conn, book, chunks)
        print(f'\n✓ Success! Inserted {inserted} chunks into {db_path}')
    except Exception as e:
        print(f'\nERROR during insertion: {e}', file=sys.stderr)
        sys.exit(4)
    finally:
        conn.close()

if __name__ == '__main__':
    main()
