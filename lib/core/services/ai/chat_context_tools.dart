import 'package:google_generative_ai/google_generative_ai.dart';

import 'chat_context_resolver.dart';

/// The user context the mentor can pull on demand, already in memory.
///
/// Reading these from the local database is free, so they are always loaded;
/// what costs tokens is putting them in the prompt. [ChatContextResolver]
/// decides what goes in up front, and anything it left out stays here, ready
/// to be handed over if the model asks for it.
class ChatContextData {
  final List<Map<String, dynamic>> weakTopics;
  final List<Map<String, dynamic>> exams;
  final String? energyLevel;
  final int? fatigueScore;
  final bool isOffDay;

  const ChatContextData({
    this.weakTopics = const [],
    this.exams = const [],
    this.energyLevel,
    this.fatigueScore,
    this.isOffDay = false,
  });
}

/// On-demand context for the mentor, as Gemini function declarations.
///
/// The keyword matcher in [ChatContextResolver] handles the common cases for
/// free. This is the safety net for the rest: when the matcher decides a slice
/// is not needed, the slice is replaced by a *declaration* the model can call
/// if it turns out to disagree.
///
/// The trade is deliberate. A declaration costs a few dozen tokens; the slice
/// itself costs hundreds. A call costs a whole extra round trip, which is why
/// every description tells the model not to call unless the answer genuinely
/// depends on it.
class ChatContextToolset {
  ChatContextToolset._();

  static const String getWeakTopics = 'get_weak_topics';
  static const String getUpcomingExams = 'get_upcoming_exams';
  static const String getEnergyStatus = 'get_energy_status';

  /// Exam syllabus strings can be enormous; cap them in tool responses too.
  static const int topicsCharLimit = 120;

  /// Declares exactly the slices that are *not* already in the prompt and that
  /// there is actually data to serve.
  ///
  /// Returns null when nothing is worth declaring, so the request carries no
  /// tool overhead at all.
  static Tool? declarationsFor(ChatContextNeeds needs, ChatContextData data) {
    final declarations = <FunctionDeclaration>[];

    if (!needs.weakTopics && data.weakTopics.isNotEmpty) {
      declarations.add(
        FunctionDeclaration(
          getWeakTopics,
          'Look up the subjects and topics this user has registered as weak. '
          'Call this ONLY when the reply depends on what this specific user '
          'personally struggles with — for example they asked what to revise, '
          'or for a study plan. Do NOT call it to explain a concept.',
          Schema.object(
            properties: {
              'subject': Schema.string(
                description: 'Optional. Narrow to one subject name, e.g. "বাংলা ব্যাকরণ".',
                nullable: true,
              ),
            },
          ),
        ),
      );
    }

    if (!needs.exams && data.exams.isNotEmpty) {
      declarations.add(
        FunctionDeclaration(
          getUpcomingExams,
          'List this user\'s upcoming LiveMCQ / BCS exams with how many days '
          'away each one is and what it covers. Call this ONLY when the reply '
          'depends on exam dates, deadlines or exam coverage.',
          Schema.object(
            properties: {
              'within_days': Schema.integer(
                description: 'Optional horizon in days. Defaults to 30.',
                nullable: true,
              ),
            },
          ),
        ),
      );
    }

    if (!needs.energy) {
      declarations.add(
        FunctionDeclaration(
          getEnergyStatus,
          'Get today\'s energy level, office fatigue score (0-10) and whether '
          'today is an off-day. Call this ONLY before prescribing study '
          'workload or session length.',
          null,
        ),
      );
    }

    if (declarations.isEmpty) return null;
    return Tool(functionDeclarations: declarations);
  }

  /// Answers a function call from [data] — no database round trip, because
  /// everything was already loaded before the request went out.
  static Map<String, Object?> resolve(FunctionCall call, ChatContextData data) {
    switch (call.name) {
      case getWeakTopics:
        final subject = call.args['subject'] as String?;
        var topics = data.weakTopics;
        if (subject != null && subject.trim().isNotEmpty) {
          final target = subject.trim().toLowerCase();
          final filtered = topics
              .where(
                (t) => (t['subject'] ?? '').toString().toLowerCase().contains(
                  target,
                ),
              )
              .toList();
          if (filtered.isNotEmpty) topics = filtered;
        }
        return {'count': topics.length, 'topics': topics};

      case getUpcomingExams:
        final within = (call.args['within_days'] as num?)?.toInt() ?? 30;
        final exams = data.exams
            .where((e) {
              final days = e['daysAway'];
              return days is! int || days <= within;
            })
            .map(
              (e) => {
                'title': e['title'],
                'track': e['track'],
                'daysAway': e['daysAway'],
                'topics': _shorten(e['topics']?.toString(), topicsCharLimit),
              },
            )
            .toList();
        return {'count': exams.length, 'exams': exams};

      case getEnergyStatus:
        return {
          'energyLevel': data.energyLevel ?? 'Moderate',
          'officeFatigueScore': data.fatigueScore ?? 5,
          'isOffDay': data.isOffDay,
        };

      default:
        return {'error': 'Unknown function: ${call.name}'};
    }
  }

  static String _shorten(String? value, int max) {
    final v = value?.trim() ?? '';
    if (v.length <= max) return v;
    return '${v.substring(0, max)}…';
  }
}
