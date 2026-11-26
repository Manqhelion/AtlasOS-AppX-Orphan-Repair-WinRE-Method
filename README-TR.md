# AtlasOS AppX Orphan Repair — WinRE yöntemi

**Topluluk rehberi / deneysel manuel onarım • 26 Kasım 2026 • v0.1 — rehber revizyonu 3**

Microsoft Store, AppX ve MSIX yüklemelerinde `0x80073CF9` / iç hata `0x80070490` (Evaluated state) için hedefli onarım. Windows'u yeniden kurmadan çözülen bir AtlasOS 0.4.1 vakasına dayanır. AtlasOS veya Microsoft tarafından onaylanmış bir araç değildir. Her kurulum hatasını çözmez.

> **ÖNEMLİ:** Windows sistem veritabanı değiştirilecektir. Yanlış disk, farklı şema veya tutarsız yedek sistemi bozabilir. Tam sistem imajı ve kişisel dosya yedeği olmadan canlı onarıma geçmeyin. Öncelikle güncel resmî Atlas Store onarımını değerlendirin. Bu rehber deneyimli kullanıcılar içindir; şüphede kalırsanız durun.

> **Resmî çözüm kullanılabilir olduğunda onu tercih edin:** Bu WinRE rehberi, otomatik onarım henüz kullanıma sunulmamışken etkilenen kurulumlar için deneysel bir manuel çözümdür. [AtlasOS PR #1764](https://github.com/Atlas-OS/Atlas/pull/1764) birleştirildiğinde **ve kullandığınız Atlas Manager sürümüne dahil edildiğinde**, **Get ready (Hazırlık)** aşamasındaki resmî onarımı tercih edin. Bu onarım güvenlik kontrolleri ve yedekleme ile temizliği otomatik yapar; bu sorun için manuel WinRE adımlarına ve SQL betiklerine artık ihtiyaç kalmaması beklenir. Kullanılabilirlik durumunu PR sayfasından ve resmî sürüm notlarından kontrol edin. Bu rehber, teknik referans ve etkilenen eski kurulumlar için erişilebilir kalacaktır.

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

Bu pakette sadece üç hedef tablonun Machine tarafında bulunmayan paket kimlikli satırları silinir. Machine veritabanı salt okunur açılır. Bütün veritabanı silinmez. Referans tablolarında yeni yabancı anahtar ihlali oluşursa, geçerli kayıt sayısı değişirse veya tetikleyici ek satır değişiklikleri yaparsa işlem durur ve geri alınır; mevcut hataları onarmaya çalışmaz. Bu, Atlas önerisinin WinRE uyarlamasıdır, orijinal Atlas kodu değildir.

### Sahipsiz kayıtlar kurulumu nasıl engelleyebilir?

`File` tablosundaki satır fiziksel dosyanın kendisi değil, bir dosya hakkında metadata kaydıdır. Örneğin Package=999 olan bir kayıt varsa ama Machine veritabanında 999 numaralı paket yoksa ilişki kopuktur. PR #1764'teki hipoteze göre Evaluated aşamasında Windows yeni paketteki dosyaların özetlerini (`File.Digest`) mevcut dosyalarla karşılaştırarak hardlink yoluyla yeniden kullanımı değerlendirebilir. Eşleşen kayıt artık var olmayan pakete aitse gerekli paket bilgisi bulunamaz; `0x80070490` (element not found) oluşabilir. Dış hata `0x80073CF9` genel kurulum başarısızlığıdır. Bu mekanizma Microsoft tarafından belgelenmiş değildir; gözlemler ve upstream kod açıklamasına dayanan bir çıkarımdır. Bizim vakamızda silme sonrası kurulumların çalışması hipotezi destekler, her kaydın tek tek hataya neden olduğunu kanıtlamaz.

**Uyumluluk sınırı:** Microsoft bu özel veritabanı şemasını desteklenen bir düzenleme arayüzü olarak sunmaz. Windows sürümleri arasında tablolar, tetikleyiciler ve ilişkiler değişebilir. Başarılı SQL testi tek başına Windows uyumluluğunu garanti etmez. Hata imzası, tam sistem imajı, çevrimdışı yedek, çalışma kopyası testi ve onarım sonrası doğrulama zorunludur. Bu rehberdeki sayılar ve SQL sorguları başka bir PC'nin veritabanını değiştirmek için sabit değerler içermez.

## 3. Hazırlık (normal Windows)

- Bekleyen Windows/Atlas güncellemesi varsa önce güvenle tamamlayın. Devam eden güncelleme sırasında onarım yapmayın. Kurtarma anahtarını güvenli biçimde saklayın; BitLocker'ı sırf bu rehber için kapatmayın.
- Harici diske tam sistem imajı ve kişisel dosya yedeği alın; kurtarma ortamından erişilebilir olduğunu doğrulayın. Sistem imajı geri yüklemesinin sonradan yapılan değişiklikleri kaybettirebileceğini unutmayın.
- GitHub’da **Code → Download ZIP** seçin. İçeriği `C:\AppxRepair` klasörüne çıkarın; SQL dosyaları doğrudan bu klasörde olmalı. Windows normalde başka bir sürücüdeyse bu hazırlık adımında ve SQLite sürüm kontrolünde o harfi kullanın.
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

**Sürücü harflerini yalnızca burada belirleyin.** Örnekte E: kurulu Windows, F: harici yedek diski. Bunları kendi doğruladığınız harflerle değiştirin. X: genellikle WinRE RAM diskidir; kullanmayın. Farklı ProgramData konumu varsa durun.

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

Yalnızca ilk iki satırı kendi sisteminize göre değiştirin. DEST yeni, henüz var olmayan bir klasör olmalı; mevcutsa farklı isim seçip değişkenleri yeniden tanımlayın. Sonraki komutları aynen yazın. Değişkenler yalnızca bu CMD oturumu boyunca geçerlidir; yeni pencere açarsanız tekrar tanımlayın. Sürücü harflerini yeniden doğrulayın.

```cmd
dir "%WIN%\Windows\System32\config\SYSTEM"
dir "%REPO%\StateRepository-*.srd*"
dir "%TOOLS%"
if exist "%DEST%" echo STOP - backup folder already exists
"%SQL%" -version
```

İki ana veritabanı, sqlite3.exe ve üç SQL dosyası mevcut olmalı. Harici yedek diskinin erişilebilir ve yeterli boş alana sahip olduğunu doğrulayın. Herhangi bir hata, STOP mesajı veya belirsizlik varsa devam etmeyin.

## 5. Çevrimdışı yedekleme (zorunlu)

Her komutu ayrı çalıştırın. Bir komut başarısız olursa sonrakine geçmeyin. Arşiv ve test klasörlerini aynı yeni yedek kökü altında oluşturun.

```cmd
cd /d "%REPO%"
mkdir "%BAK%"
copy /v "%DB%*" "%BAK%\"
copy /v "%MACHINE%*" "%BAK%\"
dir "%BAK%"
fc /b "%DB%" "%BAK%\%DB%"
fc /b "%MACHINE%" "%BAK%\%MACHINE%"
```

Her mevcut yan dosyayı (`-wal`, `-shm`, varsa `-journal`) da aşağıdaki komutlarla karşılaştırın. CMD komut isteminde tek `%S` kullanılır. Her fark veya hata durumunda durun; dosya boyutlarını ve sayılarını da kontrol edin. Arşiv yedeğini değiştirmeyin.

```cmd
for %S in (wal shm journal) do @if exist "%DB%-%S" fc /b "%DB%-%S" "%BAK%\%DB%-%S"
for %S in (wal shm journal) do @if exist "%MACHINE%-%S" fc /b "%MACHINE%-%S" "%BAK%\%MACHINE%-%S"
```

Ayrı çalışma kopyası oluşturun ve yalnızca onu test edin.

```cmd
mkdir "%TEST%"
copy /v "%BAK%\%DB%*" "%TEST%\"
copy /v "%BAK%\%MACHINE%*" "%TEST%\"
cd /d "%TEST%"
"%SQL%" -readonly "%MACHINE%" "PRAGMA quick_check;"
"%SQL%" -readonly "%DB%" "PRAGMA quick_check;"
```

Her iki sonuç da yalnızca `ok` olmalı. Salt okunur WAL erişimi hata verirse durun; yan dosyaları elle silmeyin.

## 6. Teşhis ve geri alınan test

Hâlâ çalışma kopyası klasöründeyken:

```cmd
"%SQL%" -bail -readonly "%DB%" < "%TOOLS%\diagnose.sql"
```

LivePackages > 0, LiveFiles > 0 ve Orphan_File <= LiveFiles olmalıdır. En az bir sahipsiz kayıt bulunmalı; üç `Unexpected_*_Package` sayısı da sıfır olmalı. Hiç yoksa bu onarım gereksizdir. Sayılar başka bilgisayardan kopyalanmaz. Şema hatası, SQL hatası veya quick_check != ok durumunda durun.

```cmd
"%SQL%" -bail "%DB%" < "%TOOLS%\repair-test.sql"
```

`TEST PASSED - NO CHANGES SAVED` görünmeli. Ardından diagnose.sql'yi aynı kopyada tekrar çalıştırıp sayılarının değişmediğini doğrulayın. Test başarısızsa canlı onarım yapmayın. Betik hata durumunda kapanır, açık işlem bağlantı kapanınca geri alınır. Hata kodunu yok saymayın.

## 7. Gerçek onarım (yalnızca WinRE'de)

Yedekleri, test sonucunu ve hata imzasını doğruladıysanız devam edin. Normal Windows içinde **çalıştırmayın**. Önce gerçek Windows dizinine geçin:

```cmd
cd /d "%REPO%"
dir StateRepository-*.srd*
"%SQL%" -bail -readonly "%DB%" < "%TOOLS%\diagnose.sql"
```

Sayılar çalışma kopyası ile aynı olmalı. Değilse durun ve yedekleme/teşhisi yeniden değerlendirin. Sonrasında:

```cmd
"%SQL%" -bail "%DB%" < "%TOOLS%\repair-live.sql"
```

`REPAIR COMMITTED SUCCESSFULLY` ve beklenen silme sayıları görünmeli. Bu mesaj SQL işleminin kaydedildiğini bildirir; Windows'un çalışacağını garanti etmez. Hata olursa tekrar çalıştırmayın. Ardından şu salt okunur teşhisi tekrar çalıştırın:

```cmd
"%SQL%" -bail -readonly "%DB%" < "%TOOLS%\diagnose.sql"
```

Üç orphan sayısı sıfır, quick_check `ok`, geçerli paket, File, manifest ve kaynak URI sayıları aynı olmalıdır. WAL içeriği geçerli SQLite durumunun parçasıdır; WAL/SHM dosyalarını elle silmeyin.

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
- Örnek olarak gerçek dizinden `copy /v "%DB%*" "%DEST%\after-repair\"` (önce yeni boş klasörü oluşturun) ile onarım sonrası takımı saklayın. Ardından uzman gözetiminde mevcut Deployment yan dosyalarını ayrı boş bir karantina klasörüne taşıyın; eski ana dosyayı mevcut ana dosyanın üzerine kopyalayın, yedekte bulunan WAL/SHM/journal dosyalarını aynı isimleriyle geri koyun. Eski ve yeni yan dosyaları karıştırmayın. Dosya izinlerini ve kopyaları doğrulayın. Arşiv yedeğinin kendisini değiştirmeyin.
- Windows bir kez açıldıysa Machine ve Deployment durumu değişmiş olabilir; eski veritabanlarını körlemesine geri yüklemeyin. Uzman desteği veya önceden alınan tam sistem imajı tercih edilir. Bu rehberde geri yükleme prosedürü gerçek Windows üzerinde denenmedi; otomatik restore betiği dağıtmıyoruz.
- Hata sürüyorsa yeni olay günlüklerini inceleyin ve Atlas'a raporlayın; farklı tabloları silerek devam etmeyin.

## 10. Vaka ve test kapsamı

Bkz. `CASE-STUDY.md`, `TEST-RESULTS.txt`. Bu dağıtımın SQL betikleri önceki vaka betiğinden geliştirilmiştir; 26 onarım modu testi gerçek Windows değil sentetik SQLite veritabanlarında yapılmıştır. Betikler NULL veya tam sayı olmayan paket kimliklerini, sıfır geçerli File kaydını, yeni yabancı anahtar ihlallerini, rowid bilgisi olmayan ihlalleri, tetikleyicilerden gelen ek satır değişikliklerini ve geçerli kayıt sayılarındaki değişimi reddeder. Bazı Windows sürümlerinde meşru tetikleyiciler bile bu ihtiyatlı kontrol nedeniyle onarımı durdurabilir; kontrolü atlamayın. `test_sql.py` yalnızca geçici örnek veritabanları kullanır, Python 3 gerektirir ve Windows onarımı yapmaz. CLI nokta komutları, WinRE uyumluluğu ve dosya kopyalama/geri yükleme bu testlerin kapsamı dışındadır.

## Kaynak ve atıf

- AtlasOS issue #1763: https://github.com/Atlas-OS/Atlas/issues/1763
- AtlasOS PR #1764 (Ayberkyvs, orijinal onarım fikri ve güvenlik kontrolleri): https://github.com/Atlas-OS/Atlas/pull/1764
- AtlasOS Store rehberi: https://atlasos.net/docs/faq/microsoft-store/
- Microsoft AppX troubleshooting: https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting
- SQLite CLI: https://sqlite.org/cli.html ; PRAGMA: https://sqlite.org/pragma.html

Bu çalışma AtlasOS ile bağlantılı resmî bir ürün değildir. Bu bağımsız SQL uyarlaması GPL-3.0 lisansıyla paylaşılmaktadır (LICENSE); Atlas projesi de GPL-3.0 lisanslıdır. Orijinal yaklaşımın kaynağı yukarıda belirtilmiştir. Kişisel verileri ve gerçek veritabanlarını paylaşmayın.
