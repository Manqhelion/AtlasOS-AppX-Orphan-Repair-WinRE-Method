.bail on
.timeout 5000
.headers on
.mode column
ATTACH DATABASE 'file:StateRepository-Machine.srd?mode=ro' AS machine;
CREATE TEMP TABLE live(id INTEGER PRIMARY KEY NOT NULL);
INSERT INTO live SELECT _PackageID FROM machine.Package;
DETACH DATABASE machine;
PRAGMA foreign_keys=OFF;
BEGIN IMMEDIATE;
CREATE TEMP TABLE guard(ok INTEGER NOT NULL CHECK(ok=1));
INSERT INTO guard VALUES ((SELECT count(*) FROM live)>0);
INSERT INTO guard VALUES ((SELECT count(*) FROM main.File WHERE Package NOT IN (SELECT id FROM live)) <= (SELECT count(*) FROM main.File WHERE Package IN (SELECT id FROM live)));
INSERT INTO guard VALUES ((SELECT count(*) FROM pragma_quick_check)=1 AND (SELECT quick_check FROM pragma_quick_check LIMIT 1)='ok');
CREATE TEMP TABLE refs AS SELECT DISTINCT m.name AS tbl FROM main.sqlite_master m, pragma_foreign_key_list(m.name) f WHERE m.type='table' AND lower(f."table") IN ('file','appxmanifest','packagesourceuri');
CREATE TEMP TABLE fk_before AS SELECT tbl, (SELECT count(*) FROM pragma_foreign_key_check(tbl)) AS n FROM refs;
DELETE FROM main.File WHERE Package NOT IN (SELECT id FROM live);
SELECT changes() AS Removed_File;
DELETE FROM main.AppxManifest WHERE Package NOT IN (SELECT id FROM live);
SELECT changes() AS Removed_AppxManifest;
DELETE FROM main.PackageSourceUri WHERE Package NOT IN (SELECT id FROM live);
SELECT changes() AS Removed_PackageSourceUri;
INSERT INTO guard SELECT (SELECT count(*) FROM pragma_foreign_key_check(tbl)) <= n FROM fk_before;
INSERT INTO guard VALUES ((SELECT count(*) FROM pragma_quick_check)=1 AND (SELECT quick_check FROM pragma_quick_check LIMIT 1)='ok');
INSERT INTO guard VALUES ((SELECT count(*) FROM main.File WHERE Package NOT IN (SELECT id FROM live))=0);
INSERT INTO guard VALUES ((SELECT count(*) FROM main.AppxManifest WHERE Package NOT IN (SELECT id FROM live))=0);
INSERT INTO guard VALUES ((SELECT count(*) FROM main.PackageSourceUri WHERE Package NOT IN (SELECT id FROM live))=0);
ROLLBACK;
SELECT 'TEST PASSED - NO CHANGES SAVED' AS Result;
