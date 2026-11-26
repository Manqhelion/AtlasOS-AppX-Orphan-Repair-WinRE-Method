"""Synthetic fixtures only; no Windows or real AppRepository access."""
import sqlite3, tempfile, os
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def run(mode, scenario):
    with tempfile.TemporaryDirectory() as d:
        old=os.getcwd(); os.chdir(d)
        try:
            with sqlite3.connect('StateRepository-Machine.srd') as m:
                m.execute('CREATE TABLE Package(_PackageID INTEGER PRIMARY KEY)')
                if scenario!='empty': m.execute('INSERT INTO Package VALUES(1)')
            db=sqlite3.connect('StateRepository-Deployment.srd',uri=True)
            db.executescript('''CREATE TABLE File(id INTEGER PRIMARY KEY, Package INTEGER REFERENCES Package(_PackageID));
            CREATE TABLE AppxManifest(id INTEGER PRIMARY KEY, Package INTEGER REFERENCES Package(_PackageID));
            CREATE TABLE PackageSourceUri(id INTEGER PRIMARY KEY, Package INTEGER REFERENCES Package(_PackageID));
            CREATE TABLE ContentGroupFile(id INTEGER PRIMARY KEY, file_id INTEGER REFERENCES File(id));
            INSERT INTO File VALUES(1,1),(2,1),(3,2);
            INSERT INTO AppxManifest VALUES(1,1),(2,2);
            INSERT INTO PackageSourceUri VALUES(1,1),(2,2);''')
            if scenario=='majority': db.executescript('INSERT INTO File VALUES(4,2),(5,2);')
            if scenario=='reference': db.executescript('INSERT INTO ContentGroupFile VALUES(1,3);')
            if scenario=='existing': db.executescript('INSERT INTO ContentGroupFile VALUES(1,99);')
            if scenario=='clean': db.executescript('DELETE FROM File WHERE Package=2; DELETE FROM AppxManifest WHERE Package=2; DELETE FROM PackageSourceUri WHERE Package=2;')
            if scenario=='null': db.execute('INSERT INTO File VALUES(4,NULL)')
            if scenario=='noninteger': db.execute("INSERT INTO File VALUES(4,'unexpected')")
            if scenario=='no_live_file': db.execute('DELETE FROM File')
            if scenario=='trigger_delete': db.executescript('CREATE TRIGGER bad AFTER DELETE ON File WHEN old.Package=2 BEGIN DELETE FROM File WHERE Package=1; END;')
            if scenario=='trigger_update': db.executescript('INSERT INTO ContentGroupFile VALUES(1,1); CREATE TRIGGER bad AFTER DELETE ON File BEGIN UPDATE ContentGroupFile SET file_id=2; END;')
            if scenario=='fk_swap': db.executescript('INSERT INTO ContentGroupFile VALUES(1,99),(2,3); CREATE TRIGGER bad AFTER DELETE ON File BEGIN UPDATE ContentGroupFile SET file_id=1 WHERE id=1; END;')
            if scenario=='missing_schema': db.execute('DROP TABLE PackageSourceUri'); db.execute('CREATE TABLE PackageSourceUri(id INTEGER PRIMARY KEY)')
            db.commit()
            before=[db.execute('SELECT * FROM '+t).fetchall() for t in ('File','AppxManifest','PackageSourceUri','ContentGroupFile')]
            sql='\n'.join(x for x in (ROOT/f'repair-{mode}.sql').read_text().splitlines() if not x.startswith('.'))
            failed=False
            try: db.executescript(sql)
            except sqlite3.Error: failed=True; db.rollback()
            after=[db.execute('SELECT * FROM '+t).fetchall() for t in ('File','AppxManifest','PackageSourceUri','ContentGroupFile')]
            assert failed==(scenario in ('empty','majority','reference','null','noninteger','no_live_file','trigger_delete','trigger_update','fk_swap','missing_schema')), (scenario,failed)
            if failed or mode=='test' or scenario=='clean': assert after==before
            else: assert after==[[row for row in rows if row[1]==1] for rows in before[:3]]+[before[3]]
            db.close(); print(f'PASS {mode}: {scenario}')
        finally: os.chdir(old)

for mode in ('test','live'):
    for scenario in ('normal','empty','majority','reference','existing','clean','null','noninteger','no_live_file','trigger_delete','trigger_update','fk_swap','missing_schema'): run(mode,scenario)
