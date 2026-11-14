import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/models/quiz_question.dart';

class BcsQuestionBankService {
  static const String assetPath = 'assets/data/bcs_core_questions.json';

  static List<QuizQuestion>? _cache;

  static Future<List<QuizQuestion>> loadAllQuestions() async {
    if (_cache != null && _cache!.isNotEmpty) {
      return _cache!;
    }

    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is List) {
        _cache = decoded
            .map((item) => QuizQuestion.fromJson(item as Map<String, dynamic>))
            .toList();
        return _cache!;
      }
    } catch (_) {
      // In case of parsing or asset missing, return empty list safely
    }

    return [];
  }

  static Future<List<QuizQuestion>> getQuestionsBySubject(String subject) async {
    final all = await loadAllQuestions();
    final query = subject.trim().toLowerCase();
    return all.where((q) {
      final s = (q.subject ?? '').toLowerCase();
      return s.contains(query);
    }).toList();
  }
}

final bcsQuestionBankProvider = FutureProvider<List<QuizQuestion>>((ref) async {
  return BcsQuestionBankService.loadAllQuestions();
});
