#!/usr/bin/env python3
"""
Split Dresden Files Collection 7-12 EPUB into individual books.
This anthology has a different structure than 1-6 - files are directly in OEBPS with prefixes.
"""

import zipfile
import os
import shutil
from pathlib import Path
from xml.etree import ElementTree as ET

# Define the 6 books and their component prefixes
BOOKS = [
    {"name": "Dead Beat", "prefix": "001", "filename": "Jim Butcher - Dead Beat.epub"},
    {"name": "Proven Guilty", "prefix": "002", "filename": "Jim Butcher - Proven Guilty.epub"},
    {"name": "White Night", "prefix": "003", "filename": "Jim Butcher - White Night.epub"},
    {"name": "Small Favor", "prefix": "004", "filename": "Jim Butcher - Small Favor.epub"},
    {"name": "Turn Coat", "prefix": "005", "filename": "Jim Butcher - Turn Coat.epub"},
    {"name": "Changes", "prefix": "006", "filename": "Jim Butcher - Changes.epub"},
]

# Namespaces for EPUB XML files
NS = {
    'opf': 'http://www.idpf.org/2007/opf',
    'dc': 'http://purl.org/dc/elements/1.1/',
    'ncx': 'http://www.daisy.org/z3986/2005/ncx/'
}

def extract_epub(epub_path, extract_dir):
    """Extract EPUB to directory."""
    print(f"Extracting {epub_path}...")
    with zipfile.ZipFile(epub_path, 'r') as zip_ref:
        zip_ref.extractall(extract_dir)

def create_book_epub(source_dir, output_path, book_info):
    """Create individual book EPUB from extracted anthology."""
    prefix = book_info['prefix']
    book_name = book_info['name']
    
    print(f"\nCreating {book_name}...")
    
    # Create temporary directory for this book
    temp_dir = f"/tmp/epub_book_{prefix}"
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_dir)
    
    # Copy base structure
    shutil.copy(os.path.join(source_dir, 'mimetype'), temp_dir)
    shutil.copytree(os.path.join(source_dir, 'META-INF'), os.path.join(temp_dir, 'META-INF'))
    
    # Create OEBPS directory
    oebps_dir = os.path.join(temp_dir, 'OEBPS')
    os.makedirs(oebps_dir)
    
    # Copy book-specific files from OEBPS
    source_oebps = os.path.join(source_dir, 'OEBPS')
    
    # Copy files that start with the prefix
    file_count = 0
    for item in os.listdir(source_oebps):
        item_path = os.path.join(source_oebps, item)
        
        # Copy if it starts with our prefix
        if item.startswith(f'{prefix}_'):
            dest_path = os.path.join(oebps_dir, item)
            if os.path.isfile(item_path):
                shutil.copy2(item_path, dest_path)
                file_count += 1
            elif os.path.isdir(item_path):
                shutil.copytree(item_path, dest_path)
                file_count += len([f for f in os.listdir(dest_path)])
    
    print(f"  Copied {file_count} files/items")
    
    # Parse and filter content.opf
    create_filtered_opf(source_dir, oebps_dir, prefix, book_name)
    
    # Create filtered toc.ncx
    create_filtered_ncx(source_dir, oebps_dir, prefix, book_name)
    
    # Create the EPUB file
    create_epub_file(temp_dir, output_path)
    
    # Cleanup
    shutil.rmtree(temp_dir)
    print(f"  Created: {output_path}")

def create_filtered_opf(source_dir, oebps_dir, prefix, book_name):
    """Create filtered content.opf for individual book."""
    tree = ET.parse(os.path.join(source_dir, 'OEBPS', 'content.opf'))
    root = tree.getroot()
    
    # Update metadata
    for title in root.findall('.//dc:title', NS):
        title.text = book_name
    
    # Filter manifest items
    manifest = root.find('.//opf:manifest', NS)
    items_to_remove = []
    for item in manifest.findall('.//opf:item', NS):
        item_id = item.get('id')
        href = item.get('href', '')
        # Keep only items for this book (x{prefix}_* or {prefix}_*) or common items
        if item_id and item_id.startswith('x') and not item_id.startswith(f'x{prefix}_'):
            items_to_remove.append(item)
        elif href and href.startswith(('001_', '002_', '003_', '004_', '005_', '006_')) and not href.startswith(f'{prefix}_'):
            items_to_remove.append(item)
    
    for item in items_to_remove:
        manifest.remove(item)
    
    # Filter spine itemrefs
    spine = root.find('.//opf:spine', NS)
    itemrefs_to_remove = []
    for itemref in spine.findall('.//opf:itemref', NS):
        idref = itemref.get('idref')
        # Keep only itemrefs for this book
        if idref and idref.startswith('x') and not idref.startswith(f'x{prefix}_'):
            itemrefs_to_remove.append(itemref)
    
    for itemref in itemrefs_to_remove:
        spine.remove(itemref)
    
    # Write filtered OPF
    tree.write(os.path.join(oebps_dir, 'content.opf'), encoding='utf-8', xml_declaration=True)

def create_filtered_ncx(source_dir, oebps_dir, prefix, book_name):
    """Create filtered toc.ncx for individual book."""
    ncx_path = os.path.join(source_dir, 'OEBPS', 'toc.ncx')
    if not os.path.exists(ncx_path):
        return

    tree = ET.parse(ncx_path)
    root = tree.getroot()

    # Update title
    for title in root.findall('.//ncx:docTitle/ncx:text', NS):
        title.text = book_name

    # Filter navMap - only keep top-level navpoints for this book
    navmap = root.find('.//ncx:navMap', NS)
    if navmap is not None:
        navpoints_to_remove = []
        # Only look at direct children of navMap
        for navpoint in list(navmap):
            if navpoint.tag == f'{{{NS["ncx"]}}}navPoint':
                content = navpoint.find('.//ncx:content', NS)
                if content is not None:
                    src = content.get('src', '')
                    # Keep only navpoints for this book
                    if not src.startswith(f'{prefix}_') and src.startswith(('001_', '002_', '003_', '004_', '005_', '006_')):
                        navpoints_to_remove.append(navpoint)

        for navpoint in navpoints_to_remove:
            navmap.remove(navpoint)

    # Write filtered NCX
    tree.write(os.path.join(oebps_dir, 'toc.ncx'), encoding='utf-8', xml_declaration=True)

def create_epub_file(source_dir, output_path):
    """Create EPUB file from directory."""
    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as epub:
        # Add mimetype first (uncompressed)
        epub.write(os.path.join(source_dir, 'mimetype'), 'mimetype', compress_type=zipfile.ZIP_STORED)

        # Add all other files
        for root, dirs, files in os.walk(source_dir):
            for file in files:
                if file == 'mimetype':
                    continue
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, source_dir)
                epub.write(file_path, arcname)

def main():
    source_epub = '/mnt/boston/media/books/Jim Butcher/Jim Butcher - The Dresden Files Collection 7-12  (epub).epub'
    output_dir = '/mnt/boston/media/books/Jim Butcher'
    extract_dir = '/tmp/epub_extract_7_12'

    # Extract the anthology
    if os.path.exists(extract_dir):
        shutil.rmtree(extract_dir)
    extract_epub(source_epub, extract_dir)

    # Create each individual book
    for book in BOOKS:
        output_path = os.path.join(output_dir, book['filename'])
        create_book_epub(extract_dir, output_path, book)

    print(f"\n✓ Successfully split into {len(BOOKS)} individual books!")
    print(f"  Output directory: {output_dir}")

if __name__ == '__main__':
    main()

