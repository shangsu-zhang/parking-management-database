"""Synchronize physical SQL names without regenerating user-edited diagrams."""
import ast
import hashlib
import json
import re
import shutil
import tempfile
from pathlib import Path
from zipfile import ZipFile

from lxml import etree

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '_report_build' / 'build_report.py'
tree = ast.parse(SOURCE.read_text(encoding='utf-8-sig'))
MAPPING = next(ast.literal_eval(n.value) for n in tree.body
               if isinstance(n, ast.Assign) and any(
                   isinstance(t, ast.Name) and t.id == 'SOURCE_IDENTIFIERS' for t in n.targets))
MAPPING.update({
    'idx_vehicle_车主ID':'idx_vehicle_owner_id',
    'idx_record_车辆入场':'idx_record_vehicle_entry',
    'idx_record_车位入场':'idx_record_space_entry',
    'idx_record_记录状态':'idx_record_status',
    'idx_contract_车辆日期':'idx_rental_contract_vehicle_dates',
    'idx_payment_支付时间':'idx_payment_paid_at',
})
PATTERN = re.compile('|'.join(map(re.escape, sorted(MAPPING, key=len, reverse=True))))


def translate(text):
    return PATTERN.sub(lambda m: MAPPING[m.group()], text)


def quoted(text):
    return re.sub(r'`([^`\n]+)`', lambda m: '`' + ('table_name' if m[1] == '表' else translate(m[1])) + '`', text)


def digest(data):
    return hashlib.sha256(data).hexdigest()


sql_path = ROOT / 'sql' / '停车场管理数据库.sql'
sql = quoted(sql_path.read_text(encoding='utf-8-sig'))
sql_path.write_text(sql, encoding='utf-8')
blocks = re.findall(r'CREATE TABLE `([^`]+)` \((.*?)\n\) ENGINE', sql, re.S)
schemas = {name: re.findall(r'^\s*`([^`]+)`\s+[A-Z]', body, re.M) for name, body in blocks}
assert len(schemas) == 8 and sum(map(len, schemas.values())) == 73

md_paths = [ROOT/'01_需求与数据库模型.md', ROOT/'sql'/'字段设计说明.md', ROOT/'sql'/'查询说明.md']
for path in md_paths:
    text = quoted(path.read_text(encoding='utf-8-sig'))
    lines = []
    for line in text.splitlines():
        if line.startswith('|'):
            cells = line.split('|')
            # Physical-design columns carry identifiers, while the final column
            # remains a Chinese explanation. Query result headers match aliases.
            if path.name == '字段设计说明.md':
                if re.search(r'^\| (?:\w+|管理员|车主|车辆|车位|停车记录|收费规则|月租合同|缴费记录) \|', line):
                    for i in range(1, min(len(cells)-2, 7)):
                        cells[i] = translate(cells[i])
            elif path.name == '01_需求与数据库模型.md':
                cells[1] = translate(cells[1])
                if len(cells) > 5:
                    cells[3] = translate(cells[3]) if 'FK' in cells[3] else cells[3]
            elif path.name == '查询说明.md' and line.startswith('| ') and re.search(r'ID|支付流水号|已支付金额|支付日期|车位总数|累计|实收合计|停车记录办理数|临停收入', line):
                cells = [translate(c) for c in cells]
            line = '|'.join(cells)
        if re.match(r'\d+\. \*\*', line):
            # Physical relation patterns use the exact schema column order.
            m = re.match(r'(\d+)\. \*\*([^*]+)\*\*', line)
            if m and m[2] in MAPPING and MAPPING[m[2]] in schemas:
                name = MAPPING[m[2]]
                cols = ', '.join('`'+c+'`'+(' PK' if i == 0 else '') for i,c in enumerate(schemas[name]))
                line = f'{m[1]}. **{m[2]}（`{name}`）**({cols})'
        line = line.replace('（Administrator）', '（`administrator`）').replace('（Owner）', '（`vehicle_owner`）')
        for a,b in [('ParkingSpace','parking_space'),('Vehicle','vehicle'),('ChargeRule','charge_rule'),('MonthlyContract','rental_contract'),('RentalContract','rental_contract'),('ParkingRecord','parking_record'),('PaymentRecord','payment_record')]:
            line = line.replace('（'+a+'）', '（`'+b+'`）')
        lines.append(line)
    text = '\n'.join(lines)+'\n'
    text = text.replace('| created_at | DATETIME | 否 | CURRENT_TIMESTAMP | — | — | registered_at |', '| created_at | DATETIME | 否 | CURRENT_TIMESTAMP | — | — | 登记时间 |')
    path.write_text(text, encoding='utf-8')

# A short mapping bridges the unchanged Chinese concept diagrams and the code.
mapping_path = ROOT / 'sql' / '中英文命名映射.md'
concepts = ['管理员','车主','车位','车辆','收费规则','月租合同','停车记录','缴费记录']
out = ['# 数据库中英文命名映射', '', '数据库名：`parking_management_db`。源码标识符统一为完整英文 snake_case；中文图、注释及业务数据保留。', '', '| 中文实体 | SQL 表名 |', '| --- | --- |']
out += [f'| {c} | `{MAPPING[c]}` |' for c in concepts]
reverse = {v:k for k,v in MAPPING.items()}
for c in concepts:
    name = MAPPING[c]
    out += ['', '## '+c+'（'+name+'）', '', '| 中文属性 | SQL 字段 |', '| --- | --- |']
    out += [f'| {reverse[f]} | `{f}` |' for f in schemas[name]]
mapping_path.write_text('\n'.join(out)+'\n', encoding='utf-8')

# Keep the authoring source current as well. Translate the literal SQL and
# table-column labels, preserving prose and filenames.
src = quoted(SOURCE.read_text(encoding='utf-8'))
src = re.sub(r'\("([^"\n]+)", "(BIGINT UNSIGNED|VARCHAR|CHAR|DATETIME|DATE|DECIMAL|INT UNSIGNED)"',
             lambda m: '("'+MAPPING.get(m[1],m[1])+'", "'+m[2]+'"', src)
for chinese in concepts:
    src = src.replace('"FK→'+chinese+'"', '"FK→'+MAPPING[chinese]+'"')
SOURCE.write_text(src, encoding='utf-8')

report_path = ROOT/'停车场管理项目报告.docx'
backup = Path(tempfile.mkdtemp(prefix='parking_english_before_')) / report_path.name
shutil.copy2(report_path, backup)
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w':W}
with ZipFile(report_path) as z:
    infos = z.infolist()
    parts = {n.filename:z.read(n.filename) for n in infos}
original_media = {k:digest(v) for k,v in parts.items() if k.startswith('word/media/')}
root = etree.fromstring(parts['word/document.xml'])
original_drawings = [etree.tostring(e) for e in root.findall('.//w:drawing',NS)]


def ptext(p):
    return ''.join(p.xpath('.//w:t/text()',namespaces=NS))


def update(p, value):
    old = ptext(p)
    if old == value:
        return
    nodes = p.findall('.//w:t', NS)
    # For exact field names and relation patterns, transform each existing run,
    # which retains underlining and other direct formatting.
    if ''.join(translate(t.text or '') for t in nodes) == value:
        for t in nodes:
            t.text = translate(t.text or '')
        return
    if nodes:
        nodes[0].text = value
        for t in nodes[1:]:
            t.text = ''


body = root.find('w:body',NS)
for p in body.findall('w:p',NS):
    text = ptext(p)
    if text.lstrip().startswith('SELECT '):
        update(p, quoted(text))
    elif re.match(r'\d+\. (?:车主|车辆|车位|停车记录|收费规则|月租合同|缴费记录|管理员)（',text):
        update(p, translate(text))
    elif 'SQL 使用与建表脚本一致的中文表名及字段名' in text:
        update(p,text.replace('中文表名及字段名','英文 snake_case 表名及字段名，业务枚举值保留中文'))
    elif '依据实体间联系将概念模型转换为八个关系模式' in text:
        update(p,text+' 中文实体与英文表名、字段名的对应见项目配套《中英文命名映射》。')
    elif '参与互斥 CHECK' in text or text.startswith('脚本为车牌'):
        update(p, translate(text))
tables = body.findall('w:tbl',NS)
table_order = ['administrator','vehicle_owner','parking_space','vehicle','charge_rule','rental_contract','parking_record','payment_record']
for t,name in zip(tables[1:],table_order):
    rows = t.findall('w:tr',NS)[1:]
    assert len(rows) == len(schemas[name])
    for row,field in zip(rows,schemas[name]):
        cells = row.findall('w:tc',NS)
        first = cells[0].findall('w:p',NS)
        assert len(first) == 1
        update(first[0],field)
        for cell in cells[3:5]:
            for p in cell.findall('w:p',NS):
                text = ptext(p)
                if 'FK' in text or re.search('ID|日期',text):
                    update(p,translate(text))
assert [etree.tostring(e) for e in root.findall('.//w:drawing',NS)] == original_drawings
parts['word/document.xml'] = etree.tostring(root,xml_declaration=True,encoding='UTF-8',standalone=True)
with ZipFile(report_path,'w') as z:
    for info in infos:
        z.writestr(info,parts[info.filename])
with ZipFile(report_path) as z:
    assert {k:digest(z.read(k)) for k in original_media} == original_media
    assert z.testzip() is None
print(json.dumps({'tables':len(schemas),'fields':sum(map(len,schemas.values())), 'unchanged_embedded_images':len(original_media), 'backup':str(backup)},ensure_ascii=False))
