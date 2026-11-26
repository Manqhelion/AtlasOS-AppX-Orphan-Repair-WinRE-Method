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
SELECT (SELECT count(*) FROM live) AS LivePackages;
SELECT count(*) AS Orphan_File FROM main.File WHERE Package NOT IN (SELECT id FROM live);
SELECT count(*) AS Orphan_AppxManifest FROM main.AppxManifest WHERE Package NOT IN (SELECT id FROM live);
SELECT count(*) AS Orphan_PackageSourceUri FROM main.PackageSourceUri WHERE Package NOT IN (SELECT id FROM live);
SELECT count(*) AS LiveFiles FROM main.File WHERE Package IN (SELECT id FROM live);
SELECT count(*) AS Unexpected_File_Package FROM main.File WHERE Package IS NULL OR typeof(Package)<>'integer';
SELECT count(*) AS Unexpected_AppxManifest_Package FROM main.AppxManifest WHERE Package IS NULL OR typeof(Package)<>'integer';
SELECT count(*) AS Unexpected_PackageSourceUri_Package FROM main.PackageSourceUri WHERE Package IS NULL OR typeof(Package)<>'integer';
SELECT count(*) AS LiveManifests FROM main.AppxManifest WHERE Package IN (SELECT id FROM live);
SELECT count(*) AS LiveSourceUris FROM main.PackageSourceUri WHERE Package IN (SELECT id FROM live);
PRAGMA main.quick_check;
