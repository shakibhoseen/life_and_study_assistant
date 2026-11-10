# Local Offline OCR & MCQ Extraction Pipeline (Antigravity Guide)

> **Context for Antigravity on Any Machine:**  
> এই ডকুমেন্টটি প্রজেক্টের লোকাল অফলাইন OCR এবং কুইজ-রেডি MCQ এক্সট্র্যাকশন পাইপলাইনের সম্পূর্ণ আর্কিটেকচার, বর্তমান কাজের স্থিতি (Status) এবং পরবর্তী পদক্ষেপ লিপিবদ্ধ করে। যেকোনো কম্পিউটারে এই রিপোজিটরি ওপেন করলে Antigravity এটি পড়ে সরাসরি পরবর্তী কাজ শুরু করতে পারবে।

---

## ১. বর্তমান অবস্থা ও অগ্রগতি (Completed Phases)

### ✅ Phase 1: Layout Detection & Page Normalization
- **সার্ভিস:** [`lib/core/services/media/layout/layout_detection_service.dart`](../lib/core/services/media/layout/layout_detection_service.dart)
- **মডেলসমূহ:** [`lib/core/services/media/layout/layout_detection_models.dart`](../lib/core/services/media/layout/layout_detection_models.dart)
- **মূল কাজসমূহ:**
  1. **EXIF Normalization:** ক্যামেরা ও গ্যালারির ছবির ঘূর্ণন (`bakeOrientation`) সোজা করে যাতে ক্রপ স্ক্রিন উল্টো না আসে।
  2. **Automatic Skew Correction:** Radon / Horizontal Projection Profile Variance অ্যালগরিদম ব্যবহার করে পাতা বাঁকা থাকলে ($-8^\circ$ থেকে $+8^\circ$) স্বয়ংক্রিয়ভাবে সোজা (deskew) করে।
  3. **Content-Aware Gutter & Divider Detection:** কোনো ৫০% ফিক্সড স্প্লিট নয়; Vertical Projection Profile দিয়ে বইয়ের পাতার মাঝের হোয়াইটস্পেস গটার অথবা উল্লম্ব দাগ (Divider Line) নিখুঁতভাবে শনাক্ত করে।
  4. **Adaptive Fallback:** গটার কনফিডেন্স ৬০%-এর কম হলে সেফ সিঙ্গেল কলামে ফলব্যাক করে যাতে কোনো টেক্সট না কাটে।
  5. **Zero Additional Native Bloat (0 MB):** সম্পূর্ণ ডার্ট এবং ব্যাকগ্রাউন্ড আইসোলেটে (`compute`) চলে, ভারী OpenCV ছাড়াই ৬০ FPS পারফরম্যান্স নিশ্চিত করে।
- **টেস্ট ও বেঞ্চমার্ক:** [`test/layout_detection_service_test.dart`](../test/layout_detection_service_test.dart) (৫টি টেস্টই পাস)।

---

### ✅ Phase 2: Question & Option Block Segmentation
- **সার্ভিস:** [`lib/core/services/media/segmentation/question_segmentation_service.dart`](../lib/core/services/media/segmentation/question_segmentation_service.dart)
- **মডেলসমূহ:** [`lib/core/services/media/segmentation/segmentation_models.dart`](../lib/core/services/media/segmentation/segmentation_models.dart)
- **মূল কাজসমূহ:**
  1. **Column-wise Processing & Isolation:** কলাম ০ (বাম কলাম) আগে এবং কলাম ১ (ডান কলাম) পরে প্রসেস হয়। এক কলামের অপশন অন্য কলামে কখনো মিশবে না।
  2. **Page Coordinate Mapping:** প্রতিটি কলামের বাউন্ডিং বক্স মূল পৃষ্ঠার কোঅর্ডিনেট সিস্টেমে অনুবাদ করা হয়।
  3. **Question Number Detection:** বাংলা (`১.`, `১।`, `১)`, `(১)`), ইংরেজি (`1.`, `1)`, `Q1`, `Q.1`) এবং স্পেশিয়াল মার্জিন চেক ($x \le 40\%$) দিয়ে প্রশ্ন হেডার শনাক্ত করা হয়।
  4. **Multi-Layout Option Extraction:**
     - আলাদা আলাদা লাইনে থাকা অপশন।
     - ২x২ গ্রিড লেআউট (এক লাইনে দুটি অপশন)।
     - এক লাইনে চারটি অপশন।
     - স্ক্যানড বাংলা বইয়ের বৃত্তাকার অপশন প্রতীক (`©`, `®`, `ও)`, `@`, `গু`) কে `ক`, `খ`, `গ`, `ঘ` তে স্বয়ংক্রিয় রূপান্তর।
     - অপশন মার্কার না পেলে কোনো কাল্পনিক অপশন তৈরি করা হয় না।
  5. **Math & Diagram Preservation:** জ্যামিতিক চিত্র, সমীকরণ বা গ্রাফ থাকলে মূল হাই-রেজোলিউশন ছবি থেকে ক্রপ ফাইল সেভ করে `diagramCropPath` ও `originalCropReference` রাখা হয়।
  6. **Orphan Text Protection:** পেজের হেডার বা নির্দেশনামূলক নম্বরহীন টেক্সট ফেলে না দিয়ে `orphanBlocks`-এ সংরক্ষণ করা হয়।
  7. **Strict Phase 2 Rule:** কোনো উত্তর অনুমান করা হয়নি; `correctIndex` অপরিবর্তিতভাবে `-1` রাখা হয়েছে।
  8. **Bridge to `QuizQuestion`:** `.toQuizQuestion()` কল করলেই বিদ্যমান ডাটাবেজ বা মডেলের সাথে ১০০% কম্প্যাটিবল অবজেক্ট পাওয়া যায়।
- **টেস্ট ও বেঞ্চমার্ক:** [`test/question_segmentation_service_test.dart`](../test/question_segmentation_service_test.dart) (৭টি টেস্টই পাস)।

---

### ✅ Local OCR Plugin (`packages/local_ocr/`)
- আধুনিক `cz.adaptech.tesseract4android:tesseract4android:4.9.0` (JitPack) ভিত্তিক প্লাগইন।
- Gradle 9 / AGP 9.1.0 ও Kotlin DSL কম্প্যাটিবল (কোনো ডেপ্রিকেটেড `jcenter()` নেই)।
- `LocalOcr.extractText(...)`: দ্রুত UTF-8 টেক্সট এক্সট্র্যাক্ট করে।
- `LocalOcr.extractHocr(...)`: বাউন্ডিং বক্স, লাইন ও শব্দভিত্তিক কনফিডেন্স স্কোরসহ hOCR HTML প্রদান করে।
- অ্যাসেটস: `assets/tessdata/` (`ben.traineddata`, `eng.traineddata`, `equ.traineddata`)।

---

### ✅ Visual Layout & MCQ Debugger
- স্ক্রিন: [`lib/features/image_to_text/presentation/screens/layout_debug_screen.dart`](../lib/features/image_to_text/presentation/screens/layout_debug_screen.dart)
- Image to Text স্ক্রিনের ডানদিকের **Analytics আইকন** (`Icons.analytics_outlined`) থেকে সরাসরি অ্যাক্সেসযোগ্য।
- ৫টি ট্যাব:
  1. `Bounding Boxes & Gutter`: মূল ছবির ওপর গাটার ও কলাম বাউন্ডিং বক্স ওভারলে।
  2. `Column Crops`: বাম ও ডান কলামের ক্রপ প্রিভিউ।
  3. `MCQ Blocks (Phase 2)`: সেগমেন্টেড প্রশ্ন, অপশন, চিত্র/ম্যাথ ব্যাজ, বাউন্ডিং বক্স এবং রিভিউ ফ্ল্যাগ।
  4. `Deskewed`: কোণ সোজা করা ছবি।
  5. `Original`: মূল অপরিবর্তিত ছবি।

---

## ২. বাসার কম্পিউটারে প্রজেক্ট রান ও Antigravity দিয়ে কাজ চালিয়ে যাওয়ার নিয়ম

### Antigravity কি দুই কম্পিউটারে স্বয়ংক্রিয়ভাবে চ্যাট হিস্ট্রি সিঙ্ক করে?
**না।** Antigravity-এর চ্যাট হিস্ট্রি ও কনভারসেশন লোকাল মেশিনের `~/.gemini/antigravity/` ফোল্ডারে সংরক্ষিত থাকে। তাই অন্য কম্পিউটারে একই গুগল অ্যাকাউন্ট থাকলেও পূর্ববর্তী চ্যাট সেশন স্বয়ংক্রিয়ভাবে দেখা যায় না।

**তবে সমাধান খুবই সহজ ও শক্তিশালী:**
Antigravity সম্পূর্ণ কোডবেস এবং এই ডকুমেন্টেশন ফাইল পড়ে কাজ বুঝতে পারে। আপনি বাসার কম্পিউটারে গিট থেকে কোড পুল করার পর Antigravity-কে শুধু একটি প্রম্পট দিলেই সে সম্পূর্ণ প্রজেক্টের হিস্ট্রি জেনে যাবে এবং Phase 3 শুরু করবে।

---

### বাসার কম্পিউটারে যে ধাপগুলো অনুসরণ করবেন:

#### ধাপ ১: কোড পুল বা ক্লোন করুন
```bash
git pull origin main
```
*(অথবা নতুন কম্পিউটারে ক্লোন করলে: `git clone <repo_url>` এবং সংশ্লিষ্ট ব্রাঞ্চে যান)*

#### ধাপ ২: ডিপেন্ডেন্সি ও প্যাকেজ আপডেট করুন
```bash
flutter pub get
```

#### ধাপ ৩: টেস্টগুলো রান করে কনফার্ম করুন
```bash
flutter test test/layout_detection_service_test.dart test/question_segmentation_service_test.dart
```
*(সবকটি টেস্ট সবুজ বা পাস আসবে)*

#### ধাপ ৪: বাসার কম্পিউটারের Antigravity-তে প্রম্পট দিন
বাসার কম্পিউটারে Antigravity ওপেন করে প্রজেক্ট ফোল্ডারটি খুলুন এবং নিচের প্রম্পটটি দিন:

```text
আমি অন্য কম্পিউটারে Phase 1 (Layout Detection) এবং Phase 2 (Question & Option Block Segmentation) সম্পন্ন করে পুশ করেছি। বিস্তারিত docs/LOCAL_OCR_SYSTEM_GUIDE.md ফাইলে লিপিবদ্ধ আছে।

তুমি docs/LOCAL_OCR_SYSTEM_GUIDE.md ফাইলটি এবং test/layout_detection_service_test.dart ও test/question_segmentation_service_test.dart পরীক্ষা করে দেখে নাও।

সবকিছু ঠিক থাকলে এখন আমরা Phase 3 শুরু করব।
```

Antigravity এই গাইড পড়ে সাথে সাথে আগের সমস্ত কাজের প্রেক্ষাপট বুঝে নিয়ে নির্বিঘ্নে কাজ শুরু করতে পারবে।
