import subprocess
import time
import re
import os

log_path = os.path.join("test_results", "device_meminfo_log.csv")
os.makedirs("test_results", exist_ok=True)

with open(log_path, "w", encoding="utf-8") as f:
    f.write("timestamp,total_pss_kb,total_rss_kb,native_heap_pss_kb,dalvik_heap_pss_kb\n")

print(f"Memory logging started to {log_path}...")

# Run for up to 15 minutes (180 iterations * 5 sec)
for i in range(180):
    try:
        res = subprocess.run(
            ["adb", "-s", "192.168.0.104:42055", "shell", "dumpsys", "meminfo", "com.example.life_and_study_assistant"],
            capture_output=True,
            text=True,
            timeout=10
        )
        out = res.stdout
        if "TOTAL PSS:" in out:
            now = time.strftime("%H:%M:%S")
            total_pss = 0
            total_rss = 0
            native_pss = 0
            dalvik_pss = 0
            
            m_total = re.search(r"TOTAL PSS:\s+(\d+)\s+TOTAL RSS:\s+(\d+)", out)
            if m_total:
                total_pss = int(m_total.group(1))
                total_rss = int(m_total.group(2))
                
            m_nat = re.search(r"Native Heap\s+(\d+)", out)
            if m_nat:
                native_pss = int(m_nat.group(1))
                
            m_dal = re.search(r"Dalvik Heap\s+(\d+)", out)
            if m_dal:
                dalvik_pss = int(m_dal.group(1))
                
            line = f"{now},{total_pss},{total_rss},{native_pss},{dalvik_pss}\n"
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(line)
            print(f"[{now}] Logged: PSS={total_pss} KB, RSS={total_rss} KB, Native={native_pss} KB")
    except Exception as e:
        pass
    time.sleep(5)
