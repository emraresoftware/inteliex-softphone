import os
import ollama

def projeyi_oku(yol):
    print(f"📖 {yol} klasörü inceleniyor...")
    if not os.path.exists(yol):
        return "Hata: Klasör bulunamadı!"

    icerik_ozeti = ""
    # Klasördeki ilk 10 dosyayı ve içeriklerini hızlıca tara
    for root, dirs, files in os.walk(yol):
        if any(x in root for x in [".venv", "node_modules", ".git"]): continue
        for file in files:
            file_path = os.path.join(root, file)
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    # Dosyanın sadece ilk 100 karakterini al (AI'yı boğmamak için)
                    icerik_ozeti += f"\n--- {file} ---\n{f.read(100)}..."
            except:
                continue
            if len(icerik_ozeti) > 2000: break # Sınırı aşma
    
    return icerik_ozeti

def ai_analiz_et(veriler):
    print("🧠 Qwen 2.5 Coder verileri işliyor...")
    prompt = f"Aşağıdaki proje verilerini incele ve bu projenin ne işe yaradığını açıkla:\n{veriler}"
    
    response = ollama.chat(model='qwen2.5-coder:14b', messages=[
        {'role': 'user', 'content': prompt}
    ])
    return response['message']['content']

if __name__ == "__main__":
    # Klasör yolunu tam olarak buraya yaz (Mac yolu)
    HEDEF_YOL = "/Users/emre/Dergah/projects/dergah" 
    
    veriler = projeyi_oku(HEDEF_YOL)
    if "Hata" not in veriler:
        analiz = ai_analiz_et(veriler)
        print("\n" + "="*50)
        print("🚩 PROJE ANALİZ SONUCU:")
        print(analiz)
        print("="*50)
    else:
        print(veriler)