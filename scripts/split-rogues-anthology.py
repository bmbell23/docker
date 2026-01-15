#!/usr/bin/env python3
"""
Split Rogues anthology EPUB into individual stories.
Each story has a col (collection intro) file and a chapter file.
"""

import zipfile
import os
import shutil
from pathlib import Path
from xml.etree import ElementTree as ET

# Define the 21 stories with their file prefixes
STORIES = [
    {"title": "Tough Times All Over", "author": "Joe Abercrombie", "col": "col1", "chapter": "c01"},
    {"title": "What Do You Do", "author": "Gillian Flynn", "col": "col2", "chapter": "c02"},
    {"title": "The Inn of the Seven Blessings", "author": "Matthew Hughes", "col": "col3", "chapter": "c03"},
    {"title": "Bent Twig", "author": "Joe R. Lansdale", "col": "col4", "chapter": "c04"},
    {"title": "Tawny Petticoats", "author": "Michael Swanwick", "col": "col5", "chapter": "c05"},
    {"title": "Provenance", "author": "David W. Ball", "col": "col6", "chapter": "c06"},
    {"title": "Roaring Twenties", "author": "Carrie Vaughn", "col": "col7", "chapter": "c07"},
    {"title": "A Year and a Day in Old Theradane", "author": "Scott Lynch", "col": "col8", "chapter": "c08"},
    {"title": "Bad Brass", "author": "Bradley Denton", "col": "col9", "chapter": "c09"},
    {"title": "Heavy Metal", "author": "Cherie Priest", "col": "col10", "chapter": "c10"},
    {"title": "The Meaning of Love", "author": "Daniel Abraham", "col": "col11", "chapter": "c11"},
    {"title": "A Better Way to Die", "author": "Paul Cornell", "col": "col12", "chapter": "c12"},
    {"title": "Ill Seen in Tyre", "author": "Steven Saylor", "col": "col13", "chapter": "c13"},
    {"title": "A Cargo of Ivories", "author": "Garth Nix", "col": "col14", "chapter": "c14"},
    {"title": "Diamonds from Tequila", "author": "Walter Jon Williams", "col": "col15", "chapter": "c15"},
    {"title": "The Caravan to Nowhere", "author": "Phyllis Eisenstein", "col": "col16", "chapter": "c16"},
    {"title": "The Curious Affair of the Dead Wives", "author": "Lisa Tuttle", "col": "col17", "chapter": "c17"},
    {"title": "How the Marquis Got His Coat Back", "author": "Neil Gaiman", "col": "col18", "chapter": "c18"},
    {"title": "Now Showing", "author": "Connie Willis", "col": "col19", "chapter": "c19"},
    {"title": "The Lightning Tree", "author": "Patrick Rothfuss", "col": "col20", "chapter": "c20"},
    {"title": "The Rogue Prince, or, A King's Brother", "author": "George R. R. Martin", "col": "col21", "chapter": "c21"},
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

def create_story_epub(source_dir, output_path, story_info):
    """Create individual story EPUB from extracted anthology."""
    title = story_info['title']
    author = story_info['author']
    col_id = story_info['col']
    chapter_id = story_info['chapter']

    print(f"\nCreating: {title} by {author}")

    # Create temporary directory for this story
    temp_dir = f"/tmp/epub_story_{chapter_id}"
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_dir)

    # Copy base structure
    shutil.copy(os.path.join(source_dir, 'mimetype'), temp_dir)

    # Create META-INF directory and container.xml
    metainf_dir = os.path.join(temp_dir, 'META-INF')
    os.makedirs(metainf_dir)

    # Create container.xml
    container_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
   <rootfiles>
      <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
   </rootfiles>
</container>'''
    with open(os.path.join(metainf_dir, 'container.xml'), 'w', encoding='utf-8') as f:
        f.write(container_xml)

    # Create OEBPS directory
    oebps_dir = os.path.join(temp_dir, 'OEBPS')
    os.makedirs(oebps_dir)
    
    # Copy necessary files from OEBPS
    source_oebps = os.path.join(source_dir, 'OEBPS')
    
    # Copy CSS file
    css_file = 'Mart_9780804179607_epub_css_r1.css'
    if os.path.exists(os.path.join(source_oebps, css_file)):
        shutil.copy2(os.path.join(source_oebps, css_file), os.path.join(oebps_dir, css_file))
    
    # Copy the col and chapter files for this story
    files_to_copy = []
    for item in os.listdir(source_oebps):
        # Copy files that belong to this story
        if f'_{col_id}_' in item or f'_{chapter_id}_' in item:
            files_to_copy.append(item)
    
    for file in files_to_copy:
        src = os.path.join(source_oebps, file)
        dst = os.path.join(oebps_dir, file)
        if os.path.isfile(src):
            shutil.copy2(src, dst)
    
    print(f"  Copied {len(files_to_copy)} files")
    
    # Create content.opf
    create_story_opf(source_dir, oebps_dir, story_info, files_to_copy)
    
    # Create toc.ncx
    create_story_ncx(oebps_dir, story_info)
    
    # Create the EPUB file
    create_epub_file(temp_dir, output_path)
    
    # Cleanup
    shutil.rmtree(temp_dir)
    print(f"  Created: {output_path}")

def create_story_opf(source_dir, oebps_dir, story_info, files_copied):
    """Create content.opf for individual story."""
    # Parse original OPF
    opf_files = [f for f in os.listdir(source_dir) if f.endswith('.opf')]
    if not opf_files:
        raise Exception("No OPF file found")
    
    tree = ET.parse(os.path.join(source_dir, opf_files[0]))
    root = tree.getroot()
    
    # Update metadata
    for title_elem in root.findall('.//dc:title', NS):
        title_elem.text = f"{story_info['title']} by {story_info['author']}"
    
    for creator in root.findall('.//dc:creator', NS):
        creator.text = story_info['author']
    
    # Filter manifest - keep only files we copied plus CSS
    manifest = root.find('.//opf:manifest', NS)
    items_to_remove = []
    for item in manifest.findall('.//opf:item', NS):
        item_id = item.get('id')
        href = item.get('href', '')

        # Extract just the filename from href (remove OEBPS/ prefix if present)
        filename = href.split('/')[-1] if '/' in href else href

        # Keep if it's one of our files or CSS
        if filename not in files_copied and 'css' not in filename:
            items_to_remove.append(item)
        else:
            # Since we're putting content.opf in OEBPS/, remove the OEBPS/ prefix from hrefs
            if href.startswith('OEBPS/'):
                item.set('href', filename)

    for item in items_to_remove:
        manifest.remove(item)

    # Filter spine - keep only our story items
    spine = root.find('.//opf:spine', NS)
    itemrefs_to_remove = []
    for itemref in spine.findall('.//opf:itemref', NS):
        idref = itemref.get('idref')
        # Keep only our col and chapter
        if idref not in [story_info['col'], story_info['chapter']]:
            itemrefs_to_remove.append(itemref)

    for itemref in itemrefs_to_remove:
        spine.remove(itemref)

    # Write OPF
    tree.write(os.path.join(oebps_dir, 'content.opf'), encoding='utf-8', xml_declaration=True)

def create_story_ncx(oebps_dir, story_info):
    """Create toc.ncx for individual story."""
    # Create a simple NCX
    ncx = ET.Element('ncx', xmlns=NS['ncx'], version='2005-1')

    # Head
    head = ET.SubElement(ncx, 'head')
    ET.SubElement(head, 'meta', name='dtb:uid', content='urn:uuid:rogues-story')
    ET.SubElement(head, 'meta', name='dtb:depth', content='1')
    ET.SubElement(head, 'meta', name='dtb:totalPageCount', content='0')
    ET.SubElement(head, 'meta', name='dtb:maxPageNumber', content='0')

    # Doc title
    doc_title = ET.SubElement(ncx, 'docTitle')
    title_text = ET.SubElement(doc_title, 'text')
    title_text.text = f"{story_info['title']} by {story_info['author']}"

    # Nav map
    navmap = ET.SubElement(ncx, 'navMap')
    navpoint = ET.SubElement(navmap, 'navPoint', id='navpoint-1', playOrder='1')
    navlabel = ET.SubElement(navpoint, 'navLabel')
    label_text = ET.SubElement(navlabel, 'text')
    label_text.text = story_info['title']

    # Find the actual chapter file
    col_file = None
    for f in os.listdir(oebps_dir):
        if f'_{story_info["col"]}_' in f and f.endswith('.htm'):
            col_file = f
            break

    if col_file:
        ET.SubElement(navpoint, 'content', src=col_file)

    # Write NCX
    tree = ET.ElementTree(ncx)
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
    source_epub = '/mnt/boston/media/books/George R. R. Martin/Rogues (125)/Rogues - George R. R. Martin.epub'
    output_dir = '/mnt/boston/media/books/George R. R. Martin/Rogues (125)/individual_stories'
    extract_dir = '/tmp/epub_extract_rogues'

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Extract the anthology
    if os.path.exists(extract_dir):
        shutil.rmtree(extract_dir)
    extract_epub(source_epub, extract_dir)

    # Create each individual story
    for story in STORIES:
        # Create safe filename
        filename = f"{story['author']} - {story['title']}.epub"
        # Remove problematic characters
        filename = filename.replace('?', '').replace(':', ' -').replace('/', '-')
        output_path = os.path.join(output_dir, filename)
        create_story_epub(extract_dir, output_path, story)

    print(f"\n✓ Successfully split into {len(STORIES)} individual stories!")
    print(f"  Output directory: {output_dir}")

if __name__ == '__main__':
    main()

