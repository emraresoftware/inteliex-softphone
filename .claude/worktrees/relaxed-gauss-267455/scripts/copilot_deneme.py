import pyautogui
import time
import ollama
import pyperclip # Klavye hatalarını bitiren kahraman

def hatasiz_yaz(metin):
    # Metni panoya kopyala
    pyperclip.copy(metin)
    time.sleep(1)
    # Cmd + V ile yapıştır (Mac için)
    pyautogui.hotkey('command', 'v')

def otonom_islem():
    print("🤖 Llama kodu hazırlıyor...")
    istek = "Ekrana 'Sistem Ayakta' yazan basit bir Python kodu."
    response = ollama.chat(model='llama3.2', messages=[{'role': 'user', 'content': istek}])
    kod = response['message']['content']

    print("🚀 5 saniye içinde VSCode'da kodun yazılmasını istediğin yere tıkla!")
    time.sleep(5)

    # 1. Yeni dosya aç
    pyautogui.hotkey('command', 'n')
    time.sleep(1)

    # 2. Hatasız yapıştır
    hatasiz_yaz(kod)
    
    # 3. Kaydetme ekranı
    pyautogui.hotkey('command', 's')
    time.sleep(1)
    pyperclip.copy("otonom_sonuc.py")
    pyautogui.hotkey('command', 'v')
    # pyautogui.press('enter') # İstersen bunu açıp direkt kaydettirebilirsin

if __name__ == "__main__":
    otonom_islem()