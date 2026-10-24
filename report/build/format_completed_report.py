"""Format the user's completed report while preserving text and image XML."""
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from zipfile import ZipFile
import json
import re
import shutil
from lxml import etree

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(__file__).resolve().parent
PATH = ROOT / 'report' / '停车场管理项目报告.docx'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W}
def tag(name): return '{'+W+'}'+name
def child(parent, name):
    el = parent.find('w:'+name, NS)
    if el is None: el = etree.SubElement(parent, tag(name))
    return el
def attrs(el, **values):
    for key, value in values.items(): el.set(tag(key), str(value))
def pp(p):
    el = p.find('w:pPr', NS)
    if el is None:
        el = etree.Element(tag('pPr')); p.insert(0, el)
    return el
def text(p): return ''.join(p.xpath('.//w:t/text()', namespaces=NS))
def spacing(p, line=240, before=0, after=0):
    props = pp(p)
    attrs(child(props, 'spacing'), line=line, lineRule='auto', before=before, after=after,
          beforeAutospacing=0, afterAutospacing=0)
    attrs(child(props, 'snapToGrid'), val=0)
def indent(p, first=0):
    el = child(pp(p), 'ind'); el.attrib.clear()
    attrs(el, left=0, right=0, firstLine=first)
def align(p, value): attrs(child(pp(p), 'jc'), val=value)
def flag(p, name, value=1): attrs(child(pp(p), name), val=value)
def font(p, size, east='宋体', latin='Times New Roman', bold=None):
    for run in p.findall('w:r', NS):
        if run.find('w:drawing', NS) is not None or run.find('w:pict', NS) is not None: continue
        props = run.find('w:rPr', NS)
        if props is None: props=etree.Element(tag('rPr')); run.insert(0, props)
        fonts=child(props,'rFonts'); fonts.attrib.clear()
        attrs(fonts, ascii=latin, hAnsi=latin, eastAsia=east, cs=latin)
        attrs(child(props,'sz'), val=round(size*2)); attrs(child(props,'szCs'), val=round(size*2))
        color=child(props,'color'); color.attrib.clear(); attrs(color,val='000000')
        if bold is not None: attrs(child(props,'b'),val=int(bold))
def has_picture(p): return bool(p.findall('.//w:drawing',NS) or p.findall('.//w:pict',NS))

backup_dir=WORK/'format_backup'
backup_dir.mkdir(exist_ok=True)
backup=backup_dir/(datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+PATH.name)
shutil.copy2(PATH, backup)
with ZipFile(PATH) as z:
    infos=z.infolist(); parts={i.filename:z.read(i.filename) for i in infos}
root=etree.fromstring(parts['word/document.xml'])
body=root.find('w:body',NS)
original_text=root.xpath('.//w:t/text()',namespaces=NS)
original_drawings=[etree.tostring(e) for e in root.findall('.//w:drawing',NS)]
original_media={k:v for k,v in parts.items() if k.startswith('word/media/')}

# Remove empty body spacers only; retain cover spacing and section boundaries.
in_body=False; removed=0
for p in list(body):
    if p.tag!=tag('p'):continue
    if text(p)=='一、项目概述':in_body=True
    if in_body and not text(p) and not has_picture(p) and not p.findall('.//w:sectPr',NS) and not p.findall('.//w:br',NS) and not p.findall('.//w:fldChar',NS):
        body.remove(p); removed+=1

in_body=False; pictures=0
for p in body.findall('w:p',NS):
    t=text(p)
    if t=='一、项目概述':in_body=True
    if has_picture(p):
        spacing(p,240,80,120); indent(p); align(p,'center'); flag(p,'keepLines')
        pictures+=1
        continue
    if not in_body:
        if t=='2026—2027学年第 1 学期':
            align(p,'center');indent(p);font(p,18,bold=True);spacing(p,240,0,160)
        elif t=='项目报告':
            align(p,'center');indent(p);font(p,32,'黑体',bold=True);spacing(p,240,160,160)
        continue
    is_heading=bool(re.match(r'^[一二三四五]、|^2\.[1-4]\s|^（[123]）(?:实体|整体)|^(?:单表查询|多表查询)',t)) or t in {'规范化分析','索引与跨记录一致性'}
    is_caption=bool(re.match(r'^(?:图\s*[23]-\d|表\s*2-\d|3-[1-6]\s)',t))
    is_table_label=bool(re.match(r'^\d+\. .+表$',t))
    if t.startswith('SELECT '):
        font(p,9,'宋体','Consolas');spacing(p,240,60,120);indent(p);align(p,'left');flag(p,'keepLines')
    elif is_heading:
        major=bool(re.match(r'^[一二三四五]、',t))
        font(p,16 if major else 14,'黑体',bold=True);spacing(p,300,200,160);indent(p);align(p,'left');flag(p,'keepNext');flag(p,'keepLines')
        if t.startswith(('单表查询','多表查询','四、')):flag(p,'pageBreakBefore')
    elif is_caption:
        font(p,10.5);spacing(p,240,100,60);indent(p);align(p,'center');flag(p,'keepNext');flag(p,'keepLines')
    elif is_table_label:
        font(p,12);spacing(p,280,140,60);indent(p);align(p,'left');flag(p,'keepNext')
    else:
        font(p,12);spacing(p,360,0,80);indent(p,480);align(p,'both');flag(p,'widowControl')
        if t.startswith('查询用途：'):indent(p);flag(p,'keepNext')
        if re.match(r'^\d+\. (?:vehicle|parking|charge|rental|payment|administrator)',t):
            indent(p);align(p,'left');spacing(p,300,0,60)

tables=body.findall('w:tbl',NS)
for index,table in enumerate(tables):
    widths=[2100,5200] if index==0 else [1700,1500,580,2100,1150,2042]
    props=table.find('w:tblPr',NS)
    if props is None:props=etree.Element(tag('tblPr'));table.insert(0,props)
    attrs(child(props,'tblW'),w=sum(widths),type='dxa')
    attrs(child(props,'tblLayout'),type='fixed');attrs(child(props,'jc'),val='center')
    grid=table.find('w:tblGrid',NS)
    if grid is not None:table.remove(grid)
    grid=etree.Element(tag('tblGrid'));table.insert(list(table).index(props)+1,grid)
    for width in widths:attrs(etree.SubElement(grid,tag('gridCol')),w=width)
    margins=child(props,'tblCellMar')
    for side in ['left','right']:attrs(child(margins,side),w=70,type='dxa')
    for side in ['top','bottom']:attrs(child(margins,side),w=45 if index else 100,type='dxa')
    for row_index,row in enumerate(table.findall('w:tr',NS)):
        rp=row.find('w:trPr',NS)
        if rp is None:rp=etree.Element(tag('trPr'));row.insert(0,rp)
        attrs(child(rp,'cantSplit'),val=1)
        for height in rp.findall('w:trHeight',NS):rp.remove(height)
        if row_index==0 and index:attrs(child(rp,'tblHeader'),val=1)
        for col,(cell,width) in enumerate(zip(row.findall('w:tc',NS),widths)):
            cp=cell.find('w:tcPr',NS)
            if cp is None:cp=etree.Element(tag('tcPr'));cell.insert(0,cp)
            attrs(child(cp,'tcW'),w=width,type='dxa');attrs(child(cp,'vAlign'),val='center')
            for p in cell.findall('w:p',NS):
                indent(p);spacing(p,240,0,0);align(p,'left' if col in ([0,3,4,5] if index else [0]) else 'center')
                font(p,9 if index else 14,bold=(row_index==0) if index else None)
                if index:flag(p,'keepNext',int(row_index==0))

assert root.xpath('.//w:t/text()',namespaces=NS)==original_text
assert [etree.tostring(e) for e in root.findall('.//w:drawing',NS)]==original_drawings
parts['word/document.xml']=etree.tostring(root,encoding='UTF-8',xml_declaration=True,standalone=True)
with ZipFile(PATH,'w') as z:
    for info in infos:z.writestr(info,parts[info.filename])
with ZipFile(PATH) as z:
    assert z.testzip() is None
    assert all(z.read(name)==value for name,value in original_media.items())
record={'backup':str(backup),'picture_paragraphs_single_spaced':pictures,'removed_empty_spacers':removed,'text_unchanged':True,'image_bytes_and_drawing_xml_unchanged':True}
(WORK/'format_validation.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(record,ensure_ascii=False))
