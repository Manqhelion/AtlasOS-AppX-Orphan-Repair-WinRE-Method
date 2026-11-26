.bail on
.timeout 5000
.headers on
.mode column
ATTACH DATABASE 'file:StateRepository-Machine.srd?mode=ro' AS machine;
CREATE TEMP TABLE live(id INTEGER PRIMARY KEY NOT NULL);
CREATE TEMP TABLE machine_guard(ok INTEGER NOT NULL CHECK(ok=1));
INSERT INTO machine_guard VALUES (NOT EXISTS (SELECT 1 FROM machine.Package WHERE _PackageID IS NULL OR typeof(_PackageID) <> 'integer'));
INSERT INTO live SELECT _PackageID FROM machine.Package;
DETACH DATABASE machine;
PRAGMA foreign_keys=OFF;
BEGIN IMMEDIATE;
CREATE TEMP TABLE guard(ok INTEGER NOT NULL CHECK(ok=1));
INSERT INTO guard VALUES ((SELECT count(*) FROM live)>0);
INSERT INTO guard VALUES ((SELECT count(*) FROM main.File WHERE Package IN (SELECT id FROM live))>0);
-- Unexpected package values are not candidates for automatic deletion.
INSERT INTO guard VALUES (NOT EXISTS (SELECT 1 FROM main.File WHERE Package IS NULL OR typeof(Package)<>'integer'));
INSERT INTO guard VALUES (NOT EXISTS (SELECT 1 FROM main.AppxManifest WHERE Package IS NULL OR typeof(Package)<>'integer'));
INSERT INTO guard VALUES (NOT EXISTS (SELECT 1 FROM main.PackageSourceUri WHERE Package IS NULL OR typeof(Package)<>'integer'));
INSERT INTO guard VALUES ((SELECT count(*) FROM main.File WHERE Package NOT IN (SELECT id FROM live)) <= (SELECT count(*) FROM main.File WHERE Package IN (SELECT id FROM live)));
INSERT INTO guard VALUES ((SELECT count(*) FROM pragma_quick_check)=1 AND (SELECT quick_check FROM pragma_quick_check LIMIT 1)='ok');
CREATE TEMP TABLE refs AS SELECT DISTINCT m.name AS tbl FROM main.sqlite_master m, pragma_foreign_key_list(m.name) f WHERE m.type='table' AND lower(f."table") IN ('file','appxmanifest','packagesourceuri');
CREATE TEMP TABLE fk_before AS SELECT v."table" AS tbl, v.rowid AS rid, v.parent, v.fkid FROM refs r, pragma_foreign_key_check(r.tbl) v;
INSERT INTO guard VALUES (NOT EXISTS (SELECT 1 FROM fk_before WHERE rid IS NULL));
CREATE TEMP TABLE baseline(t TEXT PRIMARY KEY, valid INTEGER, orphan INTEGER);
CREATE TEMP TABLE meter(n INTEGER);
INSERT INTO baseline SELECT 'File', count(*) FILTER (WHERE Package IN (SELECT id FROM live)), count(*) FILTER (WHERE Package NOT IN (SELECT id FROM live)) FROM main.File;
DELETE FROM meter;
INSERT INTO meter VALUES (total_changes()+1);
DELETE FROM main.File WHERE Package NOT IN (SELECT id FROM live);
SELECT changes() AS Removed_File;
-- Reject any extra row modifications by triggers, including in unrelated tables.
INSERT INTO guard VALUES (changes()=(SELECT orphan FROM baseline WHERE t='File') AND total_changes()-(SELECT n FROM meter)=changes());
INSERT INTO baseline SELECT 'AppxManifest', count(*) FILTER (WHERE Package IN (SELECT id FROM live)), count(*) FILTER (WHERE Package NOT IN (SELECT id FROM live)) FROM main.AppxManifest;
DELETE FROM meter;
INSERT INTO meter VALUES (total_changes()+1);
DELETE FROM main.AppxManifest WHERE Package NOT IN (SELECT id FROM live);
SELECT changes() AS Removed_AppxManifest;
-- Reject any extra row modifications by triggers, including in unrelated tables.
INSERT INTO guard VALUES (changes()=(SELECT orphan FROM baseline WHERE t='AppxManifest') AND total_changes()-(SELECT n FROM meter)=changes());
INSERT INTO baseline SELECT 'PackageSourceUri', count(*) FILTER (WHERE Package IN (SELECT id FROM live)), count(*) FILTER (WHERE Package NOT IN (SELECT id FROM live)) FROM main.PackageSourceUri;
DELETE FROM meter;
INSERT INTO meter VALUES (total_changes()+1);
DELETE FROM main.PackageSourceUri WHERE Package NOT IN (SELECT id FROM live);
SELECT changes() AS Removed_PackageSourceUri;
-- Reject any extra row modifications by triggers, including in unrelated tables.
INSERT INTO guard VALUES (changes()=(SELECT orphan FROM baseline WHERE t='PackageSourceUri') AND total_changes()-(SELECT n FROM meter)=changes());
CREATE TEMP TABLE fk_after AS SELECT v."table" AS tbl, v.rowid AS rid, v.parent, v.fkid FROM refs r, pragma_foreign_key_check(r.tbl) v;
INSERT INTO guard VALUES (NOT EXISTS (SELECT 1 FROM fk_after WHERE rid IS NULL));
INSERT INTO guard VALUES (NOT EXISTS (SELECT * FROM fk_after EXCEPT SELECT * FROM fk_before));
-- Compare valid row counts in all three target tables before commit.
INSERT INTO guard VALUES ((SELECT count(*) FROM main.File WHERE Package IN (SELECT id FROM live))=(SELECT valid FROM baseline WHERE t='File'));
INSERT INTO guard VALUES ((SELECT count(*) FROM main.AppxManifest WHERE Package IN (SELECT id FROM live))=(SELECT valid FROM baseline WHERE t='AppxManifest'));
INSERT INTO guard VALUES ((SELECT count(*) FROM main.PackageSourceUri WHERE Package IN (SELECT id FROM live))=(SELECT valid FROM baseline WHERE t='PackageSourceUri'));
INSERT INTO guard VALUES ((SELECT count(*) FROM pragma_quick_check)=1 AND (SELECT quick_check FROM pragma_quick_check LIMIT 1)='ok');
INSERT INTO guard VALUES ((SELECT count(*) FROM main.File WHERE Package NOT IN (SELECT id FROM live))=0);
INSERT INTO guard VALUES ((SELECT count(*) FROM main.AppxManifest WHERE Package NOT IN (SELECT id FROM live))=0);
INSERT INTO guard VALUES ((SELECT count(*) FROM main.PackageSourceUri WHERE Package NOT IN (SELECT id FROM live))=0);
COMMIT;
SELECT 'REPAIR COMMITTED SUCCESSFULLY' AS Result;
