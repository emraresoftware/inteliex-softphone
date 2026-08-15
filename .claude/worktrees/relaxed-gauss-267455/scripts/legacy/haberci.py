import subprocess
from playwright.sync_api import sync_playwright

def beyni_uyandir(metin):
    # Lokal Ollama'ya (Llama 3.2) soruyoruz
    prompt = f"Şu metni 1 cümlede özetle: {metin}"
    sonuc = subprocess.check_output(["ollama", "run", "llama3.2", prompt], text=True)
    return sonuc

def hayalet_ve_beyin():
    print("Dergah operasyonu başlıyor... 👻🧠")
    
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        
        # Örnek: Joygame'in 'Hakkımızda' sayfasına gidelim (Az önce konuştuğumuz yer)
        print("Hedef: Joygame Hakkımızda sayfası...")
        page.goto("https://www.joygame.com/hakkimizda")
        
        # Sayfadaki ana metni çekiyoruz
        icerik = page.inner_text("body")[:500] # İlk 500 karakter yeterli
        
        print("Veri çekildi, lokal beyne (Ollama) gönderiliyor...")
        ozet = beyni_uyandir(icerik)
        
        print("-" * 30)
        print(f"LOKAL AI ÖZETİ: {ozet}")
        print("-" * 30)
        
        browser.close()

if __name__ == "__main__":
    hayalet_ve_beyin()