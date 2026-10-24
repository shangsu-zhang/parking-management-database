"""Finalize figure numbers and small pagination issues after visual review."""
from pathlib import Path
from zipfile import ZipFile
import re
from lxml import etree

ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'report'/'停车场管理项目报告.docx'
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS={'w':W}
def tag(n):return '{'+W+'}'+n
def text(e):return ''.join(e.xpath('.//w:t/text()',namespaces=NS))
def prop(e,n):
    p=e.find('w:pPr',NS)
    if p is None:p=etree.Element(tag('pPr'));e.insert(0,p)
    c=p.find('w:'+n,NS)
    if c is None:c=etree.SubElement(p,tag(n))
    return c
def update(e,t):
    nodes=e.findall('.//w:t',NS)
    nodes[0].text=t
    for n in nodes[1:]:n.text=''

with ZipFile(PATH) as z:
    infos=z.infolist();parts={i.filename:z.read(i.filename) for i in infos}
root=etree.fromstring(parts['word/document.xml'])
body=root.find('w:body',NS)
count=0
for p in body.findall('w:p',NS):
    t=text(p)
    match=re.match(r'^(?:图\s*[12]-\d|(?:图\s*)?3-[1-6])\s+(.+)$',t)
    if match and ('效果图' in t or '停车场管理系统' in t):
        count+=1;update(p,f'图 1-{count}  {match[1]}')
    elif re.search(r'图\s*2-1',t):
        update(p,re.sub(r'图\s*2-1','图 1-1',t))
    if t.startswith('单表查询1：'):
        prop(p,'pageBreakBefore').set(tag('val'),'0')
assert count==8

# Remove spaces used as visual padding from cover values; align via paragraph properties.
cover=body.find('w:tbl',NS)
for index,row in enumerate(cover.findall('w:tr',NS)):
    p=row.findall('w:tc',NS)[1].find('w:p',NS)
    t=text(p).strip()
    if index in [4,5]:t=re.sub(r'\s+','  ',t)
    update(p,t)
    for run in p.findall('w:r',NS):
        rp=run.find('w:rPr',NS)
        if rp is None:rp=etree.SubElement(run,tag('rPr'))
        for size in ['sz','szCs']:
            el=rp.find('w:'+size,NS)
            if el is None:el=etree.SubElement(rp,tag(size))
            el.set(tag('val'),'24' if index in [4,5] else '28')
    prop(p,'jc').set(tag('val'),'center')

# Avoid leaving a single final data row alone on the following page.
for table in body.findall('w:tbl',NS)[1:]:
    rows=table.findall('w:tr',NS)
    for p in rows[-2].findall('.//w:p',NS):prop(p,'keepNext').set(tag('val'),'1')

parts['word/document.xml']=etree.tostring(root,encoding='UTF-8',xml_declaration=True,standalone=True)
with ZipFile(PATH,'w') as z:
    for info in infos:z.writestr(info,parts[info.filename])
print('Numbered all eight figures 1-1 through 1-8; updated references and corrected cover/pagination.')
