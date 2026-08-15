import ollama
import google.generativeai as genai
import os
from dotenv import load_dotenv

# .env dosyasındaki API anahtarını yükler
load_dotenv()
genai.configure(api_key=os.getenv("GEMINI_API_KEY"))

def bulut_akli_gemini(soru):
    """Stratejik kararları alan Bulut AI (Gemini)"""
    model = genai.GenerativeModel('gemini-1.5-flash')
    response = model.generate_content(soru)
    return response.text

def yerel_guc_llama(strateji):
    """M5 Pro'nun içinde işi bitiren Yerel AI (Llama 3.2)"""
    print("\n--- M5 Pro (Llama 3.2) Analize Başladı ---")
    response = ollama.chat(model='llama3.2', messages=[
        {'role': 'user', 'content': f"Şu stratejiyi yerel sistemler için yorumla: {strateji}"},
    ])
    return response['message']['content']

if __name__ == "__main__":
    test_sorusu = "Emare Hub için otonom bir mail özetleme sistemi kuruyoruz. İlk adım ne olmalı?"
    
    print("🛰️ Gemini'ye (Bulut) bağlanılıyor...")
    strateji = bulut_akli_gemini(test_sorusu)
    print(f"💡 Gemini'den Gelen Cevap: {strateji[:100]}...")
    
    analiz = yerel_guc_llama(strateji)
    print("\n" + "="*50)
    print("🏁 HİBRİT ZEKA RAPORU:")
    print(analiz)
    print("="*50)