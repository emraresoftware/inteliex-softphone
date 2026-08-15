import time
import os
import threading
from pynput import mouse, keyboard
import pyautogui
from PIL import Image
import datetime

# AYARLAR
LOG_DIR = "data/gozlem_gunlugu"
SCREENSHOT_DIR = f"{LOG_DIR}/ekran_goruntuleri"
os.makedirs(SCREENSHOT_DIR, exist_ok=True)

class DervisGozu:
    def __init__(self):
        self.son_hareket = time.time()
        self.islem_listesi = []
        print("👁️ Derviş Gözü açıldı. Müşahitlik başlıyor...")

    def ekran_yakala(self, sebep):
        """Ekran görüntüsü alır ve neden alındığını kaydeder."""
        zaman = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        dosya_adi = f"{SCREENSHOT_DIR}/gozlem_{zaman}.png"
        pyautogui.screenshot(dosya_adi)
        print(f"📸 Ekran yakalandı: {sebep}")
        return dosya_adi

    def niyet_analizi(self, eylem, detay):
        """
        Burada Qwen veya Gemini devreye girer. 
        Şu an için sadece log tutuyoruz, ama 'Vision' modelin varsa görüntüyü buraya besleyeceğiz.
        """
        gunluk_satiri = f"[{datetime.datetime.now()}] EYLEM: {eylem} | DETAY: {detay}"
        with open(f"{LOG_DIR}/niyet_defteri.txt", "a") as f:
            f.write(gunluk_satiri + "\n")

    # Fare Hareketleri
    def on_click(self, x, y, button, pressed):
        if pressed:
            self.niyet_analizi("Fare Tıklama", f"Konum: {x, y} | Buton: {button}")
            # Eğer sağ tıklandıysa veya önemli bir yere tıklandıysa ekran alabiliriz
            # self.ekran_yakala("Tıklama Anı")

    # Klavye Hareketleri
    def on_press(self, key):
        try:
            k = key.char  # Harf tuşları
        except AttributeError:
            k = str(key)  # Özel tuşlar (Enter, Shift vb.)

        self.islem_listesi.append(k)
        
        # Enter'a basıldığında kullanıcının bir komutu bitirdiğini varsayıp analiz yapalım
        if key == keyboard.Key.enter:
            eylem_serisi = "".join(self.islem_listesi[-20:]) # Son 20 karakter
            self.niyet_analizi("Klavye Girişi (Enter)", f"Yazılan: {eylem_serisi}")
            self.ekran_yakala(f"Enter Basıldı: {eylem_serisi}")
            self.islem_listesi = []

    def baslat(self):
        # Dinleyicileri thread olarak başlatıyoruz
        klavye_dinleyici = keyboard.Listener(on_press=self.on_press)
        fare_dinleyici = mouse.Listener(on_click=self.on_click)

        klavye_dinleyici.start()
        fare_dinleyici.start()
        
        klavye_dinleyici.join()
        fare_dinleyici.join()

if __name__ == "__main__":
    goz = DervisGozu()
    goz.baslat()