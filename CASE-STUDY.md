# Case study / Vaka analizi — 26 November 2026

## Environment and symptom

AtlasOS 0.4.1; Windows 11 Pro 24H2 originally, upgraded to build 26300.9974 during an attempted Atlas Manager update (as reported during troubleshooting). Store and MSIX installs had failed for months. ChatGPT, Claude, App Installer and other packages were affected. Atlas Manager stalled on Store update preparation.

Reported unsuccessful approaches: elevated installation, winget, Store reset, SFC, DISM, new local administrator account, service checks and Windows update. NTFS hardlink creation succeeded. None identified the root cause by itself. A portable extraction launched ChatGPT but was not an adequate replacement for normal installation.

Anonymized event excerpt (observed):

```text
Event ID 605: Error 0x80070490: Failure in the Evaluated state handler.
Outer deployment error: 0x80073CF9
Performance summary: Failed to reach state Evaluated
```

The symptom matched AtlasOS issue #1763 and the repair logic in PR #1764. The theory is that removed packages left orphaned Deployment rows. The exact internal Windows execution mechanism is not documented by Microsoft.

## Diagnosis and repair

| Measurement | Count |
|---|---:|
| Machine package IDs | 242 |
| Valid File rows | 37202 |
| Orphan File rows | 11513 |
| Orphan AppxManifest rows | 67 |
| Orphan PackageSourceUri rows | 120 |
| Total removed | 11700 |

Both database backups passed quick_check. A dry-run on copies rolled back successfully. The original repair ran offline in WinRE after taking paired database and sidecar backups. It compared Machine IDs against the three Deployment tables, checked reference counts and quick_check, and committed. The observed output included `REPAIR COMMITTED SUCCESSFULLY`.

Windows rebooted successfully. AppXSvc, StateRepository and InstallService were running. `Get-AppxPackage -AllUsers` returned 166 installed packages; this count is not expected to match Machine database IDs one-for-one. The previously failing ChatGPT MSIX installation completed without error. The package returned:

```text
Name: OpenAI.Codex
Version: 26.1120.6357.0
SignatureKind: Store
IsPartiallyStaged: False
Status: Ok
```

The user also confirmed that WhatsApp, which had failed to install for months, installed successfully via Microsoft Store. This supports the effectiveness of the targeted repair on this system; it does not prove all Store failures have the same cause. No Windows reinstall or format was performed during the database repair.

## Türkçe özet

AtlasOS 0.4.1 kullanılan bir Windows 11 bilgisayarda aylardır Store/MSIX kurulumu yapılamıyordu. Olay 605 ve Evaluated aşamasındaki 0x80070490 hatası, AtlasOS #1763 ve #1764 ile eşleşti. İki SQLite veritabanı karşılaştırıldı. 11.513 File tablosu kaydı, 67 manifest ve 120 kaynak adresi kaydı Machine tarafında karşılıksızdı. Kopya üzerinde test ve çevrimdışı yedek alındı. WinRE'de toplam 11.700 sahipsiz kayıt temizlendi. Windows normal açıldı; ChatGPT ve WhatsApp başarıyla kuruldu. Bu bir gerçek vaka sonucudur, tüm Windows sürümleri için garanti değildir.

## Reproducibility boundary

The original manually prepared SQL script succeeded in the above case. The v0.1 distributed scripts have additional checks and explicit schema qualification; they have not yet been run on a real Windows machine. Their synthetic tests are included. No actual system databases, private identifiers, screenshots or raw logs are published. The current distribution remains experimental; later documentation and safety-check revisions do not change the original case results.
