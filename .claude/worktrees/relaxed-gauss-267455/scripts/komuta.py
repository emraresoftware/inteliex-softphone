import paramiko
import json
import ollama
import os

def sunucu_saglik_kontrolü(ip, kullanici):
    print(f"📡 {ip} adresine bağlanılıyor...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    # Not: SSH Anahtarın (id_rsa) tanımlı olmalıdır
    try:
        ssh.connect(ip, username=kullanici)
        # Sunucudan CPU, RAM ve Disk bilgilerini çeken komutlar
        stdin, stdout, stderr = ssh.exec_command("uptime && free -m && df -h /")
        rapor = stdout.read().decode()
        ssh.close()
        return rapor
    except Exception as e:
        return f"Bağlantı Hatası: {e}"

def ai_degerlendir(rapor, sunucu_adi):
    print(f"🧠 Llama 3.2 {sunucu_adi} raporunu analiz ediyor...")
    prompt = f"Şu sunucu verilerini analiz et ve bir sorun olup olmadığını 1 cümlede söyle: {rapor}"
    response = ollama.chat(model='llama3.2', messages=[{'role': 'user', 'content': prompt}])
    return response['message']['content']

if __name__ == "__main__":
    with open("sunucular.json", "r") as f:
        sunucular = json.load(f)
    
    for s in sunucular:
        ham_veri = sunucu_saglik_kontrolü(s['ip'], s['kullanici'])
        analiz = ai_degerlendir(ham_veri, s['isim'])
        
        print(f"\n🖥️ SUNUCU: {s['isim']} ({s['ip']})")
        print(f"📊 DURUM: {analiz}")
        print("-" * 30)