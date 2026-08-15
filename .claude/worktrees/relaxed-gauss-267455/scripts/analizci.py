import os
import ollama

def proje_tara(proje_yolu):
    # Projenin içindeki dosyaların listesini çıkarır
    dosyalar = []
    for root, dirs, files in os.walk(proje_yolu):
        for file in files:
            if not any(x in root for x in [".venv", "node_modules", ".git"]): # Çöpleri ele
                dosyalar.append(file)
    return dosyalar[:30] # İlk 30 dosyayı analiz için alalım

def analiz_et(dosya_listesi, proje_adi):
    print(f"🧠 Llama 3.2, '{proje_adi}' projesini inceliyor...")
    
    prompt = f"Şu dosya listesine sahip bir yazılım projesini analiz et: {dosya_listesi}. Bu proje hangi dille yazılmış, amacı ne olabilir ve 'Mersin Protokolü' (temiz kod ve otonomi) için ilk olarak ne yapılmalı? Türkçe ve maddeler halinde söyle."
    
    response = ollama.chat(model='llama3.2', messages=[
        {'role': 'user', 'content': prompt},
    ])
    return response['message']['content']

if __name__ == "__main__":
    PROJE_ADI = "İLK_PROJENİN_KLASÖR_ADI" # Burayı değiştir
    PROJE_YOLU = f"projects/{PROJE_ADI}"
    
    if os.path.exists(PROJE_YOLU):
        liste = proje_tara(PROJE_YOLU)
        rapor = analiz_et(liste, PROJE_ADI)
        print("\n" + "="*50)
        print(f"📋 {PROJE_ADI} ANALİZ RAPORU:")
        print(rapor)
        print("="*50)
    else:
        print("Hata: Proje klasörü bulunamadı!")