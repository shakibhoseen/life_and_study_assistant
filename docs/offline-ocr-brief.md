# কাজের নির্দেশনা: ছবি থেকে লেখা (অফলাইন OCR)

> এটি একটি implementation brief। যে agent কাজটি করবে, তার জন্য লেখা।

## লক্ষ্য

অ্যাপে **একটি নতুন সেকশন** যোগ করা: ছবি (ক্যামেরা বা গ্যালারি) → লেখা → কপি করা যায়।

**এই ধাপে এটুকুই।** প্রশ্ন পার্স করা, কুইজ বানানো, AI-তে পাঠানো — কিছুই নয়। এটি একটি ভিত্তি: লেখা একবার নির্ভরযোগ্যভাবে বের করতে পারলে পরে ধাপে ধাপে ছবির জন্য AI-র ব্যবহার কমানো যাবে।

**ইঞ্জিন: PaddleOCR Mobile (Lite, ONNX Runtime)।** Tesseract নয় — বাংলা যুক্তাক্ষরে PaddleOCR-এর নির্ভুলতা বেশি, আর এটাই এখানে মূল চাহিদা।

---

## ১. যা অবশ্যই মানতে হবে (এই রিপোর্জিটরির নিয়ম)

- **Riverpod 3** — `StateProvider` নেই। `Notifier` / `NotifierProvider` / `AsyncNotifier` ব্যবহার করুন।
- **UI বাংলায়**, কোড ও কমেন্ট ইংরেজিতে।
- **কোনো token/output limit বসানো যাবে না** কোথাও (এটি প্রকল্পের স্থায়ী নিয়ম)।
- **অনুমান করে ডেটা বানানো নিষেধ।** OCR যা পড়তে পারেনি, সেটা ফাঁকা থাকবে — ভরাট করা হবে না।
- প্রতিটি নতুন আচরণের জন্য **test** লিখতে হবে। `flutter test` সবুজ থাকতেই হবে (বর্তমানে ৮৬৩টি পাস)।
- `flutter analyze` **শূন্য issue**।
- Widget test-এ **আসল file I/O বা unanswered platform channel await করা যাবে না** — টেস্ট ঝুলে যায়। প্রয়োজনে seam রাখুন (যেমন `GeminiResultCache.useMemoryOnly()`-এর মতো একটি `useFakeEngine()`)।

## ২. যা ইতিমধ্যেই আছে, নতুন করে লিখবেন না

| কাজ | যেখানে আছে |
|---|---|
| ছবি তোলা / গ্যালারি / ক্রপ | `lib/core/services/media/photo_capture_service.dart` → `captureAndCrop()` |
| ছবির রেজোলিউশন ও কোয়ালিটির নিয়ম | `lib/core/services/ai/ai_media_limits.dart` |
| ছবি প্রসেসিং | `image: ^4.12.0` (pubspec-এ আছে) |
| ফাইল সেভ / Downloads ফোল্ডার | `lib/core/services/export/app_export_service.dart` |

`image_picker`, `image_cropper`, `image` — তিনটিই pubspec-এ আছে। নতুন করে যোগ করার দরকার নেই।

## ৩. নতুন যা লাগবে

**প্যাকেজ:** ONNX Runtime-এর একটি Flutter বাইন্ডিং (যেমন `onnxruntime` বা `flutter_onnxruntime`)। নির্বাচনের আগে যাচাই করুন:
- Android arm64 + armeabi-v7a দুটোই সাপোর্ট করে কি না
- শেষ ১২ মাসে রিলিজ আছে কি না
- APK-তে কত সাইজ যোগ করে (মেপে লিখুন)

**মডেল অ্যাসেট** (`assets/ocr/`):
- PP-OCR detection (mobile/lite)
- PP-OCR recognition — **বাংলা ও ইংরেজি দুটোই**
- character dictionary ফাইল

লক্ষ্য: মডেল মিলিয়ে **২০ MB-এর নিচে**। pubspec-এ `assets/ocr/` ঘোষণা করুন এবং প্রথম চালানোর সময় app support directory-তে আনপ্যাক করুন (অ্যাসেট থেকে সরাসরি native-এ পাথ দেওয়া যায় না)।

## ৪. কোড যেভাবে সাজাবেন

নতুন feature: `lib/features/ocr/`

```
lib/features/ocr/
  domain/
    ocr_result.dart          # লেখা, লাইন, আত্মবিশ্বাস, সময়
    ocr_engine.dart          # abstract interface + fake (test-এর জন্য)
  data/
    paddle_ocr_engine.dart   # ONNX ইমপ্লিমেন্টেশন
    image_preprocessor.dart  # pure function, সহজে টেস্টযোগ্য
  presentation/
    screens/ocr_screen.dart
    providers/ocr_provider.dart
```

**`OcrEngine`-কে abstract রাখুন।** কারণ দুটো: (ক) টেস্টে fake বসানো যাবে, (খ) PaddleOCR-এ অ্যাকুরেসি না এলে Tesseract-এ বদলানো যাবে পুরো UI না ছুঁয়ে।

### `OcrResult`-এ যা থাকবে

```dart
final String text;              // পুরো লেখা
final List<OcrLine> lines;      // প্রতিটি লাইন + bounding box + confidence
final Duration took;            // কত সময় লাগল
final bool usedFallback;        // কোন ইঞ্জিন চলেছে
```

`confidence` রাখা **জরুরি** — পরে যখন "কোন লাইনটা AI-কে দেখাব, কোনটা নয়" ঠিক করতে হবে, তখন এটাই ভিত্তি।

## ৫. প্রি-প্রসেসিং (অ্যাকুরেসির আসল জায়গা)

`image_preprocessor.dart`-এ pure function হিসেবে, `image` প্যাকেজ দিয়ে — OpenCV লাগবে না:

1. **Grayscale**
2. **Adaptive threshold / binarization**
3. **Deskew** — ছবি বাঁকা থাকলে সোজা করা
4. **লম্বা দিক সর্বোচ্চ ~1600px-এ রিসাইজ** (এর বেশি হলে সময় বাড়ে, নির্ভুলতা বাড়ে না)

প্রতিটি ধাপ **আলাদা ফাংশন**, আলাদা test। আর প্রতিটি ধাপ **বন্ধ করা যাবে এমন** রাখুন — কোন ধাপে অ্যাকুরেসি বাড়ল বা কমল, সেটা মেপে দেখার জন্য।

> ⚠️ `copyResize` EXIF orientation ঢুকিয়ে দেয়; খালি `encodeJpg` দেয় না। এই প্রকল্পে আগে এটা নিয়ে সমস্যা হয়েছে — ঘোরানো ছবিতে পরীক্ষা করে নেবেন।

## ৬. UI

**জায়গা:** Dashboard-এর quick action strip-এ একটি নতুন টাইল — *"ছবি থেকে লেখা"*। Reference: `lib/features/dashboard/presentation/screens/dashboard_screen.dart`-এ `_buildQuickActionStrip`।

**স্ক্রিনে যা থাকবে:**
- ক্যামেরা / গ্যালারি বাটন (`PhotoCaptureService` ব্যবহার করে)
- ছবির প্রিভিউ
- চলার সময় **সত্যিকারের অগ্রগতি** — "প্রসেস হচ্ছে… ৩/৭ লাইন"। বানানো শতাংশ নয়; এই প্রকল্পে আগে একবার কাল্পনিক সংখ্যা দেখানো হয়েছিল, সেটা বাগ হিসেবে সরানো হয়েছে।
- ফলাফল একটি **editable** টেক্সট ফিল্ডে (OCR ভুল করলে হাতে ঠিক করা যাবে)
- **কপি** বাটন → ক্লিপবোর্ডে
- কত সময় লাগল, কয়টি লাইন পাওয়া গেল — ছোট করে লেখা

**যা করবেন না:** লেখা নিজে থেকে কোথাও সেভ করা, AI-তে পাঠানো, বা প্রশ্ন হিসেবে পার্স করা। শুধু দেখানো আর কপি।

## ৭. Test

- `image_preprocessor` — প্রতিটি ধাপের জন্য (grayscale, threshold, deskew, resize)
- `OcrResult` — খালি ফল, এক লাইন, বহু লাইন
- fake engine দিয়ে provider-এর অবস্থা: idle → running → done → error
- widget test: ফলাফল দেখানো, কপি বাটন, খালি ফলের বার্তা
- **আসল মডেল দিয়ে কোনো unit test নয়** — ধীর ও অস্থির। আসল ইঞ্জিন হাতে যাচাই করুন।

## ৮. যাচাই করে যা রিপোর্ট করতে হবে

হাতে অন্তত **৫টি আসল ছবি** চালিয়ে (এই ব্যবহারকারীর টেস্ট পেপার — বাংলা, ইংরেজি ও অঙ্ক মেশানো) মেপে জানাবেন:

| | মাপ |
|---|---|
| APK সাইজ বেড়েছে | ___ MB |
| প্রতি পাতায় সময় | ___ সেকেন্ড |
| বাংলা লেখা | কত শতাংশ ঠিক |
| ইংরেজি লেখা | কত শতাংশ ঠিক |
| অঙ্ক ও চিহ্ন (√, ², π, °) | কত শতাংশ ঠিক |

**আন্দাজে লিখবেন না — চালিয়ে মেপে লিখবেন।** অ্যাকুরেসি কম হলে সেটাই লিখবেন; এই তথ্যটাই ঠিক করবে পরের ধাপে AI কতটা কমানো যাবে।

## ৯. ঝুঁকি, আগেই জেনে রাখুন

- **বাংলা recognition মডেল** PaddleOCR-এ ইংরেজির তুলনায় দুর্বল। যুক্তাক্ষরে ভুল হতে পারে — তাই ফলাফল editable রাখা বাধ্যতামূলক।
- **APK সাইজ** — ONNX Runtime নিজেই ১০-১৫ MB যোগ করতে পারে। মেপে জানাবেন; ৩৫ MB ছাড়ালে আগে জানান।
- **পুরোনো ফোন** — ২ GB RAM-এ বড় ছবি OOM করতে পারে। তাই রিসাইজ প্রি-প্রসেসিংয়ের অংশ, ঐচ্ছিক নয়।
- **ছবির ঘূর্ণন** — EXIF নিয়ে উপরের সতর্কতা দেখুন।

## ১০. কমিট

- একটি feature, একটি commit (বা যৌক্তিক কয়েকটি)
- Commit message-এ **কী মাপা হয়েছে** লিখবেন, শুধু কী যোগ করা হয়েছে তা নয়
- মডেল অ্যাসেট বড় — `git lfs` লাগবে কি না আগে দেখে নিন
