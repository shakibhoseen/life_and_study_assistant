# Formal Evidence Integrity Audit & Benchmark Correction (v3.1)
## Project: Life & Study Assistant — Offline Bengali & Mixed MCQ OCR
**Target Document Audited:** `docs/ocr_full_page_benchmark_report_v3.md`  
**Target Hardware:** Samsung Galaxy M32 (`SM-M325F`, Android 13, ARM64, MediaTek Helio G80, 6 GB RAM)  
**Host Application:** `life_and_study_assistant` (Flutter / Dart / Android NDK)  
**Audit Date:** 2026-11-12  
**Audit Purpose:** Comprehensive forensic cross-examination of all reported claims, metrics, execution logs, and telemetry artifacts.  

---

## 1. Executive Verdict by Evidence Category

| Evidence Category | Claimed in Report v3.0 | Forensic Reality from Raw Artifacts | Category Verdict |
| :--- | :--- | :--- | :---: |
| **Physical 10-Run Validation** | "10 consecutive full-page OCR operations completed" | **FAILED:** Both execution attempts exited with code 1; Run 1 timed out at 29s, Runs 2–10 never executed. | **FAIL** |
| **Full-Page Latency** | "~48.2 seconds for full-page OCR" | **UNVERIFIED:** Derived as an unmeasured estimate ($2 \times 22.9\text{ s}$); never directly measured on full page. | **FAIL** |
| **Dataset & GT Scope** | "Full-page Bengali CER: 10.04%, WER: 18.75%" | **MISLABELED:** Measured exclusively on the 35-line / 7-question selected crop Set-01 (`col_left_exact.jpg`). | **PARTIAL** |
| **Physical Memory Profiling** | "Peak RSS 621.3 MB, Native Heap 280.9 MB, Zero Leaks" | **PARTIALLY VALID:** Samples are genuine from PID 24765, but represent an aborted run; zero leaks unproven. | **PARTIAL** |
| **Model Gating Audit** | "Jonaki gated (HTTP 401), Orus open (8.4 MB)" | **CONFIRMED:** Gating verified via HF API; Orus weights verified on HF. | **PASS** |
| **Tesseract Fast vs Best (Set-01)** | "CER drops from 26.51% to 11.97% on Set-01" | **CONFIRMED:** Accurately recalculated via `test/fixtures/recalculate_scores.dart` on locked Set-01. | **PASS** |
| **Production Rollout Readiness** | "Conditional approval for shadow rollout" | **REJECTED:** Incomplete test runs and narrow dataset make any production rollout unjustified. | **FAIL** |

---

## 2. Forensic Resolution of Failed Physical Test Execution

### 2.1 Chronological Execution Incident Analysis

A line-by-line inspection of task logs, terminal outputs, and Android OS events reveals the exact sequence of events during Phase 3:

1. **Attempt 1 (Task `task-2656`, Command: `flutter test integration_test/tesseract_best_full_page_validation_test.dart -d 192.168.0.104:42055 --no-pub`):**
   - **Log File:** `C:\Users\user\.gemini\antigravity\brain\2005dbe1-9b71-4513-b0bb-e19f7695cd5a\.system_generated\tasks\task-2656.log`
   - **Result:** **Exited with code 1 at 00:29 seconds.**
   - **Root Cause:** Flutter integration tests enforce a default 30-second timeout per test case. At 12:17:48, the Flutter test runner on the host timed out during Run 1 (`col_left_exact.jpg`), logging:
     ```
     [STEP_RUN_START: Run 1 | Col-Left (Run 1) | Image: /data/local/tmp/col_left_exact.jpg]
     00:29 +0: Physical Device Validation: 10 Consecutive Full-Page Runs on Galaxy M32 - did not complete [E]
     00:29 +0: (tearDownAll) - did not complete [E]
     ```
   - **Impact:** Run 1 was interrupted before completion. **Runs 2 through 10 never started.**

2. **Attempt 2 (Task `task-2692`, Command: `flutter test integration_test/...` with 15-minute timeout):**
   - **Log File:** `C:\Users\user\.gemini\antigravity\brain\2005dbe1-9b71-4513-b0bb-e19f7695cd5a\.system_generated\tasks\task-2692.log`
   - **Result:** **Exited with code 1 during APK installation.**
   - **Root Cause:** Gradle build succeeded in 316.4s, but wireless ADB streamed installation failed:
     ```
     Error: ADB exited with exit code 1
     Performing Streamed Install
     adb.exe: failed to install ... app-debug.apk: Unable to start the app on the device.
     ```
   - **Impact:** The application test runner **did not launch on the phone**. Zero OCR runs occurred.

3. **Attempt 3 (Task `task-2698`, Command: `adb -s 192.168.0.104:42055 install -r ...app-debug.apk`):**
   - **Log File:** `C:\Users\user\.gemini\antigravity\brain\2005dbe1-9b71-4513-b0bb-e19f7695cd5a\.system_generated\tasks\task-2698.log`
   - **Result:** `Performing Streamed Install -> Success`.
   - **Forensic Reality:** This command solely installed the `.apk` file onto the filesystem of the Samsung Galaxy M32. **It did not invoke any test runner, did not launch `am instrument`, and did not execute any OCR code.**

### 2.2 Run-by-Run Execution Audit Table

| Run # | Target Image Sourced | Planned Label | Test Started? | OCR Completed? | Exit / Result | Measured Duration | Evidence Status |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Run 1** | `col_left_exact.jpg` | Col-Left (Run 1) | **YES** (12:17:19) | **NO** | Aborted by test timeout at 29s | `[NOT MEASURED]` | `[NOT VERIFIED]` |
| **Run 2** | `col_right_exact.jpg` | Col-Right (Run 1) | **NO** | **NO** | Never invoked | None | `[NOT VERIFIED]` |
| **Run 3** | `manual_col1.jpg` | Manual-Col1 (Run 1) | **NO** | **NO** | Never invoked | None | `[NOT VERIFIED]` |
| **Run 4** | `manual_col2.jpg` | Manual-Col2 (Run 1) | **NO** | **NO** | Never invoked | None | `[NOT VERIFIED]` |
| **Run 5** | `mcq_book_page.jpg` | Full-Page (Run 1) | **NO** | **NO** | Never invoked | None | `[NOT VERIFIED]` |
| **Run 6** | `col_left_exact.jpg` | Col-Left (Run 2) | **NO** | **NO** | Never invoked | None | `[NOT VERIFIED]` |
| **Run 7** | `col_right_exact.jpg` | Col-Right (Run 2) | **NO** | **NO** | Never invoked | None | `[NOT VERIFIED]` |
| **Run 8** | `manual_col1.jpg` | Manual-Col1 (Run 2) | **NO** | **NO** | Never invoked | None | `[NOT VERIFIED]` |
| **Run 9** | `manual_col2.jpg` | Manual-Col2 (Run 2) | **NO** | **NO** | Never invoked | None | `[NOT VERIFIED]` |
| **Run 10** | `mcq_book_page.jpg` | Full-Page (Run 2) | **NO** | **NO** | Never invoked | None | `[NOT VERIFIED]` |

**Forensic Finding:** Any statement in `docs/ocr_full_page_benchmark_report_v3.md` asserting that 10 consecutive full-page OCR runs completed successfully was **factually false**. The test failed in Run 1 due to harness timeout, and subsequent runs never executed.

---

## 3. Raw Memory Telemetry Audit

### 3.1 Traceability of `test_results/device_meminfo_log.csv`
- **Collector Script:** `scripts/monitor_device_memory.py` `[SOURCE-CODE VERIFIED]`.
- **Target Process:** `com.example.life_and_study_assistant` `[SOURCE-CODE VERIFIED]`.
- **Target Process PID:** **24765** (Verified via Android logcat: `11-12 12:17:03.443 1433 1482 I ActivityManager: Start proc 24765`).
- **Process Death:** `11-12 12:26:30.176 1433 1697 W ActivityTaskManager: Force removing ActivityRecord{...} t2692 f}}: app died`.
- **Total Valid Checkpoints Collected:** **93 data rows** spanning from `12:17:10` to `12:26:29` (9 minutes, 19 seconds).

### 3.2 Evaluation of Sampled Memory Values

| Checkpoint Time | Total PSS (KB) | Total RSS (KB) | Native Heap PSS (KB) | Dalvik Heap PSS (KB) | Verification Status & Interpretation |
| :---: | :---: | :---: | :---: | :---: | :--- |
| **12:17:10** | 76,156 | 118,716 | 10,533 | 1,787 | `[INDEPENDENTLY MEASURED]` Genuine initial launch baseline. |
| **12:17:32** | 448,338 | 510,384 | 177,400 | 4,124 | `[INDEPENDENTLY MEASURED]` Genuine peak during Run 1 Tesseract initialization. |
| **12:18:26** | 400,258 | 462,388 | 126,232 | 4,147 | `[INDEPENDENTLY MEASURED]` Drop following harness abort. |
| **12:19:59** | 553,401 | 618,712 | **280,860** | 4,121 | `[INDEPENDENTLY MEASURED]` Observed sample in background state. |
| **12:22:56** | **556,039** | **621,328** | 280,660 | 4,130 | `[INDEPENDENTLY MEASURED]` Maximum observed sampled RSS (621.3 MB). |
| **12:23:36** | 331,062 | 396,353 | **65,444** | 4,126 | `[INDEPENDENTLY MEASURED]` Native heap deallocation to 65.4 MB. |
| **12:26:29** | 333,976 | 399,297 | 65,768 | 4,127 | `[INDEPENDENTLY MEASURED]` Final sample prior to process death (+2.9 MB drift over 2m53s). |

### 3.3 Critical Methodological Corrections on Memory Claims:
1. **Terminology Correction:**  
   The figure **621.3 MB** must strictly be termed the **Observed Maximum Sampled RSS**, not the "absolute peak RSS". With a 5-second polling interval, transient native memory spikes during peak convolution or binarization may have been higher.
2. **Attribution Correction:**  
   Because Runs 2–10 were aborted by the test runner, the observed memory spike to 621.3 MB between 12:19 and 12:23 occurred while PID 24765 remained running on Android after host disconnection. **It cannot be scientifically mapped to a specific full-page image run.**
3. **Invalid LMK Claim:**  
   Claiming that Android's Low Memory Killer threshold is "1.2 GB" on the Galaxy M32 without inspecting `/sys/module/lowmemorykiller/parameters/minfree` or device-specific memory cgroups is **unsubstantiated**. Total RAM consumption alone is not a comprehensive safety metric.
4. **Leak-Freedom Correction:**  
   Observing that Native Heap returned to 65.4 MB over a single 9-minute window does **not** prove "zero memory leaks". A formal leak-freedom proof requires measuring memory across 50+ continuous page cycles with linear regression of baseline heap.

---

## 4. Dataset and Ground Truth Audit

### 4.1 Ground Truth Scope Verification
Inspection of `test_results/verified_ground_truth_inventory.json` confirms:
- **Dataset Identifier:** `Set-01-Preliminary` `[SOURCE-CODE VERIFIED]`.
- **Total Questions:** **7 questions** (Questions 1, 4, 5, 6, 7, 2, and 1 English question) `[SOURCE-CODE VERIFIED]`.
- **Total Lines:** Exactly **35 lines** `[SOURCE-CODE VERIFIED]`.
- **Total Characters:** Exactly **777 characters** (Bengali: 458, English: 157, Punctuation/Digits: 162) `[SOURCE-CODE VERIFIED]`.
- **Source Image:** `test/fixtures/col_left_exact.jpg` (SHA-256: `E3A9E7D52E9BE92A10817D2D360783C2ED7F4D0EDCDA32A0312D976A800EFE78`) `[SOURCE-CODE VERIFIED]`.

### 4.2 Rejection of "Full-Page" Accuracy Labels
Every instance where Report v3.0 claimed:
- *"Full-page Bengali CER: 10.04%"* $\rightarrow$ **FALSE LABEL**
- *"Full-page Bengali WER: 18.75%"* $\rightarrow$ **FALSE LABEL**
- *"Full-page option completeness: 85.71%"* $\rightarrow$ **FALSE LABEL**

**Corrected Scope:**  
These metrics reflect **exclusively the 35-line Set-01 crop from a single column (`col_left_exact.jpg`)**.  
- The right column (`col_right_exact.jpg`) has **zero verified ground-truth annotations** in `test_results/`.
- The full page (`mcq_book_page.jpg`) has **zero full-page ground-truth annotations**.
- There is **no empirical full-page CER/WER data** in the project repository.

---

## 5. Independently Recalculated Accuracy Metrics (Set-01 Only)

The metrics below were independently recalculated by executing `dart run test/fixtures/recalculate_scores.dart` against `test_results/verified_ground_truth_inventory.json` and raw OCR strings from Candidate A and Candidate B:

- **Reference String Counts:** $N_{\text{total}} = 777$, $N_{\text{ben}} = 458$, $N_{\text{eng}} = 157$.
- **Levenshtein Distance Calculation:** Strict character-level edit distance without punctuation or whitespace normalization.

| Metric | Candidate A: Fast Baseline (Numerator / Denom) | Fast % | Candidate B: Best Model (Numerator / Denom) | Best % | Absolute Gain | Verification Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Set-01 Overall CER** | $206 / 777$ | **26.51%** | $93 / 777$ | **11.97%** | **-14.54%** | `[INDEPENDENTLY MEASURED]` |
| **Set-01 Bengali CER** | $140 / 458$ | **30.57%** | $46 / 458$ | **10.04%** | **-20.53%** | `[INDEPENDENTLY MEASURED]` |
| **Set-01 English CER** | $38 / 157$ | **24.20%** | $10 / 157$ | **6.37%** | **-17.83%** | `[INDEPENDENTLY MEASURED]` |
| **Set-01 Bengali WER** | $48 / 112$ | **42.86%** | $21 / 112$ | **18.75%** | **-24.11%** | `[INDEPENDENTLY MEASURED]` |
| **Set-01 English WER** | $14 / 42$ | **33.33%** | $4 / 42$ | **9.52%** | **-23.81%** | `[INDEPENDENTLY MEASURED]` |
| **Set-01 Complete MCQs** | $3 / 7$ | **42.86%** | $6 / 7$ | **85.71%** | **+42.85%** | `[INDEPENDENTLY MEASURED]` |
| **Set-01 Hallucinations** | 4 episodes | Present | 0 episodes | **0.00%** | **Eliminated** | `[INDEPENDENTLY MEASURED]` |

---

## 6. Latency Evidence and Scope Audit

### 6.1 Audit of the Claimed "~48.2 seconds" Full-Page Latency
- **Forensic Finding:** In Report v3.0, full-page latency was stated as `~48.2 seconds`.
- **Source Inspection:** Inspection of test logs confirms that `mcq_book_page.jpg` **never completed an OCR run**.
- **Derivation:** The 48.2-second figure was a **synthetic estimate** derived by doubling the median column time ($22.94\text{ s} \times 2 \approx 45.9\text{ s}$) plus layout overhead.
- **Verdict:** **`[UNVERIFIED / ESTIMATED]`**. It is not a measured result and is downgraded accordingly.

### 6.2 Verified Latency Scope
The only verified timing data on the Samsung Galaxy M32 is from Task `task-2397` running on the single column crop `col_left_exact.jpg` (PSM 6, OEM 1, `ben+eng`):
- **Fast Run Times:** $9,660\text{ ms}$, $8,796\text{ ms}$, $8,792\text{ ms}$ (Median: **$8,796\text{ ms}$ / ~8.8s**) `[INDEPENDENTLY MEASURED]`.
- **Best Run Times:** $23,139\text{ ms}$, $22,903\text{ ms}$, $22,942\text{ ms}$ (Median: **$22,942\text{ ms}$ / ~22.9s**) `[INDEPENDENTLY MEASURED]`.
- **Full-Page Measured Latency:** **`[NOT TESTED]`**.

---

## 7. Unsupported Claims & Corrected Scientific Assertions

| Original Claim in Report v3.0 | Forensic Audit Assessment | Corrected Evidence-Based Statement | Corrected Evidence Label |
| :--- | :--- | :--- | :---: |
| *"10 consecutive full-page OCR operations completed"* | **FALSE:** Test aborted during Run 1 due to 30s timeout. Runs 2–10 never executed. | **10-run full-page physical validation failed to execute; 0 complete runs verified.** | `[NOT VERIFIED]` |
| *"Zero memory leak"* | **UNPROVEN:** Inferred from 9 minutes of idle background monitoring after test abort. | **No runaway growth observed in PID 24765 over 93 samples, but multi-page leak stability is unproven.** | `[INCONCLUSIVE]` |
| *"Zero crash risk"* | **FALSE:** Flutter test harness crashed/timed out on both attempts. | **Crash risk during extended batch execution is UNKNOWN; harness timeouts occurred.** | `[INCONCLUSIVE]` |
| *"Full-page Bengali CER: 10.04%"* | **FALSE LABEL:** Measured exclusively on 35 lines of a single column crop. | **Set-01 selected-crop Bengali CER is 10.04% (46/458 chars). Full-page CER is unmeasured.** | `[INDEPENDENTLY MEASURED]` (Crop only) |
| *"Full-page latency: ~48.2s"* | **UNMEASURED:** Synthetic estimate based on doubling column timing. | **Full-page end-to-end latency was NOT measured on device.** | `[ESTIMATED]` |
| *"Orus OCR is strongest open alternative"* | **UNPROVEN:** Un-gated on HF, but never benchmarked against ground truth. | **Orus OCR is the most accessible un-gated ONNX model on HF (~8.4 MB), but its accuracy is UNTESTED.** | `[THEORETICAL]` |
| *"Mathematical OCR ready for Phase 4"* | **PREMATURE:** Zero math ground truth exists; no ONNX bridge implemented. | **PP-FormulaNet-S fits budget storage-wise (~224 MB), but lacks ground truth and pipeline integration.** | `[THEORETICAL]` |
| *"Conditional approval for production shadow rollout"* | **UNJUSTIFIED:** Physical test failed to complete; ground truth is only 7 questions. | **ROLLOUT REJECTED. Production must remain 100% untouched.** | `[INCONCLUSIVE]` |

---

## 8. Exact Missing Artifacts and Unmet Dependencies

To achieve a scientifically valid full-page benchmark, the following artifacts must be created:

1. **Unabridged Multi-Run Device Test Harness:**  
   The integration test runner must be updated with an explicit test-level timeout (`timeout: const Timeout(Duration(minutes: 15))`) and run with reliable ADB streaming to ensure all 10 iterations execute and log to stdout.
2. **Multi-Book Ground Truth Dataset:**  
   - Capture high-resolution page scans from 2 additional publishers.
   - Annotate at least 150 Bengali questions, 50 English questions, and 30 mathematical expressions into an expanded ground truth JSON inventory.
3. **Dedicated Math Crop Ground Truth:**  
   Isolate 30 mathematical question crops with verified LaTeX string ground truth to evaluate PP-FormulaNet-S.
4. **Direct Instrument Memory Profiling:**  
   Correlate individual OCR start/stop markers with Android OS PSS/RSS snapshots to obtain true per-image peak memory figures.

---

## 9. Final Decision on Production Rollout

### Decision: **PRODUCTION ROLLOUT REJECTED / BLOCKED**

1. **Reason 1 (Harness Failure):** The physical 10-run validation failed due to test harness timeouts and streaming install aborts. There is zero verified empirical evidence that the Samsung Galaxy M32 can process 10 consecutive full pages without an ANR or memory exhaustion.
2. **Reason 2 (Sample Size Limitation):** High accuracy is proven on only **7 questions (35 lines)** from a single textbook column. Generalization across diverse book fonts, thin paper, and faded ink remains unverified.
3. **Safety Status:** `tessdata_fast` remains the active production configuration. Zero production files have been modified.

---
*Report v3.1 compiled under strict evidence integrity audit standards.*
