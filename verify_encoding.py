#!/usr/bin/env python3
"""Verify auto_translate.py encoding"""

with open('scripts/auto_translate.py', 'rb') as f:
    content = f.read()

print('First 20 bytes:', content[:20])

import re
m = re.search(b'"Yes": "([^"]+)"', content)
if m:
    print('Yes value bytes:', m.group(1))
    print('Yes value decoded:', m.group(1).decode('utf-8'))

# Check if file is valid UTF-8
try:
    content.decode('utf-8')
    print('File is valid UTF-8')
except Exception as e:
    print('Invalid UTF-8:', e)
