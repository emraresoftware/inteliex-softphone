import subprocess
from playwright.sync_api import sync_playwright

def beyni_uyandir(metin):
    print("Lokal AI (Llama 3.2) veriyi analiz ediyor... 🧠")
    # Promptu biraz daha netleştirelim
    prompt = f"Aşağıdaki e-postaları Türkçe olarak çok kısa özetle ve önemli bir şey var mı söyle:\n{metin}"
    try:
        sonuc = subprocess.check_output(["ollama", "run", "llama3.2", prompt], text=True)
        return sonuc
    except Exception as e:
        return f"Ollama hatası: {e}"

# ... (üst taraf aynı)
def otonom_operasyon():
    with sync_playwright() as p:
        print("Lambalar yanıyor, hayaleti izliyoruz... 👀")
        
        # headless=False yapıyoruz ki ekran açılsın, ne olduğunu görelim
        browser = p.chromium.launch_persistent_context('user_data', headless=False) 
        page = browser.new_page()
        
        try:
            print("Gmail'e gidiliyor...")
            page.goto("https://mail.google.com/mail/u/0/#inbox", timeout=60000) 
            
            # 30 saniye boyunca mailleri bekle
            print("Maillerin yüklenmesi bekleniyor (30 sn)...")
            page.wait_for_selector('.zA', timeout=30000) 
# ... (alt taraf aynı)
            
            # Gelen kutusundaki ilk 5 mailin metnini çek
            mailler = page.locator('.zA').all_text_contents()[:5]
            ham_veri = "\n---\n".join(mailler)
            
            if not ham_veri:
                print("Mail bulunamadı veya sayfa henüz yüklenmedi.")
            else:
                print(f"{len(mailler)} adet mail satırı yakalandı. Analize gidiyor...")
                analiz_sonucu = beyni_uyandir(ham_veri)
                
                print("\n" + "="*40)
                print("GELEN KUTUSU ÖZETİ:")
                print(analiz_sonucu)
                print("="*40 + "\n")

        except Exception as e:
            print(f"Hata oluştu: {e}")
        
        finally:
            browser.close()
            print("Dergah operasyonu kapandı.")

# İŞTE BURASI ÇOK ÖNEMLİ: Kodu çalıştıran kısım
if __name__ == "__main__":
    otonom_operasyon()