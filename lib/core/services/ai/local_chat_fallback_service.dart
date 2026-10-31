import 'dart:convert';

import '../../../features/chat/domain/models/chat_action.dart';
import '../../database/app_database.dart';
import '../../utils/bengali_math_sanitizer.dart';
import 'gemini_chat_service.dart';

/// Intelligent offline fallback intent parser and responder for chat.
/// Operates 100% locally with 0 network and 0 AI tokens.
class LocalChatFallbackService {
  const LocalChatFallbackService();

  static const LocalChatFallbackService instance = LocalChatFallbackService();

  static String sanitizeErrorMessage(String message) {
    return message
        .replaceAll(RegExp(r'AIza[0-9A-Za-z\-_]{35}'), '[REDACTED_API_KEY]')
        .replaceAll(RegExp(r'key=[0-9A-Za-z\-_]+'), 'key=[REDACTED]');
  }

  GeminiChatResponse generateResponse({
    required String userMessage,
    String? energyLevel,
    int? fatigueScore,
    List<WeakTopic>? weakTopics,
    List<ExamSchedule>? upcomingExams,
    bool isOffDay = false,
    String? referencedItems,
    String? errorMessage,
  }) {
    final lower = userMessage.toLowerCase();
    String responseText;
    final actions = <ChatAction>[];

    if (errorMessage != null) {
      final sanitizedErr = sanitizeErrorMessage(errorMessage);
      final errLower = sanitizedErr.toLowerCase();
      String diagnosis;

      if (errLower.contains('api_key_invalid') ||
          errLower.contains('api key not valid') ||
          errLower.contains('invalid api key')) {
        diagnosis = '🔑 **API Key অবৈধ বা ভুল।**\nঅনুগ্রহ করে Google AI Studio থেকে নতুন API Key কপি করে Settings এ পেস্ট করুন।';
      } else if (errLower.contains('429') ||
          errLower.contains('resource_exhausted') ||
          errLower.contains('quota')) {
        diagnosis = '⏳ **Quota / Rate Limit শেষ হয়েছে।**\nকিছুক্ষণ পর আবার চেষ্টা করুন বা Settings থেকে অন্য মডেল (Flash / Pro) সিলেক্ট করুন।';
      } else if (errLower.contains('location') ||
          errLower.contains('not supported in your country')) {
        diagnosis = '🌐 **জিও-লোকেশন রেস্ট্রিকশন।**\nGoogle AI Studio আপনার বর্তমান নেটওয়ার্ক আইপি থেকে সাময়িক রেস্ট্রিক্ট করেছে।';
      } else if (errLower.contains('socketexception') ||
          errLower.contains('failed host lookup') ||
          errLower.contains('network is unreachable') ||
          errLower.contains('connection refused') ||
          errLower.contains('handshake')) {
        diagnosis = '📶 **ইন্টারনেট সংযোগ সমস্যা।**\nফোনের ইন্টারনেট বা Wi-Fi চেক করুন।';
      } else {
        diagnosis = '🔍 **কারিগরি কারণ:** $sanitizedErr';
      }

      responseText =
          '''
⚠️ **API সংযোগে সমস্যা হয়েছে**
$diagnosis

---
অফলাইনে আপনার তথ্যের ওপর ভিত্তি করে সাহায্য করছি:
''';
    } else {
      responseText = '''
💡 **Gemini API Key সেট করা নেই (অফলাইন মোড সক্রিয়)**
সম্পূর্ণ AI ফিচারের জন্য Settings এ গিয়ে আপনার Gemini API Key যুক্ত করুন। 
বর্তমানে আপনার লোকাল ডেটাবেসের তথ্যের ওপর ভিত্তি করে উত্তর দেওয়া হলো:
''';
    }

    final fatigue = fatigueScore ?? 5;
    final hasHighFatigue = fatigue >= 7;

    if (isOffDay && !lower.contains('ক্লান্ত')) {
      responseText += '''
* 🌴 আজ আপনার অফ-ডে (বৃহস্পতিবার/শুক্রবার)! কোনো অফিসের চাপ নেই।
* আজকের দিনের জন্য ১-২টি মূল দুর্বল বিষয় (যেমন ব্যাকরণ বা গণিত) গভীরভাবে পড়ার চমৎকার সুযোগ।
* পাশাপাশি পরিবারকে ভালো সময় দিন।
''';
      if (weakTopics != null && weakTopics.isNotEmpty) {
        actions.add(
          ChatAction(
            type: ChatActionType.studyTask,
            title: '৩০ মিনিটের ডিপ ড্রিল: ${weakTopics.first.topicName}',
            subject: weakTopics.first.subject,
            minutes: 30,
          ),
        );
      }
    } else if (lower.contains('ক্লান্ত') ||
        lower.contains('fatigue') ||
        lower.contains('tired') ||
        hasHighFatigue) {
      responseText += '''
* আপনি সারা দিন কোডিং করে অফিস শেষে ক্লান্ত। BCS জার্নিতে সুস্থ থাকাটাই সবচেয়ে বড় স্ট্র্যাটেজি।
* আজ কোনো ভারি টপিক পড়বেন না। শুধু **৫-১০ মিনিট** যেকোনো একটি রিভিশন কার্ড দেখুন।
* বাকি সময়টা পরিবার/স্ত্রীর সাথে আড্ডা দিন এবং তাড়াতাড়ি ঘুমিয়ে পড়ুন।
''';
      actions.add(
        const ChatAction(
          type: ChatActionType.studyTask,
          title: '৫ মিনিটের ফর্মুলা কার্ড রিভিশন',
          subject: 'রিভিউ',
          minutes: 5,
        ),
      );
    } else if (lower.contains('সমাস') || lower.contains('samas')) {
      responseText += '''
### সমাস সহজে মনে রাখার ট্রিকস:
1. **দ্বন্দ্ব:** উভয় পদ প্রধান (মা ও বাবা = মা-বাবা)।
2. **দ্বিগু:** সংখ্যাবাচক শব্দের সমাহার এবং সমাস নিষ্পন্ন পদটি বিশেষ্য (ত্রিফলা, চৌরাস্তা)।
3. **কর্মধারয়:** পরপদ প্রধান, বিশেষণ + বিশেষ্য (নীল যে পদ্ম = নীলপদ্ম)।
4. **তৎপুরুষ:** পূর্বপদের বিভক্তি লোপ পায় (দুঃখকে প্রাপ্ত = দুঃখপ্রাপ্ত)।
5. **বহুব্রীহি:** পূর্বপদ বা পরপদ কোনোটির অর্থ না বুঝিয়ে ভিন্ন অর্থ বোঝায় (দশ আনন যার = দশানন/রাবণ)।
6. **অব্যয়ীভাব:** পূর্বপদের অব্যয়ের অর্থ প্রধান (কূলের সমীপে = উপকূল)।
''';
      actions.add(
        const ChatAction(
          type: ChatActionType.addTopic,
          title: 'Add "সমাস" to Weak Topics',
          subject: 'বাংলা ব্যাকরণ',
          topic: 'সমাস',
          proficiency: 'weak',
        ),
      );
    } else if ((lower.contains('রুটিন') &&
            (lower.contains('বানাও') ||
                lower.contains('তৈরি') ||
                lower.contains('plan') ||
                lower.contains('make') ||
                lower.contains('create') ||
                lower.contains('দাও'))) ||
        (lower.contains('routine') &&
            (lower.contains('make') ||
                lower.contains('create') ||
                lower.contains('build') ||
                lower.contains('banao') ||
                lower.contains('plan')))) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final startDate = todayStart.add(const Duration(days: 1));

      // 1. Detect requested duration in days (default to 3, or parsed number e.g. "৭ দিন", "7 days")
      int requestedDays = 3;
      final dayMatch = RegExp(r'(\d+|[০-৯]+)\s*(?:দিন|day)')
          .firstMatch(userMessage);
      if (dayMatch != null) {
        final parsed = int.tryParse(
          BengaliMathSanitizer.toEnglishDigits(dayMatch.group(1)!),
        );
        if (parsed != null && parsed >= 1 && parsed <= 30) {
          requestedDays = parsed;
        }
      } else if (lower.contains('সপ্তাহ') || lower.contains('week')) {
        requestedDays = 7;
      }

      // 2. Detect requested daily study hours (e.g. "৩ ঘণ্টা", "3 hours")
      int? dailyHours;
      final hourMatch = RegExp(r'(\d+|[০-৯]+)\s*(?:ঘণ্টা|ঘন্টা|hour)')
          .firstMatch(userMessage);
      if (hourMatch != null) {
        dailyHours = int.tryParse(
          BengaliMathSanitizer.toEnglishDigits(hourMatch.group(1)!),
        );
      }

      // 3. Resolve referenced exam if user mentioned E-{id}
      ExamSchedule? matchedExam;
      final examRefMatch = RegExp(
        r'E-(\d+)',
        caseSensitive: false,
      ).firstMatch(userMessage);
      if (examRefMatch != null) {
        final examId = int.tryParse(examRefMatch.group(1)!);
        if (examId != null && upcomingExams != null) {
          matchedExam = upcomingExams.where((e) => e.id == examId).firstOrNull;
        }
      }
      matchedExam ??= upcomingExams?.firstOrNull;

      String planTitle = 'স্টাডি রুটিন';
      String track = 'AI Study Sprint';
      String subject = 'General BCS';
      List<String> topicPool = [];

      // Extract exam syllabus & metadata from referencedItems if available
      if (referencedItems != null && examRefMatch != null) {
        final refTag = 'E-${examRefMatch.group(1)}';
        if (referencedItems.contains(refTag)) {
          final syllabusMatch = RegExp(r'সিলেবাস:\s*([^\n]+)')
              .firstMatch(referencedItems);
          if (syllabusMatch != null) {
            final rawSyllabus = syllabusMatch.group(1)!.trim();
            topicPool = rawSyllabus
                .split(RegExp(r'[,;\n]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
          final subjectMatch = RegExp(r'বিষয়:\s*([^·\n]+)')
              .firstMatch(referencedItems);
          final titleMatch = RegExp(r'scheduled exam:\s*([^\n]+)')
              .firstMatch(referencedItems);
          final trackMatch = RegExp(r'ট্র্যাক:\s*([^\n·]+)')
              .firstMatch(referencedItems);

          subject =
              subjectMatch?.group(1)?.trim() ??
              matchedExam?.subject ??
              'General BCS';
          track =
              trackMatch?.group(1)?.trim() ??
              matchedExam?.trackName ??
              'AI Study Sprint';
          planTitle =
              titleMatch?.group(1)?.trim() ??
              matchedExam?.title ??
              'স্টাডি রুটিন';
        }
      }

      if (topicPool.isEmpty && matchedExam != null) {
        planTitle = matchedExam.title;
        track = matchedExam.trackName;
        subject = matchedExam.subject;
        topicPool = matchedExam.topicsCovered
            .split(RegExp(r'[,;\n]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }

      if (topicPool.isEmpty) {
        topicPool = [
          'বাংলা ব্যাকরণ ও সাহিত্য',
          'English Vocabulary & Grammar',
          'বাংলাদেশ বিষয়াবলি',
          'আন্তর্জাতিক বিষয়াবলি',
          'গাণিতিক যুক্তি ও মানসিক দক্ষতা',
          'সাধারণ বিজ্ঞান ও প্রযুক্তি',
        ];
      }

      final items = <Map<String, dynamic>>[];
      final previewLines = <String>[];

      for (var i = 0; i < requestedDays; i++) {
        final dayNum = i + 1;
        final isLastDay = (dayNum == requestedDays);
        final isPenultimateDay =
            (requestedDays >= 5 && dayNum == requestedDays - 1);
        final date = startDate
            .add(Duration(days: i))
            .toIso8601String()
            .substring(0, 10);

        List<String> dayTopics;
        String dayTitle;
        String examType;

        if (isLastDay) {
          dayTopics = ['সম্পূর্ণ সিলেবাস ফাইনাল রিভিশন ও পূর্ণাঙ্গ মক টেস্ট'];
          dayTitle = 'Day $dayNum: ফাইনাল রিভিশন ও মক টেস্ট';
          examType = 'Mock Test';
        } else if (isPenultimateDay) {
          dayTopics = ['গুরুত্বপূর্ণ টপিক রিভিশন ও দুর্বল অংশ সমাধান'];
          dayTitle = 'Day $dayNum: দ্রুত রিভিশন ও প্র্যাকটিস';
          examType = 'Study Session';
        } else {
          final topicIndex = i % topicPool.length;
          dayTopics = [topicPool[topicIndex]];
          dayTitle = 'Day $dayNum: ${dayTopics.first} প্রস্তুতি';
          examType = 'Study Session';
        }

        items.add({
          'date': date,
          'exam_time': '10:00 PM',
          'subject': subject,
          'title': dayTitle,
          'topics': dayTopics,
          'exam_type': examType,
          'track_name': track,
          'resource_summary': 'AI Mentor Plan',
        });

        previewLines.add(
          '* **Day $dayNum:** ${dayTopics.join(", ")} (${examType == "Mock Test" ? "মক টেস্ট" : "স্টাডি সেশন"})',
        );
      }

      final bnDays = BengaliMathSanitizer.toBengaliDigits('$requestedDays');
      final formattedPlanTitle = '$planTitle ($bnDays দিন)';

      final routineJson = jsonEncode({
        'title': formattedPlanTitle,
        'subject': subject,
        'track': track,
        'items': items,
      });

      final hoursNote = dailyHours != null
          ? '\n*(প্রতিদিন ${BengaliMathSanitizer.toBengaliDigits('$dailyHours')} ঘণ্টা পড়ার সময় অনুযায়ী বিন্যস্ত)*'
          : '';

      responseText +=
          '''
📋 **আপনার জন্য $bnDays দিনের স্টাডি রুটিন খসড়া তৈরি করা হয়েছে:**$hoursNote
${previewLines.join('\n')}

নিচের **"রুটিন প্রিভিউ"** বাটনে ট্যাপ করে প্রতিটি দিনের শিডিউল দেখে নিয়ে আপনার মূল রুটিনে যোগ করুন।
''';
      actions.add(
        ChatAction(
          type: ChatActionType.routinePlan,
          title: formattedPlanTitle,
          subject: subject,
          trackName: track,
          routineJson: routineJson,
        ),
      );
    } else if (lower.contains('পরীক্ষা') ||
        lower.contains('exam') ||
        lower.contains('routine')) {
      if (upcomingExams != null && upcomingExams.isNotEmpty) {
        final next = upcomingExams.first;
        responseText +=
            '''
📅 আপনার পরবর্তী পরীক্ষা: **${next.title}** [${next.trackName}] (${next.examDate.toIso8601String().substring(0, 10)})
🎯 টপিকসমূহ: ${next.topicsCovered}

**পরামর্শ:**
* নতুন কোনো বই পড়ার দরকার নেই।
* LiveMCQ অ্যাপে এই টপিকের বিগত বছরের প্রশ্নগুলো সলভ করুন।
''';
      } else {
        responseText += 'বর্তমানে কোনো আসন্ন পরীক্ষার শিডিউল নেই। LiveMCQ থেকে রুটিন PDF শেয়ার বা আপলোড করে নিন!';
      }
    } else {
      responseText += '''
আমি আপনার স্টাডি ও লাইফ পার্টনার।
* আপনার যেকোনো দুর্বল টপিক (যেমন বাংলা ব্যাকরণ, গণিত, বিজ্ঞান) বুঝিয়ে দিতে পারি।
* টপিক আলোচনার পর চাইলে এক ক্লিকে আপনার **Weak Topics** লিস্টে যুক্ত করে নিতে পারবেন।
* আপনার অফিস ক্লান্তি ও এনার্জি অনুযায়ী কাস্টম মাইক্রো-টাস্ক তৈরি করে দেব।

কী বিষয়ে জানতে বা আলোচনা করতে চান বলুন!
''';
    }

    return GeminiChatResponse(
      text: responseText,
      actions: actions,
      modelUsed: 'offline-local',
    );
  }
}
