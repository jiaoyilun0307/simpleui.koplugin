#!/usr/bin/env python3
"""Generate auto_translate.py with correct UTF-8 encoding"""

content = r'''#!/usr/bin/env python3
"""
Auto-translate missing entries in zh_CN.po
Uses a translation dictionary for common terms, falls back to keeping English
"""
import re
from pathlib import Path
from datetime import datetime


# Common translation dictionary for UI terms
TRANSLATION_DICT = {
    # Common UI terms
    "Enable": "启用",
    "Disable": "禁用",
    "Show": "显示",
    "Hide": "隐藏",
    "Save": "保存",
    "Cancel": "取消",
    "OK": "确定",
    "Yes": "是",
    "No": "否",
    "Close": "关闭",
    "Open": "打开",
    "Delete": "删除",
    "Edit": "编辑",
    "Add": "添加",
    "Remove": "移除",
    "Reset": "重置",
    "Apply": "应用",
    "Settings": "设置",
    "Options": "选项",
    "Loading": "正在加载",
    "Loading…": "正在加载…",
    "Fixed": "固定",
    "Height": "高度",
    "Width": "宽度",
    "Size": "大小",
    "Position": "位置",
    "Top": "顶部",
    "Bottom": "底部",
    "Left": "左侧",
    "Right": "右侧",
    "Center": "居中",
    "Auto": "自动",
    "Manual": "手动",
    "Default": "默认",
    "Custom": "自定义",
    "None": "无",
    "All": "全部",
    "Book": "书籍",
    "Books": "书籍",
    "Page": "页面",
    "Pages": "页面",
    "Chapter": "章节",
    "Statistics": "统计",
    "Notice": "提示",
    "Warning": "警告",
    "Error": "错误",
    "Success": "成功",
    "Failed": "失败",
    "Unavailable": "不可用",
    "not available": "不可用",
    "preventing": "防止",
    "accidental": "意外",
    "double-taps": "双击",
    "e-ink": "电子墨水屏",
    "refreshes": "刷新",
    "brief": "短暂",
    "window": "窗口",
    "opening": "打开",
    "closing": "关闭",
}


def build_translation(msgid: str) -> str:
    """Build Chinese translation from English msgid"""
    # Try exact match first
    if msgid in TRANSLATION_DICT:
        return TRANSLATION_DICT[msgid]
    
    # Try building from words
    result = msgid
    
    # Handle ellipsis
    if result.endswith('…'):
        result = '正在' + result[:-1] + '…'
    
    # Handle common patterns
    patterns = [
        (r'Show a brief "([^"]+)" notice', r'显示短暂的"\1"提示'),
        (r'preventing accidental double-taps', r'防止发生意外双击'),
        (r'while e-ink refreshes', r'在电子墨水屏刷新期间'),
        (r'when opening', r'打开'),
        (r'when closing', r'关闭'),
        (r'Fixed Height', r'固定高度'),
        (r'Loading statistics', r'正在加载统计数据'),
        (r'Fetching bookmarks', r'正在获取书签'),
        (r'Statistics Loading Notice', r'统计数据加载提示'),
    ]
    
    for pattern, replacement in patterns:
        result = re.sub(pattern, replacement, result, flags=re.IGNORECASE)
    
    # If still looks like English, return as-is with a note
    if re.match(r'^[A-Z][a-z]+(\s+[a-z]+)*$', result):
        return f"[待翻译] {result}"
    
    return result


def get_po_entries_set(content: str) -> set:
    """Get set of msgid entries from PO content"""
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


def auto_translate(pot_path: str, po_path: str):
    """Add missing translations to PO file"""
    pot_content = Path(pot_path).read_text(encoding='utf-8')
    po_content = Path(po_path).read_text(encoding='utf-8')
    
    pot_entries = get_po_entries_set(pot_content)
    po_entries = get_po_entries_set(po_content)
    
    pot_entries.discard('')
    po_entries.discard('')
    
    missing = pot_entries - po_entries
    
    if not missing:
        print("No missing translations to add.")
        return
    
    print(f"Found {len(missing)} missing translations:")
    
    # Parse existing PO to find insertion point
    lines = po_content.split('\n')
    
    # Find the last entry
    insert_blocks = []
    for msgid in sorted(missing):
        translation = build_translation(msgid)
        print(f"  {msgid} → {translation}")
        
        # Escape quotes in translation
        translation_escaped = translation.replace('"', '\\"')
        msgid_escaped = msgid.replace('"', '\\"')
        
        block = f'\nmsgid "{msgid_escaped}"\nmsgstr "{translation_escaped}"'
        insert_blocks.append(block)
    
    # Append to end of file
    new_content = po_content.rstrip() + '\n' + '\n'.join(insert_blocks) + '\n'
    
    Path(po_path).write_text(new_content, encoding='utf-8')
    print(f"\nUpdated {po_path} with {len(missing)} new translations.")


def main():
    auto_translate('locale/simpleui.pot', 'locale/zh_CN.po')


if __name__ == '__main__':
    main()
'''

with open('scripts/auto_translate.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("File generated successfully!")
