import subprocess
import time
import re
import os
import json
import sys
import threading

DEVICE_SERIAL = sys.argv[1] if len(sys.argv) > 1 else "192.168.0.104:33715"
PACKAGE_NAME = "com.example.life_and_study_assistant"
LOG_PATH = os.path.join("test_results", "reliable_device_meminfo.csv")

os.makedirs("test_results", exist_ok=True)

with open(LOG_PATH, "w", encoding="utf-8") as f:
    f.write("timestamp,pid,run_id,event_tag,total_pss_kb,total_rss_kb,native_heap_pss_kb,dalvik_heap_pss_kb\n")

print(f"[MONITOR] Reliable Memory Telemetry initialized for {PACKAGE_NAME} on {DEVICE_SERIAL}")
print(f"[MONITOR] Writing correlated memory snapshots to {LOG_PATH}")

current_run_id = "IDLE_OR_UNASSIGNED"
current_event = "IDLE"
consecutive_adb_failures = 0
MAX_ADB_FAILURES = 5
stop_flag = False

def logcat_listener():
    global current_run_id, current_event, stop_flag
    try:
        # Clear logcat first
        subprocess.run(["adb", "-s", DEVICE_SERIAL, "logcat", "-c"], capture_output=True)
        proc = subprocess.Popen(
            ["adb", "-s", DEVICE_SERIAL, "logcat", "-v", "time", "-s", "flutter:V"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
            encoding="utf-8",
            errors="replace"
        )
        for line in proc.stdout:
            if stop_flag:
                break
            if "BENCHMARK_MARKER:" in line:
                idx = line.find("BENCHMARK_MARKER:")
                json_str = line[idx + len("BENCHMARK_MARKER:"):].strip()
                try:
                    data = json.loads(json_str)
                    run_id = data.get("runId", "UNKNOWN")
                    event = data.get("event", "UNKNOWN")
                    print(f"[MONITOR LOGCAT] Event observed: {event} for {run_id}")
                    if event == "START":
                        current_run_id = run_id
                        current_event = "RUNNING"
                    elif event in ("COMPLETE", "ERROR", "TIMEOUT", "RUN_ABORTED"):
                        current_event = event
                        # Let one poll sample capture the COMPLETE event before resetting
                        time.sleep(1.5)
                        current_run_id = "IDLE_OR_UNASSIGNED"
                        current_event = "IDLE"
                except Exception as ex:
                    print(f"[MONITOR LOGCAT] Parse error: {ex} on line: {line.strip()}")
        proc.terminate()
    except Exception as e:
        print(f"[MONITOR LOGCAT] Error in logcat listener: {e}")

def poll_memory():
    global current_run_id, current_event, consecutive_adb_failures
    try:
        res = subprocess.run(
            ["adb", "-s", DEVICE_SERIAL, "shell", "dumpsys", "meminfo", PACKAGE_NAME],
            capture_output=True,
            text=True,
            timeout=5
        )
        if res.returncode != 0 or "No process found" in res.stdout:
            if "No process found" in res.stdout and current_run_id != "IDLE_OR_UNASSIGNED":
                now = time.strftime("%H:%M:%S")
                with open(LOG_PATH, "a", encoding="utf-8") as f:
                    f.write(f"{now},NONE,{current_run_id},PROCESS_EXIT,0,0,0,0\n")
                current_run_id = "IDLE_OR_UNASSIGNED"
                current_event = "IDLE"
            consecutive_adb_failures = 0
            return

        out = res.stdout
        if "TOTAL PSS:" in out:
            consecutive_adb_failures = 0
            now = time.strftime("%H:%M:%S")
            pid = "UNKNOWN"
            m_pid = re.search(r"MEMINFO in pid\s+(\d+)", out)
            if m_pid:
                pid = m_pid.group(1)

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

            line = f"{now},{pid},{current_run_id},{current_event},{total_pss},{total_rss},{native_pss},{dalvik_pss}\n"
            with open(LOG_PATH, "a", encoding="utf-8") as f:
                f.write(line)
    except Exception as e:
        consecutive_adb_failures += 1
        if consecutive_adb_failures >= MAX_ADB_FAILURES:
            now = time.strftime("%H:%M:%S")
            with open(LOG_PATH, "a", encoding="utf-8") as f:
                f.write(f"{now},NONE,{current_run_id},ADB_DISCONNECTED,0,0,0,0\n")
            print(f"[MONITOR] ADB connection lost: {e}. Exiting monitor.")
            sys.exit(1)

def main():
    global stop_flag
    t = threading.Thread(target=logcat_listener, daemon=True)
    t.start()

    start_time = time.time()
    max_duration = 600  # 10 minutes maximum

    try:
        while time.time() - start_time < max_duration:
            poll_memory()
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        stop_flag = True

if __name__ == "__main__":
    main()
