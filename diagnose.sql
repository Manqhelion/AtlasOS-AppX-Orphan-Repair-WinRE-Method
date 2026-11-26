.bail on
.timeout 5000
.headers on
.mode column
ATTACH DATABASE 'file:StateRepository-Machine.srd?mode=ro' AS machine;
CREATE TEMP TABLE live(id INTEGER PRIMARY KEY NOT NULL);
INSERT INTO live SELECT _PackageID FROM machine.Package;
DETACH DATABASE machine;
SELECT (SELECT count(*) FROM live) AS LivePackages;
SELECT count(*) AS Orphan_File FROM main.File WHERE Package NOT IN (SELECT id FROM live);
SELECT count(*) AS Orphan_AppxManifest FROM main.AppxManifest WHERE Package NOT IN (SELECT id FROM live);
SELECT count(*) AS Orphan_PackageSourceUri FROM main.PackageSourceUri WHERE Package NOT IN (SELECT id FROM live);
SELECT count(*) AS LiveFiles FROM main.File WHERE Package IN (SELECT id FROM live);
PRAGMA main.quick_check;
