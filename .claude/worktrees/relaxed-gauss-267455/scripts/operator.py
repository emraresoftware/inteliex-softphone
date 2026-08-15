import pyautogui
import time
import ollama

def vscode_islem_yap(komut_ve_kod):
    print("🤖 Lokal Operatör VSCode üzerinde çalışıyor...")
    
    # VSCode'u öne getir (Mac için Cmd+Tab veya direkt tıklama simülasyonu)
    # Varsayalım ki VSCode şu an açık ve aktif.
    
    # 1. Yeni dosya aç (Cmd + N)
    pyautogui.hotkey('command', 'n')
    time.sleep(1)
    
    # 2. Kodları yaz (Llama'dan gelen temiz kod)
    pyautogui.write(komut_ve_kod, interval=0.01)
    
    # 3. Kaydet (Cmd + S)
    pyautogui.hotkey('command', 's')
    print("✅ İşlem tamamlandı, dosya oluşturuldu.")

# Bu fonksiyon seninle (Gemini) konuşup kararı Llama'ya paslayan döngüye bağlanacak