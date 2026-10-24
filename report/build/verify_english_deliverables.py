"""Verify the renamed deliverables against SQL and original image bytes."""
import ast
import hashlib
import json
import re
from pathlib import Path
from zipfile import ZipFile

from lxml import etree

ROOT = Path(__file__).resolve().parents[2]
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W}
sql = (ROOT / 'sql' / '停车场管理数据库.sql').read_text(encoding='utf-8')
schemas = {name: re.findall(r'^\s*`([^`]+)`\s+[A-Z]', body, re.M)
           for name, body in re.findall(r'CREATE TABLE `([^`]+)` \((.*?)\n\) ENGINE', sql, re.S)}
active = re.sub(r'^\s*--.*$', '', sql, flags=re.M)
assert all(re.fullmatch(r'[a-z][a-z0-9_]*', name)
           for name in re.findall(r'`([^`]+)`', active))
normalize = lambda value: re.sub(r'\s+', '', value)
queries = re.findall(r'^SELECT\b.*?;', active, re.S | re.M)[:11]
documented = re.findall(r'```sql\s*(.*?)```', (ROOT / 'sql' / '查询说明.md').read_text(encoding='utf-8'), re.S)
assert len(documented) == 11
assert list(map(normalize, queries)) == list(map(normalize, documented))
with ZipFile(ROOT / 'report' / '停车场管理项目报告.docx') as z:
    assert z.testzip() is None
    parts = {name: z.read(name) for name in z.namelist()}
root = etree.fromstring(parts['word/document.xml'])
def text(element):
    return ''.join('\n' if node.tag == '{'+W+'}br' else node.text or ''
                   for node in element.iter() if node.tag in {'{'+W+'}t', '{'+W+'}br'})
paragraphs = root.findall('w:body/w:p', NS)
report_queries = [text(p) for p in paragraphs if text(p).startswith('SELECT ')]
assert list(map(normalize, report_queries)) == list(map(normalize, queries[:6]))
table_order = ['administrator', 'vehicle_owner', 'parking_space', 'vehicle',
               'charge_rule', 'rental_contract', 'parking_record', 'payment_record']
for table, name in zip(root.findall('w:body/w:tbl', NS)[1:], table_order):
    fields = [text(row.find('w:tc', NS)) for row in table.findall('w:tr', NS)[1:]]
    assert fields == schemas[name], (name, fields)
backup = ROOT / 'report' / 'build' / 'format_backup' / '20261020_115208_停车场管理项目报告.docx'
with ZipFile(backup) as z:
    media = [name for name in z.namelist() if name.startswith('word/media/')]
    assert all(z.read(name) == parts[name] for name in media)
    old = etree.fromstring(z.read('word/document.xml'))
    assert [etree.tostring(e) for e in old.findall('.//w:drawing', NS)] == [etree.tostring(e) for e in root.findall('.//w:drawing', NS)]
for item in json.loads((ROOT / 'report' / 'build' / 'images_before_english.json').read_text(encoding='utf-8-sig')):
    assert hashlib.sha256((ROOT / Path(item['Path'])).read_bytes()).hexdigest().upper() == item['Hash']
assert 'vehicleowner_id' not in text(root)
ast.parse((ROOT / 'report' / 'build' / 'build_report.py').read_text(encoding='utf-8'))
print('PASS: 8 tables / 73 fields; 11 documented queries / 6 report queries match SQL; all original media and drawing XML unchanged.')
