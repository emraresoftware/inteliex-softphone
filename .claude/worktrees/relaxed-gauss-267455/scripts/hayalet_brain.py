import ollama
from playwright.sync_api import sync_playwright
import time

def gemini_web_soru_sor(soru):
    with sync_playwright() as p:
        print("Hayalet, Gemini Web arayüzüne sızıyor... 👻")
        browser = p.chromium.launch_persistent_context('user_data', headless=True) # Arka planda çalışsın
        page = browser.new_page()
        
        page.goto("https://gemini.google.com/app")
        
        # Sayfanın yüklenmesi ve input alanının gelmesi için bekle
        print("Zihin bağlantısı bekleniyor...")
        page.wait_for_selector('div[role="textbox"]', timeout=30000)
        
        # Soruyu yaz ve gönder
        page.fill('div[role="textbox"]', soru)
        page.keyboard.press("Enter")
        
        print("Gemini düşünüyor... (10 sn bekleniyor)")
        time.sleep(10) # Cevabın yazılması için süre veriyoruz
        
        # En son cevabı çek (Gemini'nin cevap kutucuğu seçicisi)
        cevaplar = page.locator('message-content').all_text_contents()
        son_cevap = cevaplar[-1] if cevaplar else "Cevap alınamadı."
        
        browser.close()
        return son_cevap

def llama_analiz_et(gelen_strateji):
    print("\n--- M5 Pro (Llama 3.2) Görevi Devraldı ---")
    response = ollama.chat(model='llama3.2', messages=[
        {'role': 'user', 'content': f"Şu stratejiyi analiz et: {gelen_strateji}"},
    ])
    return response['message']['content']

if __name__ == "__main__":
    gorev = "Emare Hub için otonom bir dosya düzenleyici yazmak istiyoruz, yol haritası çıkar."
    
    # 1. Hayalet benim web arayüzüme gider
    strateji = gemini_web_soru_sor(gorev)
    print(f"💡 Gemini'den (Web) Gelen Cevap: {strateji[:150]}...")
    
    # 2. Alınan cevabı Llama'ya (M5 Pro) paslar
    sonuc = llama_analiz_et(strateji)
    
    print("\n" + "="*50)
    print("🏁 HAYALET KÖPRÜSÜ ANALİZ SONUCU:")
    print(sonuc)
    print("="*50)