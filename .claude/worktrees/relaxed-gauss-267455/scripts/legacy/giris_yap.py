from playwright.sync_api import sync_playwright

def oturum_ac():
    with sync_playwright() as p:
        # headless=False olmalı ki tarayıcıyı göresin ve şifreni yazasın
        browser = p.chromium.launch_persistent_context(
            'user_data', 
            headless=False # Burası mutlaka False kalsın!
        )
        page = browser.new_page()
        
        # BURAYI DEĞİŞTİR: Hangi siteye giriş yapacaksan o adresi yaz
        # Örn: "https://gmail.com" veya "https://chatgpt.com"
        target_url = "https://gemini.google.com/app" 
        
        print(f"Hedefe gidiliyor: {target_url}")
        page.goto(target_url)
        
        print("-" * 30)
        print("ŞİMDİ SIRA SENDE:")
        print("1. Açılan tarayıcı penceresinden kullanıcı adın ve şifrenle GİRİŞ YAP.")
        print("2. Giriş işlemi bittikten ve ana sayfayı gördükten sonra buraya dön.")
        print("3. Terminal'de Enter'a basarak oturumu kaydet.")
        print("-" * 30)
        
        input("Giriş tamamlandı mı? (Devam etmek için Enter'a bas): ")
        
        browser.close()
        print("Harika! Oturum 'user_data' klasörüne mühürlendi. Artık hayalet seni tanıyor. 👻")

if __name__ == "__main__":
    oturum_ac()