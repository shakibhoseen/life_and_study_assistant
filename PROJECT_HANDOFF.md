# Project Handoff: Offline OCR & MCQ Segmentation Engine
**Project Name:** `life_and_study_assistant`  
**Handoff Date:** 2026-11-11  
**Target Platform:** Flutter (Android arm64-v8a / Desktop Dart VM Test Harness)  
**Current Active Branch:** `baseline/phase-2-3-marker-recovery`  
**Baseline Git HEAD Commit:** `1e85ce603328f0382b2db6f5d165630701965f42`  

---

## 1. Project Purpose & Architecture Overview

The `life_and_study_assistant` Flutter application contains a specialized offline optical character recognition (OCR) and document processing pipeline designed to ingest full-page photographs of Bengali competitive examination MCQ books and convert them into interactive digital quiz entities without requiring cloud servers, active internet connectivity, or paid API calls.

### Three-Tier Processing Architecture:
1. **Tier 1 — Layout Detection & Deskewing (`LayoutDetectionService`, `SkewDetectionService`):**
   - Computes page orientation and corrects document tilt using radon/projection variance.
   - Analyzes vertical projection profiles across the central $25\% - 75\%$ horizontal window to detect gutters and vertical divider lines.
   - Slices dual-column layouts into zero-crosstalk column crops.
2. **Tier 2 — Native Offline OCR Engine (`packages/local_ocr`):**
   - Android-native plugin embedding **Tesseract4Android 4.9.0** (wrapping native C++ Tesseract 5.5.0 and Leptonica 1.84.1).
   - Generates line-level text bounding boxes, per-word confidence metrics, and structured hOCR representations.
3. **Tier 3 — Segmentation & Context-Aware Marker Recovery (`QuestionSegmentationService`, `ContextAwareMarkerRecoveryService`):**
   - Assembles text lines into discrete MCQ questions and associated option blocks.
   - Employs spatial grid detection (1x4, 2x2, 4x1 layouts) and multi-signal evidence to recover degraded circular Bengali option markers (`(ক)`, `(খ)`, `(গ)`, `(ঘ)`).
   - Maps questions to `QuizQuestion` entities while adhering strictly to zero answer guessing (`correctIndex = -1`).
   - Cloud Fallback: Questions flagged with `reviewRequired = true` or low offline confidence can selectively delegate to Google Gemini Vision.

---

## 2. Phase-by-Phase Development History

| Phase | Milestone Title | Key Accomplishments | Primary Deliverables / Test Files |
| :--- | :--- | :--- | :--- |
| **Phase 1** | Layout Detection & Column Slicing | Implemented Hough/projection-based skew detection, gutter discovery, and dual-column bounding box extraction. Fixed a 9.0° false skew anomaly caused by black border rotation artifacts. | `skew_detection_service.dart`, `layout_detection_service.dart` (Commit `c584aa3`) |
| **Phase 2** | MCQ Question & Option Segmentation | Implemented spatial line grouping, Bengali question header detection, multi-option line splitting, and initial hOCR parsing. | `question_segmentation_service.dart`, `question_segmentation_service_test.dart` (Commit `6130976`) |
| **Phase 2.1** | Real Device OCR Audit | Executed on physical Samsung Galaxy M32; captured 36 real OCR lines; audited marker degradation where circled Bengali letters (`ক`, `খ`, `গ`, `ঘ`) became `@`, `€`, `©`, `ও`. | `real_image_audit_test.dart`, `full_device_flutter_logcat.txt` |
| **Phase 2.2** | Full Page Segmentation & False Recovery Guard | Resolved Line 6 conflict where `€) বাদ্যযন্ত্র...` was misclassified as Question 5 header; introduced answer marker guard (`উ.`) and prefix negative lookaheads. | `phase_2_2_full_audit_report.md` |
| **Phase 2.3** | Ground Truth Benchmark & Baseline Lock | Formulated 7-question Ground Truth JSON for left column; verified 8/12 exact option text match baseline; locked baseline commits; created pure Dart desktop integration test harness. | `phase_2_3_benchmark_test.dart`, `ground_truth_left_column.json` (Commit `df32598`, `1e85ce6`) |

---

## 3. Git Baseline & Commit Lineage

Current working branch: **`baseline/phase-2-3-marker-recovery`**  
Base branch: **`main`** (`61309764e385a1d0d911df83c490f4293e9ce451` — **Strictly Untouched**)

```
* 1e85ce6 (HEAD -> baseline/phase-2-3-marker-recovery) chore(test): add integration test harness, book page png fixture, and ground truth baseline
* df32598 feat(ocr): implement context-aware marker recovery baseline and regression tests (Phase 2.3)
* c584aa3 fix(layout): eliminate false 9-degree skew from black border canvas rotation
* 6130976 (main, origin/main) feat: complete Phase 1 Layout Detection and Phase 2 MCQ Segmentation with Local OCR
```

### Commit Content Summary:
- **`c584aa3` (Commit 1):** 1 file modified (`skew_detection_service.dart`). Ensures background canvas is painted white before rotation and evaluates projection variance only within the central 25%–75% band.
- **`df32598` (Commit 2):** 7 files (4 core services/models + 3 test files). Implements `ContextAwareMarkerRecoveryService`, `MarkerRecoveryAudit`, negative regex lookaheads for question headers, and 9 comprehensive unit test cases (TC-01 through TC-09).
- **`1e85ce6` (Commit 3):** 7 files. Adds `ground_truth_left_column.json`, `mcq_book_page.png` (14.9 MB high-res test fixture), `local_ocr_integration_test.dart`, and `desktop_ocr_pipeline_test.dart`.

---

## 4. Ground Truth & Physical Device Audit Findings

### 4.1 Sample Image Scope
- **Full Reference Page:** $3478 \times 4624$ pixels (`test/fixtures/mcq_book_page.png`).
- **Left Column Device Crop:** $1547 \times 4424$ pixels (`test_results/col_crop_device.jpg`).

### 4.2 The 36 OCR Lines on Samsung Galaxy M32
The physical run on Samsung Galaxy M32 generated 36 raw OCR lines mapping to Ground Truth (`test_results/ground_truth_left_column.json`):
- **Lines 0–3:** Question 1 (Header, Exam source, Options ক/খ, Options গ/ঘ + Answer `উ.ক`).
- **Lines 4–6:** Question 4 (Header, Options ক/খ, Options গ/ঘ + Answer `উ.ঘ`).
- **Lines 7–9:** Question 5 (Header, Exam source, Options ক/খ — Row 1).
- **Lines 10–15:** Question 5 (Row 2) and Question 6 Header.
- **Lines 16–22:** Question 6 Options and Question 7 (`ATM এর পূর্ণরূপ কী?`).
- **Lines 23–27:** Question 2 (English technical question: *"Analog signal is measured in -"*).
- **Lines 28–32:** Question 3 (*"PDA এর পূর্ণরূপ কী?"* — Tesseract OCR misread digit `৩` as `21`).
- **Lines 33–35:** Question 8 and column margin fragments.

---

## 5. Baseline Metric: 8/12 Exact Option Text Match (66.7%)

Evaluated across the 3 benchmark questions in the crop window (Q1, Q4, Q5):

| Option Metric | Score | Percentage | Notes |
| :--- | :---: | :---: | :--- |
| **Exact Option Text Match** | **8 / 12** | **66.7%** | Q1 (2 options), Q4 (4 options), Q5 (2 options in Row 1). |
| **Partial Option Text Match** | 1 / 12 | 8.3% | Q1 option (গ) text OCR misread as `ay`. |
| **Marker Conflict** | 1 / 12 | 8.3% | Q1 option (ঘ) marker misread as `(গ)`. |
| **Missing Options (Outside Window)** | 2 / 12 | 16.7% | Q5 options (গ) & (ঘ) fell on lines 10-11 outside the 10-line slice. |
| **False Token Fragments** | 1 token | N/A | Sub-token `few)` parsed as spurious option due to `(a few)` parenthesis. |

> [!WARNING]
> **Baseline Boundary:** The 8/12 metric represents exact text match on a single 3-question crop slice. It must never be claimed as full-page accuracy.

---

## 6. Core Non-Negotiable Engineering Policies

### 6.1 `correctIndex = -1` Policy (Zero Answer Guessing)
- Under no circumstances should the segmentation or OCR pipeline infer, guess, or assign `correctIndex`.
- Printed answer symbols (e.g. `উ.ক`, `উ.ঘ`) must only be stored in `printedAnswerLetter` for human or cloud review.
- In `toQuizQuestion()`, `correctIndex` is immutably set to `-1`.

### 6.2 Data Immutability: Raw OCR Text Preservation
- The original raw text and bounding boxes emitted by Tesseract must remain unaltered in `TextLineBox.text` and `MarkerRecoveryAudit.originalText`.
- Cleaned and normalized text must reside strictly in `cleanedText`, `options`, or `recoveredText`.

### 6.3 Test Truthfulness: Synthetic Test vs Physical Device Test Separation
- **Synthetic Desktop Harness (`flutter test`):** Executes on Dart VM (Windows/Linux/macOS). Evaluates regex, spatial association, geometry, and recovery algorithms using pre-captured OCR mocks. It does NOT invoke native JNI or the Tesseract C++ engine.
- **Physical Device Run (`flutter run -d <device_id> integration_test/...`):** Executes on physical hardware (Samsung Galaxy M32). Invokes native `LocalOcrPlugin.kt`, Leptonica image binarization, and Tesseract 5.5.0 JNI.
- Reports must never present desktop test passes as physical device verification.

---

## 7. Engine & Dependency Runtime Specifications

### 7.1 Resolved Gradle Dependency
- **Declared:** `packages/local_ocr/android/build.gradle.kts`:
  ```kotlin
  implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
  ```
- **Resolved Dependency Tree:** Verified via `./gradlew :local_ocr:dependencies`:
  ```
  +--- cz.adaptech.tesseract4android:tesseract4android:4.9.0
  |    \--- androidx.annotation:annotation:1.3.0 -> 1.8.1
  ```
- **Engine Components:** Tesseract 5.5.0 / Leptonica 1.84.1. References to "4.7.0" are obsolete.

### 7.2 Offline Asset & Memory Budget (< 100 MB Target)
The offline OCR capability is strictly designed to remain below a **100 MB** storage and memory budget:

| Asset / Component | On-Disk Size | RAM Footprint | Storage Path |
| :--- | :---: | :---: | :--- |
| **`tesseract4android` Native `.so` (arm64-v8a)** | $\approx 14.2\text{ MB}$ | $\approx 25\text{ MB}$ | APK native lib |
| **`ben.traineddata` (Fast Integer Model)** | $3.5\text{ MB}$ | $\approx 15\text{ MB}$ | `assets/tessdata/` |
| **`eng.traineddata` (Fast Integer Model)** | $4.1\text{ MB}$ | $\approx 12\text{ MB}$ | `assets/tessdata/` |
| **Circular Marker Bitmaps (4 templates)** | $< 0.05\text{ MB}$ | $< 0.5\text{ MB}$ | Static code |
| **Flutter Base Code & Assets** | $\approx 22.0\text{ MB}$ | $\approx 45\text{ MB}$ | Base APK |
| **Total Estimated Footprint** | **$\approx 43.85\text{ MB}$** | **$\approx 97.5\text{ MB}$ (Peak RSS)** | **< 100 MB Limit** |

> [!CAUTION]
> Heavy deep learning frameworks (PaddleOCR server, PyTorch Mobile, ONNX Runtime $> 75\text{ MB}$) are strictly disallowed to maintain this lightweight offline budget.

---

## 8. Phase 3 Architecture & Benchmark Roadmap

The portable roadmap for Phase 3 is documented at:
[`docs/phase_3_ocr_architecture_and_benchmark_plan.md`](docs/phase_3_ocr_architecture_and_benchmark_plan.md)

### Phase 3 Stages:
- **Stage 3.1:** Full-Page Layout & Dual-Column Pipeline (zero crosstalk gutter splitting).
- **Stage 3.2:** Native On-Device JNI Execution & Two-Column OCR (sequential processing to prevent OOM).
- **Stage 3.3:** Global Sequential Question Segmentation & Reading Order (Col 0 $\rightarrow$ Col 1).
- **Stage 3.4:** Visual Patch & Circular Marker Recovery Engine (sub-image cropping + template correlation).
- **Stage 3.5:** Full-Page Ground Truth Benchmark & Regression Validation ($\approx 14$ questions).

---

## 9. Pre-Phase 3 Verification Checklist

Before initiating implementation on Phase 3:
- [x] Baseline commits verified on `baseline/phase-2-3-marker-recovery` (`c584aa3`, `df32598`, `1e85ce6`).
- [x] All 19 unit & regression tests pass on Dart VM.
- [x] Tesseract4Android 4.9.0 runtime dependency verified.
- [x] `docs/phase_3_ocr_architecture_and_benchmark_plan.md` reviewed.
- [ ] Explicit user sign-off on Phase 3 plan.
- [ ] Create dedicated branch `feature/phase-3-full-page-pipeline` branched from `baseline/phase-2-3-marker-recovery`.
- [ ] Generate comprehensive full-page Ground Truth dataset: `test_results/ground_truth_full_page.json`.

---

## 10. Prohibited Operations (Without Explicit User Authorization)

The following actions are strictly forbidden:
1. **No Code Mutations to Phase 2.3 Baseline Files:** Zero edits to `context_aware_marker_recovery_service.dart`, `question_segmentation_service.dart`, etc., without clean extension patterns.
2. **No Git Destructive Operations:** Never run `git reset --hard`, `git rebase`, `git commit --amend`, or force-push.
3. **No File Deletions of Untracked Evidence:** Never delete logcat files, test results, or visual crops.
4. **No Schema Mutations:** Do not alter the database schema or `QuizQuestion` model.
5. **No Third-Party Cloud/Heavy Engines:** Do not replace Tesseract with cloud dependencies or heavy local runtimes.
