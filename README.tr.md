[English](README.md) | [中文](README.zh-CN.md) | [Español](README.es.md) | [Português](README.pt-BR.md) | **Türkçe**

![MSI Center PSU GET_ALL düzeltmesi](docs/images/banner.jpg)

# MSI Center: "Read data of PSU GET_ALL fail" hatası için düzeltme

USB izleme destekli bir MSI güç kaynağınız (**MEG Ai1300P** gibi) ve MSI Center kuruluysa, Power Supply Unit günlüğünüz büyük olasılıkla şuna benzer satırlarla doludur:

```
10-18-2026 21:50:01.933 | [ERROR] Read data of PSU GET_ALL fail... (6)
```

Dakikada 3-5 kez, günde yaklaşık 5.000 kez görünürler. **Güç kaynağınız da USB bağlantınız da sağlam.** Hata MSI Center'ın kendisindeki bir bug'dan kaynaklanıyor ve bu repo onu yamalıyor.

## Sorun ne?

MSI Center saniyede bir güç kaynağından tüm ölçümlerini ister (komut `0xE0`, GET_ALL). Cevap, PMBus LINEAR11 değerlerinden oluşan bir listedir: +12V, raylara ait akımlar, +5V, +3,3V ve diğerleri.

Modülün cevap kontrolü (`API_Power Supply Unit.dll` 1.0.0.38 içindeki `cPSU.Get`), 3. bayt `0xFE` olduğunda cevabı hata sayar. Bu kural tüm komutlar için ortaktır. Oysa GET_ALL'da 3. bayt, **+12V ölçümünün** düşük baytıdır. Güç kaynağı tam olarak **11,969 V** (`0xD2FE`) bildirdiğinde MSI geçerli bir cevabı çöpe atar. Ara vermeden art arda 6 kez yeniden dener, her seferinde aynı voltajı alır ve `GET_ALL fail` yazar. Parantez içindeki sayı hata kodu değil, çalışan bir hata sayacıdır.

Yani hata sıklığı, +12V hattınızın tesadüfen 11,969 V'ta durup durmadığına bağlıdır. USB, kablolar, AIDA64/HWiNFO/iCUE veya yükle hiçbir ilgisi yok. Ayrıntılar ve kanıtlar: [docs/technical.md](docs/technical.md) (İngilizce).

![MSI Center neden GET_ALL fail yazıyor](docs/images/3-cause.png)

## Bu sorun bende var mı?

PowerShell'de çalıştırın (yönetici gerekmez):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check-log.ps1
```

Bugünün günlüğündeki `GET_ALL fail` satırlarını saat başına sayar.

![Düzeltmeden önce ve sonra güç kaynağı günlüğü](docs/images/5-log.png)

## Yama ne yapıyor?

`cPSU.Get` içine 3 IL talimatı ekler: `if (cmd == 0xE0) 0xFE kontrolünü atla`. Modülde başka hiçbir şey değişmez, diğer komutlar özgün kontrolü kullanmaya devam eder.

MEG Ai1300P üzerinde 10 dakika boyunca yapılan ölçüm:

| | günlükteki hatalar | GET_ALL istekleri | +12V = 11,969 V olan ve kabul edilen cevaplar |
|---|---|---|---|
| orijinal | 36 | 1199 | 0 |
| yamalı | **0** | **594** (saniyede bir) | **67 / 67** |

Pratikte:
- günlük temiz kalır;
- ölçümlerden hiçbir saniye kaybolmaz;
- güç kaynağı artık 6'lı yeniden deneme yağmuruna tutulmaz.

Güç kaynağının davranışına dokunulmaz. Single/multi rail modu, OCP ve fan ayarları etkilenmez.

**Bu repo hiçbir MSI dosyası içermez.** Yamalayıcı *sizin kendi* kurulu DLL'inizi alır, SHA-256 değerini kontrol eder ve bir kopyasını yamalar.

![Düzeltmeden önce ve sonra hatalar](docs/images/4-before-after.png)

## En kolay yol: bir yapay zeka ajanına yaptırın

Bir yapay zeka kodlama ajanı kullanıyorsanız (Claude Code, Codex, Cursor, Copilot agent mode vb.), bu repo klasörünü onda açın ve şunu yapıştırın:

```
Bu klasördeki AGENTS.md dosyasını oku ve ona göre PC'min MSI Center "GET_ALL fail" bug'ından etkilenip etkilenmediğini kontrol et; etkileniyorsa düzeltmeyi uygula. Sistemimde değişiklik yapan her adımdan önce bana sor.
```

[AGENTS.md](AGENTS.md) ajana her şeyi güvenli biçimde yaptırır:
- günlüğü kontrol eder;
- modülün hash'ini doğrular ve desteklenmeyen sürümleri reddeder;
- gerekirse .NET SDK'yı kurar;
- nelerin değişeceğini açıklar ve yapmadan önce sorar;
- yükleyiciyi çalıştırır;
- sonucu doğrular.

## İndirme

Bu sayfada **Code → Download ZIP** deyip istediğiniz yere çıkarın. Ya da `git clone https://github.com/lostintired/msi-psu-getall-fix` kullanın.

## Gereksinimler

- Windows 10/11 ve Power Supply Unit bileşenli MSI Center, modül sürümü **1.0.0.38**. Diğer sürümler reddedilir ve hiçbir şey değiştirilmez.
- [.NET 10 SDK](https://dotnet.microsoft.com/download), yamalayıcıyı derlemek için kullanılır.
- Yönetici hakları.

## Kurulum

Repo klasöründe, **yönetici olarak** çalıştırılan PowerShell'de çalıştırın:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

Betik şunları yapar:
1. modülün özgün 1.0.0.38 olduğunu kontrol eder (SHA-256 `F7833895…0274BB`);
2. yedek olarak `C:\Program Files\MsiPsuGetAllFix\` klasörüne kopyalar;
3. yamalayıcıyı derler, kopyayı yamalar ve sonucu kontrol eder (SHA-256 `6535FEB9…5D2B46`; yama deterministiktir);
4. modülü yerine koyar ve `MSI_Center_Service` hizmetini yeniden başlatır. MSI Center tüm bileşenlerini yeniden yükler, bu birkaç saniye sürer;
5. **"MSI PSU GET_ALL fix guard"** adlı zamanlanmış görevi kaydeder. Oturum açılışında ve her gün çalışır:
   - bir MSI Center güncellemesi özgün 1.0.0.38'i geri getirdiyse yeniden yamalar;
   - *farklı* bir sürüm çıkarsa hiçbir şeyi değiştirmez ve bildirim gösterir. MSI bug'ı düzeltmiş olabilir ya da yamalayıcının güncellenmesi gerekebilir.

Görevi atlamak için `-NoGuard`, MSI Center varsayılan konumda değilse `-MsiCenterDir "D:\...\MSI Center"` kullanın.

Sonrasında kontrol: birkaç dakika sonra `scripts\check-log.ps1` çalıştırın. Kurulum saatinden sonra yeni satır görünmemeli.

## Kaldırma

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\MsiPsuGetAllFix\uninstall.ps1"
```

Özgün modülü geri yükler, hizmeti yeniden başlatır, görevi ve kurulum klasörünü siler.

## Dikkat edilmesi gerekenler

- Yamalı DLL üzerindeki MSI Authenticode imzası artık geçerli değildir. MSI Center bunu kontrol etmez (bileşenleri `Assembly.LoadFile` ile yükler), ancak bir antivirüs uyarı verebilir.
- Yalnızca 1.0.0.38 modülü desteklenir. İleride gelecek bir MSI güncellemesi bug'ı düzeltebilir ya da kodu değiştirebilir. İki durumda da koruma görevi yeni modüle dokunmaz.
- Tek bir sistemde test edildi: MEG Ai1300P (USB `VID_0DB0&PID_56D4`), MSI Center 2.0.74.0, SDK 3.2026.0911.01. Aynı kod yolu iki güç kaynağı modeline daha hizmet ediyor (ürün kimlikleri 59209 ve 51691). Diğer modellerden gelen geri bildirimler memnuniyetle karşılanır.
- Kullanım riski size aittir. MSI ile bir bağlantısı yoktur. Bug MSI desteğine bildirildi.

## Lisans

Bu repodaki kod MIT lisanslıdır. MSI Center ve bileşenleri MSI'a aittir.
