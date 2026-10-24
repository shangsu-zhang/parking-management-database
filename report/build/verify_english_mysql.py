"""Run the course script only in a fresh, isolated local MySQL instance."""
from pathlib import Path
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BIN = Path(r'C:\Program Files\MySQL\MySQL Server 8.0\bin')
WORK = Path(tempfile.mkdtemp(prefix='parking_mysql_english_'))
DATA = WORK/'data'
DATA.mkdir()
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0))
    port = sock.getsockname()[1]
flags = subprocess.CREATE_NO_WINDOW
print('Isolated instance:', WORK, 'port:', port, flush=True)
init = subprocess.run([str(BIN/'mysqld.exe'),'--no-defaults','--initialize-insecure',
    '--basedir='+str(BIN.parent),'--datadir='+str(DATA)],capture_output=True,creationflags=flags,timeout=120)
if init.returncode:
    raise RuntimeError(init.stderr.decode('utf-8',errors='replace'))
client = [str(BIN/'mysql.exe'),'--no-defaults','--protocol=TCP','--host=127.0.0.1',
          '--port='+str(port),'--user=root','--connect-timeout=2',
          '--default-character-set=utf8mb4','--batch']
log = open(WORK/'server.log','wb')
server = subprocess.Popen([str(BIN/'mysqld.exe'),'--no-defaults',
    '--basedir='+str(BIN.parent),'--datadir='+str(DATA),'--port='+str(port),
    '--bind-address=127.0.0.1','--mysqlx=OFF','--skip-log-bin',
    '--innodb-buffer-pool-size=64M','--performance-schema=OFF','--console'],
    stdout=log,stderr=subprocess.STDOUT,creationflags=flags)
try:
    for _ in range(60):
        ready = subprocess.run(client+['--execute=SELECT VERSION();'],capture_output=True,creationflags=flags)
        if ready.returncode == 0:
            break
        if server.poll() is not None:
            raise RuntimeError((WORK/'server.log').read_text(encoding='utf-8',errors='replace'))
        time.sleep(0.5)
    else:
        raise RuntimeError('Temporary MySQL did not become ready')
    script = (ROOT/'sql'/'停车场管理数据库.sql').read_bytes()
    run = subprocess.run(client,input=script,capture_output=True,creationflags=flags,timeout=60)
    validation = '''USE parking_management_db;
SELECT COUNT(*) AS table_count FROM information_schema.tables WHERE table_schema=DATABASE();
SELECT COUNT(*) AS column_count FROM information_schema.columns WHERE table_schema=DATABASE();
SELECT COUNT(*) AS foreign_key_count FROM information_schema.referential_constraints WHERE constraint_schema=DATABASE();
SELECT COUNT(*) AS check_count FROM information_schema.table_constraints WHERE constraint_schema=DATABASE() AND constraint_type='CHECK';
'''
    check = subprocess.run(client,input=validation.encode(),capture_output=True,creationflags=flags,timeout=20)
    report = ('MySQL isolated execution\n'+ready.stdout.decode('utf-8')+
              '\nScript exit code: '+str(run.returncode)+'\n'+run.stdout.decode('utf-8')+
              '\nSTDERR\n'+run.stderr.decode('utf-8')+
              '\nSchema checks\n'+check.stdout.decode('utf-8')+check.stderr.decode('utf-8'))
    (ROOT/'report'/'build'/'english_mysql_validation.txt').write_text(report,encoding='utf-8')
    assert run.returncode == 0, run.stderr.decode('utf-8')
    assert check.returncode == 0, check.stderr.decode('utf-8')
    print(check.stdout.decode('utf-8'),flush=True)
    # The invalid in-place update must be rejected by the renamed CHECK.
    negative = subprocess.run(client,input=b"USE parking_management_db; UPDATE parking_record SET record_status='\xe5\xb7\xb2\xe5\x87\xba\xe5\x9c\xba' WHERE record_status='\xe5\x9c\xa8\xe5\x9c\xba' LIMIT 1;",capture_output=True,creationflags=flags)
    assert negative.returncode != 0 and b'3819' in negative.stderr, negative.stderr
    with (ROOT/'report'/'build'/'english_mysql_validation.txt').open('a',encoding='utf-8') as f:
        f.write('\nNegative CHECK test (expected rejection)\n'+negative.stderr.decode('utf-8'))
    print('All script statements and queries passed; invalid status update rejected.',flush=True)
finally:
    subprocess.run([str(BIN/'mysqladmin.exe'),'--no-defaults','--protocol=TCP',
        '--host=127.0.0.1','--port='+str(port),'--user=root','shutdown'],
        capture_output=True,creationflags=flags,timeout=20)
    try:
        server.wait(timeout=20)
    except subprocess.TimeoutExpired:
        server.terminate()
        server.wait(timeout=10)
    log.close()
