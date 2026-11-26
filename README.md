# AtlasOS AppX Orphan Repair — WinRE method

**Experimental community guide • v0.1 — documentation revision 3 • 26 November 2026**

[Turkish full guide / Türkçe kılavuz](README-TR.md) · [Case study](CASE-STUDY.md) · [Test results](TEST-RESULTS.txt)

Targeted workaround for Microsoft Store / AppX / MSIX error `0x80073CF9`, inner `0x80070490`, failure in the Evaluated state, on certain older AtlasOS installations. A single real-world AtlasOS 0.4.1 repair succeeded without reinstalling Windows. This is not an official AtlasOS or Microsoft tool. The distributed scripts are a revised adaptation, tested against synthetic SQLite fixtures only.

> **Warning:** This modifies internal Windows system databases. Back up personal files and create a verified full system image first. Prefer the current official [AtlasOS Store repair guide](https://atlasos.net/docs/faq/microsoft-store/). Do not run the repair while normal Windows is running, during a pending update, or without confirmed matching symptoms and backups. Not a universal fix.

## 1. Confirm the symptom

In elevated PowerShell:

```powershell
Get-Service StateRepository, AppXSvc, InstallService
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppXDeploymentServer/Operational';Id=605;StartTime=(Get-Date).AddDays(-30)} -MaxEvents 30 | Select-Object TimeCreated,Id,Message | Format-List
(Get-AppxPackage -AllUsers).Count
```

Confirm a recent failure matching `0x80070490: Failure in the Evaluated state handler` and the affected package. Outer error 0x80073CF9 alone is insufficient. Try official Store troubleshooting first. A different error, or no matching event, means stop.

## 2. Why this can happen

AtlasOS issue #1763 and PR #1764 propose that AME `!appx` removals on older Atlas releases can leave deployment records whose package IDs no longer exist in the Machine database. Windows may then fail during evaluation of new packages. The internal schema is undocumented by Microsoft; this is an evidence-based hypothesis, not a universal causal guarantee.

The scripts compare `StateRepository-Machine.srd` → `Package._PackageID` with `StateRepository-Deployment.srd` → `File.Package`, `AppxManifest.Package`, and `PackageSourceUri.Package`. Only the three target tables are modified. The Machine database is opened read-only. Raw foreign-key checks across the entire Deployment database can report missing parents that actually reside in the Machine database. `quick_check` checks database structure, not all logical relationships.

### Why orphaned records can break installation

A `File` row is metadata, not a physical file. For example, a row with Package=999 is orphaned if Machine no longer contains package 999. PR #1764 hypothesizes that Windows compares new file digests with existing `File.Digest` records during evaluation to assess hardlink reuse. A matching record belonging to a missing package can prevent the required package lookup, potentially producing `0x80070490` (element not found). The outer `0x80073CF9` is a generic deployment failure. This mechanism is inferred from observations and upstream comments, not documented by Microsoft. Successful installs after cleanup in our case support the hypothesis but do not prove that each orphan caused a failure.

**Compatibility limits:** Microsoft does not expose this private database schema as a supported editing interface. Tables, triggers and relationships can vary across Windows builds. Successful SQL checks do not establish Windows compatibility. A matching error signature, full system image, offline backup, working-copy test and post-repair validation remain mandatory. The scripts do not hardcode package IDs or orphan counts from our PC.

## 3. Prepare while in normal Windows

- Finish pending updates safely before proceeding. Back up personal files and make a verified full system image; keep recovery media and BitLocker recovery keys accessible. Do not disable encryption just for this guide.
- On GitHub choose **Code → Download ZIP**. Extract the contents into `C:\AppxRepair` so the SQL files are directly inside it (not in another nested directory). If Windows normally uses another drive letter, use that drive instead for this step and the CLI version check.
- Download the architecture-appropriate official Windows command-line tools from https://sqlite.org/download.html, verify the published checksum, and place `sqlite3.exe` in the same directory. No executable is bundled. Test `C:\AppxRepair\sqlite3.exe -version` in PowerShell. Use a current CLI compatible with your WinRE environment.
- Enter Windows Recovery Environment using Advanced startup or Shift+Restart → Troubleshoot → Advanced options → Command Prompt.

## 4. Identify drives in WinRE

```cmd
diskpart
list volume
exit
```

**Set the drive letters only here.** E: is the example installed Windows volume; F: is the example external backup drive. Replace these with your verified letters. X: is normally WinRE's RAM disk; do not use it. Stop if ProgramData is in a nonstandard location.

```cmd
set "WIN=E:"
set "DEST=F:\AppxBackup-01"
set "REPO=%WIN%\ProgramData\Microsoft\Windows\AppRepository"
set "TOOLS=%WIN%\AppxRepair"
set "BAK=%DEST%\original"
set "TEST=%DEST%\test"
set "SQL=%TOOLS%\sqlite3.exe"
set "DB=StateRepository-Deployment.srd"
set "MACHINE=StateRepository-Machine.srd"
```

Edit only the first two lines. DEST must be a new, nonexistent directory; choose another name and redefine the variables if it exists. Use the remaining commands verbatim. Variables last only for this CMD session; redefine them and verify drive letters if you open another window.

```cmd
dir "%WIN%\Windows\System32\config\SYSTEM"
dir "%REPO%\StateRepository-*.srd*"
dir "%TOOLS%"
if exist "%DEST%" echo STOP - backup folder already exists
"%SQL%" -version
```

Both main databases, sqlite3.exe and all three SQL files must exist. Verify the external backup disk is accessible and has sufficient free space. Stop on any error, STOP message or uncertainty.

## 5. Back up the offline database pair

Run each command separately. Stop on any failure. Create the archive and working copy under the same new backup root.

```cmd
cd /d "%REPO%"
mkdir "%BAK%"
copy /v "%DB%*" "%BAK%\"
copy /v "%MACHINE%*" "%BAK%\"
dir "%BAK%"
fc /b "%DB%" "%BAK%\%DB%"
fc /b "%MACHINE%" "%BAK%\%MACHINE%"
```

Compare every existing sidecar (`-wal`, `-shm`, `-journal` if present) using the commands below. Use a single `%S` at the interactive CMD prompt. Stop on any difference or error; also compare file sizes and counts. Keep the archive untouched.

```cmd
for %S in (wal shm journal) do @if exist "%DB%-%S" fc /b "%DB%-%S" "%BAK%\%DB%-%S"
for %S in (wal shm journal) do @if exist "%MACHINE%-%S" fc /b "%MACHINE%-%S" "%BAK%\%MACHINE%-%S"
```

Create a separate working copy and test only that copy.

```cmd
mkdir "%TEST%"
copy /v "%BAK%\%DB%*" "%TEST%\"
copy /v "%BAK%\%MACHINE%*" "%TEST%\"
cd /d "%TEST%"
"%SQL%" -readonly "%MACHINE%" "PRAGMA quick_check;"
"%SQL%" -readonly "%DB%" "PRAGMA quick_check;"
```

Both results must be only `ok`. Stop on read-only WAL access errors; do not delete sidecars manually.

## 6. Diagnose and dry-run on the working copy

```cmd
"%SQL%" -bail -readonly "%DB%" < "%TOOLS%\diagnose.sql"
```

Require LivePackages > 0, LiveFiles > 0, Orphan_File <= LiveFiles, at least one orphan in the three target tables, all three `Unexpected_*_Package` counts equal to zero, and `quick_check=ok`. Stop on missing schema, SQL errors, or unsafe counts. No orphans means this repair is unnecessary.

```cmd
"%SQL%" -bail "%DB%" < "%TOOLS%\repair-test.sql"
```

Require `TEST PASSED - NO CHANGES SAVED`. Run diagnose again; counts must be unchanged. If the dry-run fails, do not proceed. Never ignore a SQL error. Scripts abort on errors; connection closure rolls back an open transaction.

## 7. Repair the actual offline database

Only after the preceding checks and backups succeed. Do not execute from normal Windows. Change to the real repository:

```cmd
cd /d "%REPO%"
dir StateRepository-*.srd*
"%SQL%" -bail -readonly "%DB%" < "%TOOLS%\diagnose.sql"
```

Counts must match the working copy. If they differ, stop and reassess backups. Then:

```cmd
"%SQL%" -bail "%DB%" < "%TOOLS%\repair-live.sql"
```

Expect deletion counts and `REPAIR COMMITTED SUCCESSFULLY`. This means the transaction committed, not that Windows functionality is guaranteed. Run the following read-only diagnosis again:

```cmd
"%SQL%" -bail -readonly "%DB%" < "%TOOLS%\diagnose.sql"
```

 All three orphan counts must be zero; valid package, File, manifest and source URI counts must be unchanged; quick_check must return `ok`. Stop on discrepancies. Do not manually remove WAL/SHM.

```cmd
wpeutil reboot
```

## 8. Validate Windows functionality

Run the service and package count checks from section 1 again. Verify Start, Microsoft Store and existing apps. Install an app that previously failed, using Store or a trusted MSIX (`Add-AppxPackage -Path "C:\path\app.msix"`). Check the correct package with `Get-AppxPackage -Name <package-name>` (replace placeholder): `Status : Ok`, `IsPartiallyStaged : False`. Try a second affected app. Some services are trigger-started and need not always be Running. Keep backups until stability is confirmed.

## 9. Recovery and failure handling

Do not blindly rerun a failed repair. If no success marker appears, do not assume whether commit occurred; inspect read-only. Before reboot, if rollback of an already committed repair is needed, preserve the current Deployment main file and sidecars in a separate empty folder. Under expert supervision, move current Deployment sidecars to quarantine, overwrite the existing main file with the verified pre-repair backup and restore exactly its matching sidecars. Do not mix generations or overwrite Machine unnecessarily; it was not modified. Verify file permissions and contents. Never modify the archival backup. Detailed Turkish recovery notes are in README-TR.md.

If Windows has already booted, its database state may have advanced. Do not restore stale database files blindly. Seek expert assistance or use the verified full system image, accounting for data changes since it was created. Actual Windows rollback has not been tested by this project; no automatic restore script is provided. If the original error persists, collect fresh event logs and seek support rather than deleting additional tables.

## 10. Safety design and testing

The scripts use a read-only attached Machine DB, copy IDs into a temporary table, refuse empty Machine and excessive File orphan counts, check database structure before/after, use a single transaction, compare foreign-key violation tuples (table, rowid, parent, FK ID) for tables referencing the three targets, reject violations without rowids, reject unexpected NULL/non-integer package IDs and zero live File rows, check for extra row changes using total_changes(), preserve valid row counts in all three target tables, and require zero remaining orphans. Foreign keys are disabled in this connection only to account for the cross-database schema; the script does not change Windows settings. These checks deliberately reject additional trigger-driven row changes, even if those changes might be legitimate on a particular Windows build. They do not prove every logical relationship is valid. Test mode rolls back, live mode commits. The CLI `.bail on` is mandatory.

The revised distribution was tested with Python's SQLite on disposable synthetic databases (26 repair-mode test cases). This does not test actual Windows schemas, CLI dot commands, WinRE compatibility, or backup/restore behavior. The original manual script was used successfully on one real PC. See CASE-STUDY.md and TEST-RESULTS.txt. Run `python test_sql.py` if desired; it never touches actual Windows databases.

## References and credit

- [AtlasOS #1763](https://github.com/Atlas-OS/Atlas/issues/1763)
- [AtlasOS PR #1764](https://github.com/Atlas-OS/Atlas/pull/1764) — credit to Ayberkyvs for the original repair approach and guard design.
- [AtlasOS Store support](https://atlasos.net/docs/faq/microsoft-store/)
- [Microsoft AppX troubleshooting](https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting)
- [SQLite CLI](https://sqlite.org/cli.html), [PRAGMA reference](https://sqlite.org/pragma.html)

Independent community adaptation; not affiliated with AtlasOS or Microsoft. No raw system logs, personal details, proprietary databases or third-party executables are distributed. The distributed adaptation is licensed under GPL-3.0; see LICENSE. The upstream Atlas project is also GPL-3.0. Original approach credited above; this is a separate implementation.
