# AtlasOS AppX Orphan Repair — WinRE method

**Experimental community guide • v0.1 • 26 November 2026**

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

## 3. Prepare while in normal Windows

- Finish pending updates safely before proceeding. Back up personal files and make a verified full system image; keep recovery media and BitLocker recovery keys accessible. Do not disable encryption just for this guide.
- Extract this archive into `C:\AppxRepair` so the SQL files are directly inside it.
- Download the architecture-appropriate official Windows command-line tools from https://sqlite.org/download.html, verify the published checksum, and place `sqlite3.exe` in the same directory. No executable is bundled. Test `C:\AppxRepair\sqlite3.exe -version` in PowerShell. Use a current CLI compatible with your WinRE environment.
- Enter Windows Recovery Environment using Advanced startup or Shift+Restart → Troubleshoot → Advanced options → Command Prompt.

## 4. Identify drives in WinRE

```cmd
diskpart
list volume
exit
```

Examples below use **E:** for the installed Windows volume and **F:** for external backup storage. Replace both with your verified actual letters. X: is normally the recovery environment. These examples assume the default ProgramData location.

```cmd
dir E:\Windows\System32\config\SYSTEM
dir E:\AppxRepair
dir E:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-*.srd*
dir F:\
```

Stop if files are missing, volume identity is uncertain, or the disk is locked. Never publish recovery keys.

## 5. Back up the offline database pair

Use new empty folders; change the suffix if a folder already exists. Check every command for errors. These are Command Prompt commands, not PowerShell.

```cmd
cd /d E:\ProgramData\Microsoft\Windows\AppRepository
mkdir F:\AppxBackup-20261126
copy /v StateRepository-Deployment.srd* F:\AppxBackup-20261126\
copy /v StateRepository-Machine.srd* F:\AppxBackup-20261126\
dir F:\AppxBackup-20261126
fc /b StateRepository-Deployment.srd F:\AppxBackup-20261126\StateRepository-Deployment.srd
fc /b StateRepository-Machine.srd F:\AppxBackup-20261126\StateRepository-Machine.srd
```

Compare each existing sidecar (`-wal`, `-shm`, and `-journal` if present) with `fc /b` too. Check source/destination sizes and counts. Stop on any discrepancy. Keep archival backup untouched; create a separate working copy:

```cmd
mkdir F:\AppxTest-20261126
copy /v F:\AppxBackup-20261126\StateRepository-Deployment.srd* F:\AppxTest-20261126\
copy /v F:\AppxBackup-20261126\StateRepository-Machine.srd* F:\AppxTest-20261126\
cd /d F:\AppxTest-20261126
E:\AppxRepair\sqlite3.exe -readonly StateRepository-Machine.srd "PRAGMA quick_check;"
E:\AppxRepair\sqlite3.exe -readonly StateRepository-Deployment.srd "PRAGMA quick_check;"
```

Both checks must return only `ok`. Do not manually delete sidecars to fix read-only WAL access errors.

## 6. Diagnose and dry-run on the working copy

```cmd
E:\AppxRepair\sqlite3.exe -bail -readonly StateRepository-Deployment.srd < E:\AppxRepair\diagnose.sql
```

Require LivePackages > 0, LiveFiles > 0, Orphan_File <= LiveFiles, at least one orphan in the three target tables, and `quick_check=ok`. Stop on missing schema, SQL errors, or unsafe counts. No orphans means this repair is unnecessary.

```cmd
E:\AppxRepair\sqlite3.exe -bail StateRepository-Deployment.srd < E:\AppxRepair\repair-test.sql
```

Require `TEST PASSED - NO CHANGES SAVED`. Run diagnose again; counts must be unchanged. If the dry-run fails, do not proceed. Never ignore a SQL error. Scripts abort on errors; connection closure rolls back an open transaction.

## 7. Repair the actual offline database

Only after the preceding checks and backups succeed. Do not execute from normal Windows. Change to the real repository:

```cmd
cd /d E:\ProgramData\Microsoft\Windows\AppRepository
dir StateRepository-*.srd*
E:\AppxRepair\sqlite3.exe -bail -readonly StateRepository-Deployment.srd < E:\AppxRepair\diagnose.sql
```

Counts must match the working copy. If they differ, stop and reassess backups. Then:

```cmd
E:\AppxRepair\sqlite3.exe -bail StateRepository-Deployment.srd < E:\AppxRepair\repair-live.sql
```

Expect deletion counts and `REPAIR COMMITTED SUCCESSFULLY`. This means the transaction committed, not that Windows functionality is guaranteed. Run the read-only diagnosis again: all three orphan counts must be zero; valid package and file counts must be unchanged; quick_check must return `ok`. Stop on discrepancies. Do not manually remove WAL/SHM.

```cmd
wpeutil reboot
```

## 8. Validate Windows functionality

Run the service and package count checks from section 1 again. Verify Start, Microsoft Store and existing apps. Install an app that previously failed, using Store or a trusted MSIX (`Add-AppxPackage -Path "C:\path\app.msix"`). Check the correct package with `Get-AppxPackage -Name <package-name>` (replace placeholder): `Status : Ok`, `IsPartiallyStaged : False`. Try a second affected app. Some services are trigger-started and need not always be Running. Keep backups until stability is confirmed.

## 9. Recovery and failure handling

Do not blindly rerun a failed repair. If no success marker appears, do not assume whether commit occurred; inspect read-only. Before reboot, if rollback of an already committed repair is needed, preserve the current Deployment main file and sidecars in a separate empty folder. Under expert supervision, move current Deployment sidecars to quarantine, overwrite the existing main file with the verified pre-repair backup and restore exactly its matching sidecars. Do not mix generations or overwrite Machine unnecessarily; it was not modified. Verify file permissions and contents. Never modify the archival backup. Detailed Turkish recovery notes are in README-TR.md.

If Windows has already booted, its database state may have advanced. Do not restore stale database files blindly. Seek expert assistance or use the verified full system image, accounting for data changes since it was created. Actual Windows rollback has not been tested by this project; no automatic restore script is provided. If the original error persists, collect fresh event logs and seek support rather than deleting additional tables.

## 10. Safety design and testing

The scripts use a read-only attached Machine DB, copy IDs into a temporary table, refuse empty Machine and excessive File orphan counts, check database structure before/after, use a single transaction, compare foreign-key violation counts for tables referencing the three targets, and require zero remaining orphans. Foreign keys are disabled in this connection only to account for the cross-database schema; the script does not change Windows settings. Counts of existing foreign-key violations are not a proof that every relationship is valid. Test mode rolls back, live mode commits. The CLI `.bail on` is mandatory.

The revised distribution was tested with Python's SQLite on disposable synthetic databases. This does not test actual Windows schemas, CLI dot commands, WinRE compatibility, or backup/restore behavior. The original manual script was used successfully on one real PC. See CASE-STUDY.md and TEST-RESULTS.txt. Run `python test_sql.py` if desired; it never touches actual Windows databases.

## References and credit

- [AtlasOS #1763](https://github.com/Atlas-OS/Atlas/issues/1763)
- [AtlasOS PR #1764](https://github.com/Atlas-OS/Atlas/pull/1764) — credit to Ayberkyvs for the original repair approach and guard design.
- [AtlasOS Store support](https://atlasos.net/docs/faq/microsoft-store/)
- [Microsoft AppX troubleshooting](https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting)
- [SQLite CLI](https://sqlite.org/cli.html), [PRAGMA reference](https://sqlite.org/pragma.html)

Independent community adaptation; not affiliated with AtlasOS or Microsoft. No raw system logs, personal details, proprietary databases or third-party executables are distributed. Review upstream licensing before incorporating upstream code or selecting a repository license.
