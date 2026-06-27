#!/usr/bin/env python3
"""
Check translation completeness for zh_CN.po against simpleui.pot
"""
import re
import argparse
from pathlib import Path


def parse_po_entries(content: str) -> set:
    """Parse msgid entries from PO/POT content"""
    entries = set()
    blocks = re.split(r'\n\n+', content)
    
    for block in blocks:
        lines = block.strip().split('\n')
        msgid = ''
        in_msgid = False
        
        for line in lines:
            if line.startswith('msgid '):
                m = re.match(r'msgid\s+"(.*)"', line)
                if m:
                    msgid = m.group(1)
                in_msgid = True
            elif line.startswith('"') and in_msgid:
                m = re.match(r'"(.*)"', line)
                if m:
                    msgid += m.group(1)
            else:
                in_msgid = False
        
        if msgid:
            entries.add(msgid)
    
    return entries


def check_translation(pot_path: str, po_path: str, count_missing: bool = False) -> int:
    """Check if PO file has all entries from POT file"""
    pot_content = Path(pot_path).read_text(encoding='utf-8')
    po_content = Path(po_path).read_text(encoding='utf-8')
    
    pot_entries = parse_po_entries(pot_content)
    po_entries = parse_po_entries(po_content)
    
    # Remove empty string (header)
    pot_entries.discard('')
    po_entries.discard('')
    
    missing = pot_entries - po_entries
    
    if count_missing:
        # Only output the count for GitHub Actions
        print(len(missing))
        return len(missing)
    
    print(f"POT template entries: {len(pot_entries)}")
    print(f"PO file entries: {len(po_entries)}")
    print(f"Missing entries: {len(missing)}")
    
    if missing:
        print("\nMissing translations:")
        for entry in sorted(missing):
            print(f"  - {entry}")
    
    if not missing:
        print("\n✓ Translation is complete!")
        return 0
    else:
        print(f"\n✗ Translation is incomplete ({len(missing)} entries missing)")
        return 1


def main():
    parser = argparse.ArgumentParser(description='Check translation completeness')
    parser.add_argument('--pot', default='locale/simpleui.pot', help='Path to POT file')
    parser.add_argument('--po', default='locale/zh_CN.po', help='Path to PO file')
    parser.add_argument('--count-missing', action='store_true', help='Only output missing count')
    
    args = parser.parse_args()
    
    if args.count_missing:
        result = check_translation(args.pot, args.po, count_missing=True)
        print(result)  # Output just the number for GitHub Actions
    else:
        result = check_translation(args.pot, args.po)
        exit(result)


if __name__ == '__main__':
    main()
