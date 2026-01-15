#!/usr/bin/env python3
"""
Generic script to split anthology EPUBs into individual books based on NCX navigation.
"""

import os
import sys
import zipfile
import shutil
import tempfile
from xml.etree import ElementTree as ET
from pathlib import Path

NS = {
    'opf': 'http://www.idpf.org/2007/opf',
    'dc': 'http://purl.org/dc/elements/1.1/',
    'ncx': 'http://www.daisy.org/z3986/2005/ncx/'
}

def extract_epub(epub_path, extract_dir):
    """Extract EPUB to directory."""
    with zipfile.ZipFile(epub_path, 'r') as epub:
        epub.extractall(extract_dir)
    print(f"Extracted to {extract_dir}")

def get_book_sections(ncx_path, book_configs):
    """
    Parse NCX and identify which navPoints belong to which books.
    book_configs is a list of dicts with 'title' and 'navpoint_index' (1-based)
    """
    tree = ET.parse(ncx_path)
    root = tree.getroot()
    
    navmap = root.find('.//ncx:navMap', NS)
    navpoints = list(navmap)
    
    books = []
    
    for i, config in enumerate(book_configs):
        nav_idx = config['navpoint_index'] - 1  # Convert to 0-based
        
        if nav_idx >= len(navpoints):
            print(f"Warning: navpoint index {config['navpoint_index']} out of range")
            continue
        
        nav = navpoints[nav_idx]
        label = nav.find('.//ncx:navLabel/ncx:text', NS)
        content = nav.find('.//ncx:content', NS)
        
        if label is None or content is None:
            continue
        
        # Get all content files for this book
        content_files = set()
        start_file = content.get('src').split('#')[0]
        content_files.add(start_file)
        
        # Get all sub-navpoints
        for sub_nav in nav.findall('.//ncx:navPoint', NS):
            sub_content = sub_nav.find('.//ncx:content', NS)
            if sub_content is not None:
                src = sub_content.get('src').split('#')[0]
                content_files.add(src)
        
        books.append({
            'title': config.get('output_title', label.text),
            'author': config.get('author', 'Unknown'),
            'navpoint': nav,
            'navpoint_index': nav_idx,
            'content_files': content_files
        })
    
    return books

def get_spine_items_for_book(opf_path, content_files):
    """Get spine item IDs that correspond to the content files."""
    tree = ET.parse(opf_path)
    root = tree.getroot()
    
    # Build manifest: id -> href mapping
    manifest = root.find('.//opf:manifest', NS)
    manifest_map = {}
    for item in manifest.findall('.//opf:item', NS):
        item_id = item.get('id')
        href = item.get('href')
        manifest_map[item_id] = href
    
    # Find spine items that match our content files
    spine = root.find('.//opf:spine', NS)
    spine_ids = []
    
    for itemref in spine.findall('.//opf:itemref', NS):
        idref = itemref.get('idref')
        if idref in manifest_map:
            href = manifest_map[idref]
            if href in content_files:
                spine_ids.append(idref)
    
    return spine_ids

def create_individual_epub(source_dir, book_info, output_path):
    """Create an individual EPUB for one book."""
    temp_dir = tempfile.mkdtemp()
    
    try:
        # Create EPUB structure
        oebps_dir = os.path.join(temp_dir, 'OEBPS')
        os.makedirs(oebps_dir)
        
        source_oebps = os.path.join(source_dir, 'OEBPS')
        
        # Copy content files
        files_copied = set()
        for content_file in book_info['content_files']:
            src = os.path.join(source_oebps, content_file)
            dst = os.path.join(oebps_dir, content_file)
            
            if os.path.exists(src):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
                files_copied.add(content_file)

        # Copy CSS and other resources
        for item in os.listdir(source_oebps):
            item_path = os.path.join(source_oebps, item)
            if os.path.isfile(item_path) and (item.endswith('.css') or item.endswith(('.jpg', '.png', '.gif', '.svg'))):
                shutil.copy2(item_path, os.path.join(oebps_dir, item))
                files_copied.add(item)

        print(f"  Copied {len(files_copied)} files")

        # Create/modify content.opf
        opf_source = os.path.join(source_oebps, 'content.opf')
        tree = ET.parse(opf_source)
        root = tree.getroot()

        # Update metadata
        for title_elem in root.findall('.//dc:title', NS):
            title_elem.text = book_info['title']

        for creator in root.findall('.//dc:creator', NS):
            creator.text = book_info['author']

        # Filter manifest
        manifest = root.find('.//opf:manifest', NS)
        items_to_remove = []
        for item in manifest.findall('.//opf:item', NS):
            href = item.get('href', '')
            media_type = item.get('media-type', '')

            # Keep NCX file and files we copied
            if media_type == 'application/x-dtbncx+xml' or 'ncx' in href.lower():
                continue

            if href and href not in files_copied:
                items_to_remove.append(item)

        for item in items_to_remove:
            manifest.remove(item)

        # Ensure NCX is in manifest (add if missing)
        ncx_exists = False
        for item in manifest.findall('.//opf:item', NS):
            if item.get('media-type') == 'application/x-dtbncx+xml':
                ncx_exists = True
                break

        if not ncx_exists:
            ncx_item = ET.SubElement(manifest, '{http://www.idpf.org/2007/opf}item')
            ncx_item.set('id', 'toc.ncx')
            ncx_item.set('href', 'toc.ncx')
            ncx_item.set('media-type', 'application/x-dtbncx+xml')

        # Filter spine
        spine_ids = get_spine_items_for_book(opf_source, book_info['content_files'])
        spine = root.find('.//opf:spine', NS)
        itemrefs_to_remove = []
        for itemref in spine.findall('.//opf:itemref', NS):
            idref = itemref.get('idref')
            if idref not in spine_ids:
                itemrefs_to_remove.append(itemref)

        for itemref in itemrefs_to_remove:
            spine.remove(itemref)

        # Save content.opf
        tree.write(os.path.join(oebps_dir, 'content.opf'), encoding='utf-8', xml_declaration=True)

        # Create simplified toc.ncx with just this book
        ncx_tree = ET.Element('ncx', xmlns='http://www.daisy.org/z3986/2005/ncx/', version='2005-1')
        head = ET.SubElement(ncx_tree, 'head')
        doc_title = ET.SubElement(ncx_tree, 'docTitle')
        text = ET.SubElement(doc_title, 'text')
        text.text = book_info['title']

        navmap = ET.SubElement(ncx_tree, 'navMap')
        navmap.append(book_info['navpoint'])

        ncx_out = ET.ElementTree(ncx_tree)
        ncx_out.write(os.path.join(oebps_dir, 'toc.ncx'), encoding='utf-8', xml_declaration=True)

        # Create META-INF/container.xml
        metainf_dir = os.path.join(temp_dir, 'META-INF')
        os.makedirs(metainf_dir)

        container_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
   <rootfiles>
      <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
   </rootfiles>
</container>'''
        with open(os.path.join(metainf_dir, 'container.xml'), 'w', encoding='utf-8') as f:
            f.write(container_xml)

        # Create mimetype
        with open(os.path.join(temp_dir, 'mimetype'), 'w', encoding='utf-8') as f:
            f.write('application/epub+zip')

        # Create EPUB
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as epub_out:
            # Add mimetype first (uncompressed)
            epub_out.write(os.path.join(temp_dir, 'mimetype'), 'mimetype', compress_type=zipfile.ZIP_STORED)

            # Add everything else
            for root_dir, dirs, files in os.walk(temp_dir):
                for file in files:
                    if file == 'mimetype':
                        continue
                    file_path = os.path.join(root_dir, file)
                    arcname = os.path.relpath(file_path, temp_dir)
                    epub_out.write(file_path, arcname)

        print(f"  Created: {output_path}")

    finally:
        shutil.rmtree(temp_dir)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 split_anthology_by_ncx.py <config_name>")
        print("Available configs: foundation, throne_of_glass, crescent_city, hitchhiker")
        sys.exit(1)

    config_name = sys.argv[1]

    # Configuration for each anthology
    configs = {
        'foundation': {
            'epub_path': '/mnt/boston/media/books/Isaac Asimov/The Foundation Trilogy (251)/The Foundation Trilogy - Isaac Asimov.epub',
            'output_dir': '/mnt/boston/media/books_staging/EPUBs/Foundation',
            'author': 'Isaac Asimov',
            'books': [
                {'navpoint_index': 5, 'output_title': 'Foundation'},
                {'navpoint_index': 6, 'output_title': 'Foundation and Empire'},
                {'navpoint_index': 7, 'output_title': 'Second Foundation'},
            ]
        },
        'throne_of_glass': {
            'epub_path': '/mnt/boston/media/books/Sarah J. Maas/Throne of Glass (Anthology) (231)/Throne of Glass (Anthology) - Sarah J. Maas.epub',
            'output_dir': '/mnt/boston/media/books_staging/EPUBs/Throne_of_Glass',
            'author': 'Sarah J. Maas',
            'books': [
                {'navpoint_index': 4, 'output_title': 'Throne of Glass'},
                {'navpoint_index': 5, 'output_title': 'Crown of Midnight'},
                {'navpoint_index': 6, 'output_title': 'Heir of Fire'},
                {'navpoint_index': 7, 'output_title': 'Queen of Shadows'},
                {'navpoint_index': 8, 'output_title': 'Empire of Storms'},
                {'navpoint_index': 9, 'output_title': 'Tower of Dawn'},
                {'navpoint_index': 10, 'output_title': 'Kingdom of Ash'},
                {'navpoint_index': 11, 'output_title': "Assassin's Blade"},
            ]
        },
        'crescent_city': {
            'epub_path': '/mnt/boston/media/books/Sarah J. Maas/Crescent City (Anthology) (262)/Crescent City (Anthology) - Sarah J. Maas.epub',
            'output_dir': '/mnt/boston/media/books_staging/EPUBs/Crescent_City',
            'author': 'Sarah J. Maas',
            'books': [
                {'navpoint_index': 3, 'output_title': 'House of Earth and Blood'},
                {'navpoint_index': 4, 'output_title': 'House of Sky and Breath'},
            ]
        },
        'hitchhiker': {
            'epub_path': "/mnt/boston/media/books/Unknown/The Hitchhiker's Guide to the Galax (268)/The Hitchhiker's Guide to the G - Unknown.epub",
            'output_dir': "/mnt/boston/media/books_staging/EPUBs/Hitchhikers_Guide",
            'author': 'Douglas Adams',
            'books': [
                {'navpoint_index': 6, 'output_title': "The Hitchhiker's Guide to the Galaxy"},
                {'navpoint_index': 7, 'output_title': 'The Restaurant at the End of the Universe'},
                {'navpoint_index': 8, 'output_title': 'Life, the Universe and Everything'},
                {'navpoint_index': 9, 'output_title': 'So Long, and Thanks for All the Fish'},
                {'navpoint_index': 10, 'output_title': 'Young Zaphod Plays It Safe'},
                {'navpoint_index': 11, 'output_title': 'Mostly Harmless'},
            ]
        }
    }

    if config_name not in configs:
        print(f"Unknown config: {config_name}")
        print(f"Available configs: {', '.join(configs.keys())}")
        sys.exit(1)

    config = configs[config_name]

    # Add author to each book config
    for book in config['books']:
        book['author'] = config['author']

    print(f"Splitting: {os.path.basename(config['epub_path'])}")
    print(f"Output: {config['output_dir']}")
    print()

    # Extract EPUB
    extract_dir = tempfile.mkdtemp()
    try:
        extract_epub(config['epub_path'], extract_dir)

        # Get book sections
        ncx_path = os.path.join(extract_dir, 'OEBPS', 'toc.ncx')
        books = get_book_sections(ncx_path, config['books'])

        print(f"\nFound {len(books)} books to extract\n")

        # Create each book
        for book in books:
            print(f"Creating: {book['title']}")
            output_filename = f"{book['author']} - {book['title']}.epub"
            output_path = os.path.join(config['output_dir'], output_filename)

            create_individual_epub(extract_dir, book, output_path)

        print(f"\n✓ Successfully split into {len(books)} individual books!")
        print(f"  Output directory: {config['output_dir']}")

    finally:
        shutil.rmtree(extract_dir)


