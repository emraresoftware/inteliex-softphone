# FreePBX WebRTC Hazirligi

Bu dokuman, Inteliex Softphone MVP'sini Asterisk / FreePBX tarafina baglamak icin gereken ilk ayarlari listeler.

## 1. Sertifika ve HTTPS

- FreePBX web arayuzu HTTPS ile calismali.
- Gecerli bir TLS sertifikasi kullanin.
- Mobil istemci testlerinde self-signed sertifika yerine guvenilir bir sertifika tercih edin.

## 2. PJSIP Extension

Her test kullanicisi icin ayri bir PJSIP extension olusturun.

Onerilen ilk alanlar:

- Transport: WSS veya TLS ile uyumlu PJSIP
- Media Encryption: DTLS-SRTP
- ICE Support: aktif
- RTCP Mux: aktif
- Rewrite Contact: aktif
- Force rport: aktif
- Direct Media: kapali

## 3. Asterisk SIP Settings

FreePBX icinde su basliklari kontrol edin:

- Chan SIP kapali olabilir, PJSIP acik olmali
- TLS transport aktif olmali
- WSS aktif olmali
- RTP port araligi firewall tarafinda acik olmali
- External address ve local network alanlari dogru girilmeli

## 4. Codec Secimi

MVP icin ilk tercih:

- Opus
- PCMU
- PCMA

Ilk testlerde codec listesini dar tutmak, ses pazarligindaki sorunlari daha hizli ayristirir.

## 5. NAT ve Firewall

Mobil istemciler icin en sik problem NAT kaynaklidir.

Kontrol listesi:

- FreePBX public IP veya dogru reverse proxy arkasinda mi
- 8089 veya kullanilan WSS portu erisilebilir mi
- RTP port araligi acik mi
- STUN gerekiyorsa istemciye tanimlandi mi
- TURN gerekiyorsa kurumsal ag senaryosu icin hazir mi

## 6. FreePBX Tarafinda Test Kullanici Bilgisi

Ilk uygulama testleri icin her hesap icin su alanlari kaydedin:

- Display name
- Username / extension
- SIP password
- Domain
- WSS URL

Bu alanlar uygulamadaki hesap ekleme ekranina bire bir karsilik gelir.

## 7. Mobil Taraf Icin Gercekci Beklenti

MVP asamasinda:

- Uygulama acikken registration ve cagri akisi test edilir
- Uygulama arka plandayken surekli registration kararsiz olabilir
- Uygulama kapaliyken gelen cagri icin push tabanli uyandirma gerekir

Bu nedenle ilk milestone icin hedef, foreground stabilitesi olmalidir.

## 8. Sonraki Teknik Baglanti

Uygulama tarafinda sonraki entegrasyon sirası:

1. sip_ua ile register
2. Gelen ve giden session event'leri
3. flutter_webrtc ile media stream kontrolu
4. Secure storage ile hesap saklama
5. Drift veya sqflite ile cagri gecmisi

## 9. iOS ve Android Test Notlari

- iOS tarafinda sertifika zinciri ve WSS guveni erken asamada test edilmelidir.
- Android tarafinda farkli vendor cihazlarda mikrofon, hoparlor ve bluetooth gecisleri ayni davranmaz.
- Her iki platform icin ilk test hedefi foreground sesli cagri olmali, background gelen cagri daha sonra ele alinmalidir.
