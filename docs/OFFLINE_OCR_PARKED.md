# Offline Bengali OCR — parked

**Status: on hold since 2026-11-15. Not abandoned, not deleted.**

The offline OCR work stopped because the thing it needs does not exist yet, not
because the code is broken. This note exists so that picking it up again is a
day's reading rather than a month's rediscovery.

---

## Why it stopped

Three separate walls. None of them is an OCR accuracy problem, which is what
makes "try a better OCR model" the wrong next move.

**1. Circled option markers (ক/খ/গ/ঘ inside a circle) are not an OCR task.**
Every engine in this space — Tesseract, PaddleOCR, the lot — is trained to find
and read *lines of text*. A single glyph inside a drawn circle is not a line, so
the detector drops it before the recognizer ever sees it. Solving this means
shape detection plus a small dedicated classifier, i.e. training something, not
choosing something. `question_segmentation_service.dart` papers over this with a
list of known misreads (`©`, `®`, `@`, `€`, `ও)`, `গু`, `ঘ)`) — that list is a
symptom, not a fix.

**2. Bengali + English + maths on one page.**
Tesseract's multi-language mode (`ben+eng`) measurably *lowers* accuracy on
mixed pages, because two language models compete per line. Maths notation is
recognised by neither. `assets/tessdata/equ.traineddata` was an attempt at the
third; it did not help.

**3. Column detection offline.**
The weakest link. Offline layout-analysis models are trained on English and
Chinese documents; a Bengali two-column question paper is outside what they have
seen. `lib/core/services/media/layout/` is a hand-rolled gutter detector written
because nothing off the shelf worked.

Cloud vision models (Gemini, Claude) handle all three today — but that defeats
the point, which was offline.

## What was measured

Best result reached, with the `best` (not `fast`) Tesseract models, on the
verified Set-01 fixture: **CER 10.04%, WER 18.75%** — about 3× better than the
`fast` models, and still far short of usable for an exam question bank where a
single wrong Bengali conjunct changes the answer.

Full write-ups are in `docs/ocr_*_benchmark_report*.md` and
`docs/offline_bengali_ocr_engine_benchmark.md`.

## The one idea that was never tried

`docs/offline-ocr-brief.md` specifies **PaddleOCR Mobile (Lite, via ONNX
Runtime)** rather than Tesseract, on the grounds that it is better on Bengali
conjuncts. That brief was written and never implemented — everything shipped
here is the Tesseract path. If this is restarted, that is the starting point,
not a re-tune of Tesseract.

It does not solve walls 1 and 3. Only wall 2.

---

## What is still in the repo

Left in place deliberately. It compiles, it is analyzer-clean, and it costs
nothing to carry except disk.

| | |
|---|---|
| Native plugin | `packages/local_ocr/` (Android-only, Java) |
| Engine wrapper | `lib/core/services/media/local_ocr_service.dart` |
| Layout / columns | `lib/core/services/media/layout/` |
| Question splitting | `lib/core/services/media/segmentation/` |
| Image preprocessing | `lib/core/services/media/image_preprocessor_service.dart` |
| Screen (still reachable from the dashboard) | `lib/features/image_to_text/` |
| Models | `assets/tessdata/` (6.9 MB, shipped in the APK) |
| Test fixture models | `test/fixtures/tessdata_best/` (25 MB, repo only) |

**This is not the same thing as the AI OCR, which is live and unaffected:**
`question_bank_ocr_service.dart` and `study_sheet_ocr_service.dart` send images
to a cloud model and are what the app actually uses. Do not park those.

## What is skipped, and how to run it

Tagged `offline-ocr` in `dart_test.yaml`, skipped by `flutter test`:

```
flutter test --run-skipped --tags offline-ocr
```

- `test/tesseract_best_regression_gate_test.dart` — reads the 25 MB fixture.
  **RG-06 fails and has always failed:** it asserts
  `test_results/verified_ground_truth_inventory.json`, a local benchmark output
  that was never committed. Reviving the work means regenerating that file, not
  deleting the assertion.
- `test/desktop_ocr_pipeline_test.dart` — drives the Android-only native plugin.
  From a desktop host it catches the missing registration, prints a warning and
  **passes without having run the engine**. It needs a device to mean anything.

Device tests, which `flutter test` never ran anyway, carry a header pointing
here: `integration_test/{local_ocr,stage_1_layout,stage_2_column_ocr,tesseract_ab,tesseract_best_full_page_validation}_*.dart`.

Still running in the normal suite, because they are fast, green, and are the
coverage a revival would want on day one: `column_wise_ocr_test.dart` (coordinate
mapping and reading order), `ocr_text_cleaner_test.dart`, `real_image_audit_test.dart`.

## Picking it up again

1. `flutter test --run-skipped --tags offline-ocr` — see what still holds.
2. Regenerate `test_results/verified_ground_truth_inventory.json` and commit it
   this time, so RG-06 is a real gate.
3. Read `docs/offline-ocr-brief.md` and evaluate PaddleOCR Mobile against the
   same Set-01 fixture, so the numbers are comparable to the CER/WER above.
4. Treat circled markers and column detection as their own problems with their
   own models. They will not come free with a better recogniser.

**Worth restarting when** a Bengali-capable offline layout+recognition model
appears — or when an on-device multimodal model small enough to ship can read a
page end to end, which would make walls 1–3 one problem instead of three.

## If this is ever abandoned for good

Delete, in this order: `test/fixtures/tessdata_best/` (25 MB), the tagged and
noted tests above, `packages/local_ocr/` plus its `pubspec.yaml` path
dependency, `assets/tessdata/`, `lib/core/services/media/{local_ocr_service,
ocr,layout,segmentation,image_preprocessor_service}`, `lib/features/image_to_text/`
and its dashboard tile, and `docs/ocr_*`. Nothing outside that list depends on it.
