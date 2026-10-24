"""Finish human-facing labels and keep renamed SQL blocks on one page."""
import ast
import re
from pathlib import Path
from zipfile import ZipFile
from lxml import etree

ROOT = Path(__file__).resolve().parents[2]
builder = Path(__file__).resolve().with_name('build_report.py')
tree = ast.parse(builder.read_text(encoding='utf-8'))
mapping = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign)
               and any(isinstance(t,ast.Name) and t.id=='SOURCE_IDENTIFIERS' for t in n.targets))
pattern = re.compile('|'.join(map(re.escape,sorted(mapping,key=len,reverse=True))))
translate = lambda t: pattern.sub(lambda m:mapping[m[0]],t)

query_path = ROOT/'sql'/'查询说明.md'
q = query_path.read_text(encoding='utf-8')
start = q.index('| 编号 |')
end = q.index('\n\n',start)
overview = '''| 编号 | 名称 | 类型 | 涉及表 | 技术要点 |
| --- | --- | --- | --- | --- |
| 单表 1 | 当前在场的临时车辆 | 单表 | parking_record | 多条件筛选 + 排序 |
| 单表 2 | 未来 30 天内到期的有效月租合同 | 单表 | rental_contract | 日期区间 + 当前日期函数 |
| 单表 3 | 指定日期已支付的缴费流水 | 单表 | payment_record | 日期范围半开区间筛选 |
| 多表 1 | 在场车辆、车主和车位 | 多表 | parking_record、vehicle、vehicle_owner、parking_space | 四表内连接 |
| 多表 2 | 按月租合同统计已支付金额 | 多表 | rental_contract、vehicle、vehicle_owner、payment_record | 左连接 + 条件聚合 |
| 多表 3 | 按日期和缴费类型统计停车场收入 | 多表 | payment_record、administrator | 内连接 + 分组聚合 |
| 统计 1 | 按区域统计车位数量与占用情况 | 单表聚合 | parking_space | 条件求和 + 占用率 |
| 统计 2 | 车辆停车次数、累计时长与费用 | 多表聚合 | vehicle、vehicle_owner、parking_record | 左连接 + COALESCE 汇总 |
| 统计 3 | 已支付收入总览 | 单表聚合 | payment_record | WITH ROLLUP 总计 |
| 统计 4 | 管理员业务办理量统计 | 多表聚合 | administrator + 3 个子查询 | 相关子查询 |
| 统计 5 | 本月每日收入统计 | 单表聚合 | payment_record | 条件聚合 + 按日分组 |'''
q=q[:start]+overview+q[end:]
headers = [
['parking_record_id','vehicle_id','parking_space_id','entry_time','record_status'],
['rental_contract_id','contract_no','vehicle_id','start_date','end_date','monthly_rent'],
['payment_no','payment_type','amount_due','amount_paid','payment_method','paid_at'],
['license_plate','owner_name','space_code','area','entry_time','parking_type'],
['contract_no','license_plate','owner_name','monthly_rent','paid_amount','paid_count'],
['payment_date','payment_type','administrator_name','payment_count','revenue_amount'],
['area','total_spaces','occupied_spaces','available_spaces','disabled_spaces','occupancy_rate'],
['license_plate','owner_name','parking_count','total_duration_minutes','total_amount_due'],
['payment_type','payment_count','total_amount_paid'],
['employee_no','name','role','parking_record_count','rental_contract_count','paid_payment_count','collected_amount'],
['date','temporary_revenue','rental_revenue','daily_revenue']]
lines=q.splitlines()
matches=[i for i,line in enumerate(lines[:-1]) if line.startswith('|') and lines[i+1].startswith('| ---')][1:]
assert len(matches)==len(headers)
for i,h in zip(matches,headers):
    lines[i]='| '+' | '.join(h)+' |'
q='\n'.join(lines)+'\n'
q=q.replace("`SUM(车位状态 = '占用')`","`SUM(space_status = '占用')`")
query_path.write_text(q,encoding='utf-8')

model=ROOT/'docs'/'01_需求与数据库模型.md'
m=model.read_text(encoding='utf-8')
m=m.replace('关系模式如下，属性后的下划线含义为主键，`FK` 后注明参照关系：',
            '关系模式使用英文物理名称，`PK` 标记主键；外键及基数见第 4 节联系说明与配套字段设计说明。')
m=re.sub(r'参照(车主|车辆|车位|管理员|收费规则|月租合同|停车记录)\(([^)]+)\)',lambda x:'参照'+translate(x[1])+'('+translate(x[2])+')',m)
model.write_text(m,encoding='utf-8')

path=ROOT/'report'/'停车场管理项目报告.docx'
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
ns={'w':W}
with ZipFile(path) as z:
    infos=z.infolist()
    parts={i.filename:z.read(i.filename) for i in infos}
root=etree.fromstring(parts['word/document.xml'])
for p in root.findall('w:body/w:p',ns):
    text=''.join(p.xpath('.//w:t/text()',namespaces=ns))
    is_sql=text.lstrip().startswith('SELECT ')
    is_title=bool(re.match(r'(?:单表查询|多表查询|2\.3|表\s*2-|\d+\. .+表$)',text)) or text in {'规范化分析','索引与跨记录一致性'}
    is_purpose=text.startswith('查询用途：')
    if not (is_sql or is_title or is_purpose):
        continue
    props=p.find('w:pPr',ns)
    if props is None:
        props=etree.Element('{'+W+'}pPr')
        p.insert(0,props)
    tag='keepLines' if is_sql else 'keepNext'
    prop=props.find('w:'+tag,ns)
    if prop is None:
        prop=etree.SubElement(props,'{'+W+'}'+tag)
    prop.set('{'+W+'}val','1')
for table in root.findall('w:body/w:tbl',ns)[1:]:
    # Keep each caption, table header, and the first data row together.
    header=table.find('w:tr',ns)
    for p in header.findall('.//w:p',ns):
        props=p.find('w:pPr',ns)
        if props is None:
            props=etree.Element('{'+W+'}pPr')
            p.insert(0,props)
        keep=props.find('w:keepNext',ns)
        if keep is None:
            keep=etree.SubElement(props,'{'+W+'}keepNext')
        keep.set('{'+W+'}val','1')
parts['word/document.xml']=etree.tostring(root,encoding='UTF-8',xml_declaration=True,standalone=True)
with ZipFile(path,'w') as z:
    for info in infos:
        z.writestr(info,parts[info.filename])
print('Query documentation labels and SQL pagination finalized; no images touched.')
