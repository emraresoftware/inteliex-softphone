from playwright.sync_api import sync_playwright

def hayalet_uyandi():
    print("Dergahın kapıları açıldı...")
    
    with sync_playwright() as p:
        # headless=True -> Görünmez mod (hayalet). Ekranda hiçbir şey açılmaz.
        browser = p.chromium.launch(headless=True) 
        page = browser.new_page()
        
        print("Hayalet işçi uyandı! Hedefe sessizce gidiliyor... 👻")
        
        # Test için Google'a gidiyoruz
        page.goto("https://google.com")
        
        print(f"Başarıyla ulaşılan yer: {page.title()}")
        print("Görev tamamlandı, iz bırakmadan çıkılıyor.")
        
        browser.close()

if __name__ == "__main__":
    hayalet_uyandi()