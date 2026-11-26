# AtlasOS AppX Orphan Repair — WinRE yöntemi

**Topluluk rehberi / deneysel manuel onarım • 26 Kasım 2026 • v0.1**

Microsoft Store, AppX ve MSIX yüklemelerinde `0x80073CF9` / iç hata `0x80070490` (Evaluated state) için hedefli onarım. Windows'u yeniden kurmadan çözülen bir AtlasOS 0.4.1 vakasına dayanır. AtlasOS veya Microsoft tarafından onaylanmış bir araç değildir. Her kurulum hatasını çözmez.

> **ÖNEMLİ:** Windows sistem veritabanı değiştirilecektir. Yanlış disk, farklı şema veya tutarsız yedek sistemi bozabilir. Tam sistem imajı ve kişisel dosya yedeği olmadan canlı onarıma geçmeyin. Öncelikle güncel resmî Atlas Store onarımını değerlendirin. Bu rehber deneyimli kullanıcılar içindir; şüphede kalırsanız durun.

## 1. Belirtiler ve kapsam

Birden fazla uygulama Store'dan veya `Add-AppxPackage` ile kurulamıyor; Event Viewer'da **Microsoft-Windows-AppXDeploymentServer/Operational**, olay 605, `Error 0x80070490: Failure in the Evaluated state handler.` görülüyor. Dış hata 0x80073CF9 olabilir. 0x80073D28 tek başına bu teşhisi desteklemez.

Yönetici PowerShell:

```powershell
Get-Service StateRepository, AppXSvc, InstallService
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppXDeploymentServer/Operational';Id=605;StartTime=(Get-Date).AddDays(-30)} -MaxEvents 30 | Select-Object TimeCreated,Id,Message | Format-List
(Get-AppxPackage -AllUsers).Count
```

Bir uygulamayı güvenilir kaynaktan kurmayı deneyip yeni olayın tarihini doğrulayın. Farklı hata varsa bu yöntemi uygulamayın. Store'un resmî onarım kılavuzu: https://atlasos.net/docs/faq/microsoft-store/ . Hizmetler ve kullanıcı profiliyle ilgili nedenleri önce değerlendirin; SFC/DISM, Store sıfırlama gibi işlemleri zaten denediyseniz gereksiz yere tekrarlamayın.

## 2. Teknik açıklama

`%ProgramData%\Microsoft\Windows\AppRepository` altında bulunan `StateRepository-Machine.srd` içindeki `Package._PackageID` kayıtları ile `StateRepository-Deployment.srd` içindeki `File.Package`, `AppxManifest.Package`, `PackageSourceUri.Package` ilişkilidir. AtlasOS #1763 ve #1764, eski AME `!appx` kaldırmalarından sonra sahipsiz Deployment kayıtları kalabildiğini ve bunların Evaluated aşamasındaki hatanın muhtemel nedeni olduğunu açıklıyor. Microsoft bu iç şemayı belgelemiyor. Ham `foreign_key_check` çıktısı farklı veritabanında bulunan üst tabloları eksik sanabilir; tek başına bütün veritabanının bozuk olduğunu göstermez. `quick_check=ok` da mantıksal tutarlılık garantisi değildir.

Bu pakette sadece üç hedef tablonun Machine tarafında bulunmayan paket kimlikli satırları silinir. Machine veritabanı salt okunur açılır. Bütün veritabanı silinmez. Referans tablolarındaki yabancı anahtar hata sayısı artarsa işlem geri alınır; mevcut hataları onarmaya çalışmaz. Bu, Atlas önerisinin WinRE uyarlamasıdır, orijinal Atlas kodu değildir.

## 3. Hazırlık (normal Windows)

- Bekleyen Windows/Atlas güncellemesi varsa önce güvenle tamamlayın. Devam eden güncelleme sırasında onarım yapmayın. Kurtarma anahtarını güvenli biçimde saklayın; BitLocker'ı sırf bu rehber için kapatmayın.
- Harici diske tam sistem imajı ve kişisel dosya yedeği alın; kurtarma ortamından erişilebilir olduğunu doğrulayın. Sistem imajı geri yüklemesinin sonradan yapılan değişiklikleri kaybettirebileceğini unutmayın.
- Bu paketi bir klasöre çıkarın: örneğin `C:\AppxRepair` (dosyalar doğrudan klasörün içinde olmalı).
- https://sqlite.org/download.html adresinden Windows mimarinize uygun **sqlite-tools** arşivini indirin, yayınlanan sağlama toplamını doğrulayın ve `sqlite3.exe` dosyasını aynı klasöre koyun. Bu pakette exe yoktur. WinRE ile uyumlu çalıştırılabilir dosya gerekir.
- Yönetici PowerShell'den `C:\AppxRepair\sqlite3.exe -version` ile aracın çalıştığını kontrol edin. Güncel SQLite CLI kullanın.
- Ayarlar > Sistem > Kurtarma > Gelişmiş başlangıç > Şimdi yeniden başlat; Sorun gider > Gelişmiş seçenekler > Komut İstemi. Alternatif: Shift tuşuyla Yeniden Başlat.

## 4. WinRE'de diskleri doğrulayın

Komut İstemi'nde:

```cmd
diskpart
list volume
exit
```

**Aşağıdaki örnekte E: Windows diski, F: yedek için harici disk.** Harfler her bilgisayarda değişebilir. X: genelde WinRE'nin RAM diskidir. Kendi harflerinizi kullanın. Dizinler varsayılan Windows yerleşimini esas alır; farklı ProgramData konumunuz varsa bu rehberi doğrudan kullanmayın.

```cmd
dir E:\Windows\System32\config\SYSTEM
dir E:\AppxRepair
dir E:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-*.srd*
dir F:\
```

İki ana `.srd` dosyası ve üç SQL betiği bulunmalı. Şüpheli/missing dosya veya kilitli sürücü varsa durun. BitLocker kurtarma anahtarını yalnızca kendi sisteminizde, gerektiğinde kullanın; yayımlamayın.

## 5. Çevrimdışı yedekleme (zorunlu)

Yeni ve boş bir yedek dizini oluşturun; örneğin `F:\AppxBackup-20261126`. Aynı adlı klasör zaten varsa yeni isim seçin. Her komutun sonucunu okuyun. Örnekler CMD içindir, PowerShell değildir.

```cmd
cd /d E:\ProgramData\Microsoft\Windows\AppRepository
mkdir F:\AppxBackup-20261126
copy /v StateRepository-Deployment.srd* F:\AppxBackup-20261126\
copy /v StateRepository-Machine.srd* F:\AppxBackup-20261126\
dir F:\AppxBackup-20261126
```

Her iki ana dosya ve mevcut `-wal`, `-shm` (varsa `-journal`) dosyaları kopyalanmış olmalı. Kaynak ve hedef boyutlarını karşılaştırın; `fc /b` ile her dosyanın kaynak/hedef içeriğini karşılaştırın. Örnek:

```cmd
fc /b StateRepository-Deployment.srd F:\AppxBackup-20261126\StateRepository-Deployment.srd
fc /b StateRepository-Machine.srd F:\AppxBackup-20261126\StateRepository-Machine.srd
```

Kopyalama hatası, fark veya disk alanı sorunu varsa durun. **Arşiv yedeğini sorgulamayın/değiştirmeyin; ayrı çalışma kopyası oluşturun.**

```cmd
mkdir F:\AppxTest-20261126
copy /v F:\AppxBackup-20261126\StateRepository-Deployment.srd* F:\AppxTest-20261126\
copy /v F:\AppxBackup-20261126\StateRepository-Machine.srd* F:\AppxTest-20261126\
cd /d F:\AppxTest-20261126
E:\AppxRepair\sqlite3.exe -readonly StateRepository-Machine.srd "PRAGMA quick_check;"
E:\AppxRepair\sqlite3.exe -readonly StateRepository-Deployment.srd "PRAGMA quick_check;"
```

İki çıktı da sadece `ok` olmalı. Değilse durun. SQLite'ın salt okunur WAL açma koşulları sağlanmıyorsa rastgele yan dosya silmeyin.

## 6. Teşhis ve geri alınan test

Hâlâ çalışma kopyası klasöründeyken:

```cmd
E:\AppxRepair\sqlite3.exe -bail -readonly StateRepository-Deployment.srd < E:\AppxRepair\diagnose.sql
```

LivePackages > 0, LiveFiles > 0 ve Orphan_File <= LiveFiles olmalıdır. En az bir sahipsiz kayıt bulunmalı. Hiç yoksa bu onarım gereksizdir. Sayılar başka bilgisayardan kopyalanmaz. Şema hatası, SQL hatası veya quick_check != ok durumunda durun.

```cmd
E:\AppxRepair\sqlite3.exe -bail StateRepository-Deployment.srd < E:\AppxRepair\repair-test.sql
```

`TEST PASSED - NO CHANGES SAVED` görünmeli. Ardından diagnose.sql'yi aynı kopyada tekrar çalıştırıp sayılarının değişmediğini doğrulayın. Test başarısızsa canlı onarım yapmayın. Betik hata durumunda kapanır, açık işlem bağlantı kapanınca geri alınır. Hata kodunu yok saymayın.

## 7. Gerçek onarım (yalnızca WinRE'de)

Yedekleri, test sonucunu ve hata imzasını doğruladıysanız devam edin. Normal Windows içinde **çalıştırmayın**. Önce gerçek Windows dizinine geçin (örnek E:):

```cmd
cd /d E:\ProgramData\Microsoft\Windows\AppRepository
dir StateRepository-*.srd*
E:\AppxRepair\sqlite3.exe -bail -readonly StateRepository-Deployment.srd < E:\AppxRepair\diagnose.sql
```

Sayılar çalışma kopyası ile aynı olmalı. Değilse durun ve yedekleme/teşhisi yeniden değerlendirin. Sonrasında:

```cmd
E:\AppxRepair\sqlite3.exe -bail StateRepository-Deployment.srd < E:\AppxRepair\repair-live.sql
```

`REPAIR COMMITTED SUCCESSFULLY` ve beklenen silme sayıları görünmeli. Bu mesaj SQL işleminin kaydedildiğini bildirir; Windows'un çalışacağını garanti etmez. Hata olursa tekrar çalıştırmayın. Ardından tekrar salt okunur diagnose çalıştırın; üç orphan sayısı sıfır, quick_check `ok`, geçerli paket ve dosya sayıları aynı olmalıdır. WAL içeriği geçerli SQLite durumunun parçasıdır; WAL/SHM dosyalarını elle silmeyin.

```cmd
wpeutil reboot
```

## 8. Windows sonrası doğrulama

Yönetici PowerShell:

```powershell
Get-Service StateRepository, AppXSvc, InstallService
(Get-AppxPackage -AllUsers).Count
```

Başlat, Store, Hesap Makinesi gibi uygulamaları kontrol edin. Daha önce hata veren güvenilir bir uygulamayı Store'dan kurun. İsterseniz güvenilir yerel MSIX paketini `Add-AppxPackage -Path "C:\path\app.msix"` ile yükleyin. Kurulumun ardından `Get-AppxPackage -Name <paket-adı>` ile `Status : Ok`, `IsPartiallyStaged : False` değerlerini kontrol edin (yer tutucuyu değiştirin). Başka bir uygulama ile de deneyin. Hizmetlerin bazıları tetiklemeli başlatılır; her zaman Running olmaları gerekmez. Yedekleri, sistem kararlılığı doğrulanana kadar saklayın.

## 9. Hata veya geri dönüş

- SQL hata verirse tekrar çalıştırmayın; WinRE'de kalın ve hatayı not edin. Başarı mesajı yoksa commit gerçekleşmiş mi varsaymayın. Salt okunur teşhisle durumu kontrol edin.
- Windows henüz yeniden başlatılmadıysa ve commit sonrası geri dönmek gerekiyorsa aynı çevrimdışı oturumda, onarım öncesi **Deployment** ana dosyası ve eşleşen yan dosyaları bir takım olarak geri getirin. Önce mevcut onarım sonrası dosyaların da ayrı kopyasını alın. Machine değiştirilmediğinden onu gelişigüzel geri yüklemeyin.
- Örnek olarak gerçek dizinden `copy /v StateRepository-Deployment.srd* F:\AppxAfterRepair\` (önce yeni boş klasörü oluşturun) ile onarım sonrası takımı saklayın. Ardından uzman gözetiminde mevcut Deployment yan dosyalarını ayrı boş bir karantina klasörüne taşıyın; eski ana dosyayı mevcut ana dosyanın üzerine kopyalayın, yedekte bulunan WAL/SHM/journal dosyalarını aynı isimleriyle geri koyun. Eski ve yeni yan dosyaları karıştırmayın. Dosya izinlerini ve kopyaları doğrulayın. Arşiv yedeğinin kendisini değiştirmeyin.
- Windows bir kez açıldıysa Machine ve Deployment durumu değişmiş olabilir; eski veritabanlarını körlemesine geri yüklemeyin. Uzman desteği veya önceden alınan tam sistem imajı tercih edilir. Bu rehberde geri yükleme prosedürü gerçek Windows üzerinde denenmedi; otomatik restore betiği dağıtmıyoruz.
- Hata sürüyorsa yeni olay günlüklerini inceleyin ve Atlas'a raporlayın; farklı tabloları silerek devam etmeyin.

## 10. Vaka ve test kapsamı

Bkz. `CASE-STUDY.md`, `TEST-RESULTS.txt`. Bu dağıtımın SQL betikleri önceki vaka betiğinden geliştirilmiştir; yeni testler gerçek Windows değil sentetik SQLite veritabanlarında yapılmıştır. `test_sql.py` yalnızca geçici örnek veritabanları kullanır, Python 3 gerektirir ve Windows onarımı yapmaz. CLI nokta komutları, WinRE uyumluluğu ve dosya kopyalama/geri yükleme bu testlerin kapsamı dışındadır.

## Kaynak ve atıf

- AtlasOS issue #1763: https://github.com/Atlas-OS/Atlas/issues/1763
- AtlasOS PR #1764 (Ayberkyvs, orijinal onarım fikri ve güvenlik kontrolleri): https://github.com/Atlas-OS/Atlas/pull/1764
- AtlasOS Store rehberi: https://atlasos.net/docs/faq/microsoft-store/
- Microsoft AppX troubleshooting: https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting
- SQLite CLI: https://sqlite.org/cli.html ; PRAGMA: https://sqlite.org/pragma.html

Bu çalışma AtlasOS ile bağlantılı resmî bir ürün değildir. Kaynak kodun yeniden dağıtım koşullarını doğrulamadan upstream kodu kopyalayıp lisanslamayın; bu pakette bağımsız SQL uyarlaması vardır. Kişisel verileri ve gerçek veritabanlarını paylaşmayın.
