import time
import ollama
import pyperclip
import pyautogui
from playwright.sync_api import sync_playwright

# AYARLAR
GEMINI_URL = "https://gemini.google.com/app"
USER_DATA_DIR = "user_data" # Daha önce giriş yaptığın klasör
LOCAL_MODEL = "qwen2.5-coder:14b"

def gemini_ile_konus(sayfa, mesaj):
    print("🛰️ Hayalet, Gemini'ye fısıldıyor...")
    # Mesaj kutusunu bul ve yaz
    sayfa.wait_for_selector('div[role="textbox"]')
    sayfa.fill('div[role="textbox"]', mesaj)
    sayfa.keyboard.press("Enter")
    
    # Cevabın gelmesini bekle (Yazma animasyonu bitene kadar)
    print("⏳ Gemini'nin cevabı bekleniyor...")
    time.sleep(15) # Web arayüzü olduğu için biraz süre tanıyalım
    
    # En son cevabı çek
    cevaplar = sayfa.locator('message-content').all_text_contents()
    return cevaplar[-1] if cevaplar else "Hata: Cevap alınamadı."

def vscode_insa_et(kod):
    print("🤖 Qwen 2.5 Coder talimatı aldı, VSCode'a geçiliyor...")
    time.sleep(2)
    
    # Yeni dosya ve yapıştırma
    pyautogui.hotkey('command', 'n')
    time.sleep(1)
    pyperclip.copy(kod)
    pyautogui.hotkey('command', 'v')
    time.sleep(1)
    
    # Kaydetme simülasyonu
    pyautogui.hotkey('command', 's')
    time.sleep(1)
    pyperclip.copy("otonom_update.py")
    pyautogui.hotkey('command', 'v')
    # pyautogui.press('enter') # Kaydetmek istersen aktif et
    print("✅ Kod VSCode'a işlendi.")

def otonom_dongu():
    with sync_playwright() as p:
        # Arka planda tarayıcıyı aç (headless=True arka planda çalıştırır)
        browser = p.chromium.launch_persistent_context(USER_DATA_DIR, headless=True)
        page = browser.new_page()
        page.goto(GEMINI_URL)
        
        rapor = "Sistem başlatıldı. Emare Hub için sunucu yönetim sistemi kurmak istiyoruz. İlk adım ne olmalı?"
        
        while True:
            # 1. Gemini Web'den strateji al
            strateji = gemini_ile_konus(page, rapor)
            print(f"💡 Gemini Stratejisi: {strateji[:100]}...")
            
            # 2. Lokal Qwen 14B ile kodu temizle
            print(f"🧠 {LOCAL_MODEL} işleniyor...")
            qwen_istek = f"Şu stratejiyi sadece Python koduna dönüştür: {strateji}"
            res = ollama.chat(model=LOCAL_MODEL, messages=[{'role': 'user', 'content': qwen_istek}])
            temiz_kod = res['message']['content']
            
            # 3. VSCode üzerinde fiziksel işlem yap
            vscode_insa_et(temiz_kod)
            
            # 4. Durumu tekrar raporla ve döngüyü sürdür
            rapor = f"Kod yazıldı. Sonuç başarılı. Sıradaki adıma geç: {strateji[:50]}"
            print("🔄 Döngü tamamlandı. Bir sonraki aşamaya geçiliyor...")
            
            # Gözlem için mola (Senin kontrolün için)
            input("\n--- Devam etmek için Enter'a bas... ---")

if __name__ == "__main__":
    otonom_dongu()