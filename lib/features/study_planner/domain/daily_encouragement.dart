/// The line of encouragement shown with the day's plan.
///
/// There were four of them in the whole app — one per energy level, written
/// into the local planner — plus one English fallback for when the model
/// returned nothing. So anyone studying offline, or on the same energy level
/// two days running, read the identical sentence every evening, and a sentence
/// read for the fifth time is wallpaper rather than encouragement.
///
/// The pools below are grouped by the kind of day it is, because what helps on
/// an exhausted Tuesday is not what helps on a free Friday. They are picked by
/// the date, not at random: the line is the same all day however many times the
/// plan is rebuilt or the dashboard reopened — a sentence that changes while
/// you look at it is a slot machine, not a companion — and it changes tomorrow.
///
/// Deliberately not all in one register. Some are practical, some are blunt,
/// some give permission to do less. None of them is about small steps
/// conquering mountains.
library;

/// Which pool a day draws from.
enum DayMood { low, medium, high, offDay }

/// Reads the planner's own energy wording, which comes from the model as well
/// as from the local planner and so cannot be relied on to be tidy.
DayMood moodFrom({required String energyLevel, required bool isOffDay}) {
  if (isOffDay) return DayMood.offDay;
  final energy = energyLevel.trim().toLowerCase();
  if (energy.startsWith('low')) return DayMood.low;
  if (energy.startsWith('high')) return DayMood.high;
  return DayMood.medium;
}

const Map<DayMood, List<String>> _pools = {
  DayMood.low: [
    'আজ ক্লান্ত লাগছে? তাহলে আজ শুধু দশ মিনিট। কম পড়া আর না পড়া এক জিনিস নয়।',
    'মাথা সারাদিন কোড লিখে ক্লান্ত। আজ বইটাকে প্রতিপক্ষ বানাবেন না, শুধু ছুঁয়ে যান।',
    'আজকের লক্ষ্য জেতা নয়, টিকে থাকা। কাল আবার আছে।',
    'দশ মিনিট পড়ে বাকি সন্ধ্যাটা পরিবারকে দিন — এটাও প্রস্তুতিরই অংশ।',
    'যেদিন একদম ইচ্ছে করে না, সেদিনের দশ মিনিটই আসল পার্থক্যটা গড়ে।',
    'আজ নতুন কিছু শেখার দিন নয়। পুরোনোটা একবার চোখ বুলিয়ে নিলেই যথেষ্ট।',
    'ঘুম কম হলে পড়া মাথায় ঢোকে না। আজ তাড়াতাড়ি শুয়ে পড়াটাও একটা সিদ্ধান্ত।',
    'একটা প্রশ্নও যদি আজ সত্যিই বুঝে ফেলেন, দিনটা বৃথা যায়নি।',
    'ক্লান্তির দিনে পরিমাণ নয়, উপস্থিতিটুকুই যথেষ্ট।',
    'আজ কম করুন, কিন্তু করুন। শূন্য দিনটা মনে থেকে যায়।',
  ],
  DayMood.medium: [
    'আজ মাঝারি এনার্জি — আধ ঘণ্টাই যথেষ্ট, যদি ফোনটা হাতের বাইরে থাকে।',
    'যে টপিকটা ভাবতেই অস্বস্তি লাগে, আজ সেটাই আগে ধরুন। পরে ধরলে আর ধরা হয় না।',
    'আজকের পঁচিশ মিনিট পরীক্ষার আগের রাতে তিন ঘণ্টা বাঁচাবে।',
    'রিভিশন বিরক্তিকর। কিন্তু হলে ঢুকে ওটাই মনে থাকে।',
    'নতুন টপিক শুরু না করে আজ গত সপ্তাহের ভুলগুলো একবার দেখুন।',
    'টাইমার চালু করে বসুন। সময় মাপা থাকলে মন কম পালায়।',
    'পড়তে বসার আগে ঠিক করুন কখন উঠবেন। শেষটা জানা থাকলে শুরু করা সহজ।',
    'মনে থাকছে না বলে নিজেকে দোষ দেবেন না — রিভিশনের ব্যবধানটা ঠিক করুন।',
    'আজকের দিনটা ভালো-মন্দের মাঝামাঝি। প্রস্তুতির বেশিরভাগটা এরকম দিনেই হয়।',
    'অর্ধেক করা তিনটের চেয়ে পুরো করা একটা ভালো।',
  ],
  DayMood.high: [
    'আজ এনার্জি আছে — সবচেয়ে কঠিন টপিকটা আজই ধরুন। সহজগুলো ক্লান্ত দিনের জন্য তোলা থাক।',
    'ভালো দিনে সহজ কাজ করলে কঠিনগুলো জমতেই থাকে।',
    'আজ একটা পুরো মডেল টেস্ট দিন — ঘড়ি ধরে, ফোন উল্টে রেখে।',
    'এরকম দিন সপ্তাহে দুটো আসে। রেজাল্ট এগুলোই বদলায়।',
    'যে অধ্যায়টা বারবার এড়িয়ে যাচ্ছেন, আজ সেটার দিন।',
    'টানা পঁয়তাল্লিশ মিনিট, তারপর উঠে দাঁড়ান, চা খান, আবার বসুন।',
    'আজ শুধু পড়বেন না, নিজেকে পরীক্ষাও নেবেন। পড়া আর পারা এক জিনিস নয়।',
    'আজ নোট বানিয়ে রাখুন। ভবিষ্যতের ক্লান্ত আপনি আজকের আপনাকে ধন্যবাদ দেবে।',
    'শক্তি থাকতে থাকতে কঠিনটা সেরে ফেলুন; সহজটা ক্লান্ত হাতেও হয়।',
    'ভালো দিনের সুযোগে এগিয়ে থাকুন — খারাপ দিন আসবেই।',
  ],
  DayMood.offDay: [
    'আজ অফিস নেই। এই দিনগুলোই আসলে প্রস্তুতির মেরুদণ্ড।',
    'আজ লম্বা সময় বসা যায় — কিন্তু পুরো দিন নয়। পরিবারকেও ভাগ দিন।',
    'ছুটির দিনে একটা পুরো সিলেবাস মডেল টেস্ট, বাকিটা বিশ্রাম।',
    'সময় আছে বলে সব পড়ে ফেলার চেষ্টা করবেন না। একটা বিষয়ে গভীরে যান।',
    'সপ্তাহজুড়ে জমে থাকা ভুলগুলো শোধরানোর দিন আজ।',
    'সকালটাই সবচেয়ে ভালো। দুপুরের পর মন অফিসের দিনের মতোই ক্লান্ত হয়ে যায়।',
    'আজ দুই ঘণ্টা পড়ুন, বাকিটা পরিবারের — কোনো অপরাধবোধ ছাড়া।',
    'ছুটির দিনে রুটিন না থাকলে দিনটা হাওয়ায় মিলিয়ে যায়। শুরুর সময়টা ঠিক করে নিন।',
    'আজ যেটা বুঝে নেবেন, সপ্তাহের ক্লান্ত দিনগুলোয় সেটারই রিভিশন চলবে।',
    'একটা পুরো মক টেস্ট আর একটা ভালো ঘুম — ছুটির দিনের সেরা ব্যবহার।',
  ],
};

/// The line for a given day.
///
/// The same date and mood always give the same line, so it does not change
/// under the user while they read it, and the next day's is a different one:
/// a pool is walked in order by day number rather than drawn at random, which
/// would repeat within the week often enough to be noticed.
String encouragementFor({
  required DateTime date,
  required String energyLevel,
  bool isOffDay = false,
}) {
  final pool = _pools[moodFrom(energyLevel: energyLevel, isOffDay: isOffDay)]!;
  return pool[_dayNumber(date) % pool.length];
}

/// Days since the epoch, from the calendar date alone — so the line turns over
/// at midnight and not at some hour that drifts with daylight saving.
int _dayNumber(DateTime date) {
  final utcMidnight = DateTime.utc(date.year, date.month, date.day);
  return utcMidnight.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

/// Every line, for the tests that check them.
Map<DayMood, List<String>> get encouragementPools => _pools;
