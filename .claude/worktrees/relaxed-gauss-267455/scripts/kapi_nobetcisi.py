import time
import os
import subprocess
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class ProjeKarsilama(FileSystemEventHandler):
    def on_created(self, event):
        if event.is_directory:
            dervis_adi = os.path.basename(event.src_path)
            print(f"✨ Yeni bir derviş geldi: {dervis_adi}! Tescil merasimi başlıyor...")
            # Tescil scriptini otomatik tetikle
            subprocess.run(["python", "scripts/tescil_merasimi.py"])

if __name__ == "__main__":
    if not os.path.exists("projects"): os.makedirs("projects")
    
    path = "projects/"
    event_handler = ProjeKarsilama()
    observer = Observer()
    observer.schedule(event_handler, path, recursive=False)
    
    print("💂‍♂️ Dergah Kapı Nöbetçisi aktif. Dervişleri bekliyoruz...")
    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()