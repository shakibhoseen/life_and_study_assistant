import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';

enum MistakeSource {
  liveMcqVoice(
    label: 'LiveMCQ Voice',
    banglaLabel: 'লাইভ এমসিকিউ ভয়েস',
    icon: Icons.mic_external_on_rounded,
    color: Color(0xFF8B5CF6),
  ),
  bookScan(
    label: 'Book OCR / Scan',
    banglaLabel: 'বইয়ের স্ক্যান / ভিশন',
    icon: Icons.camera_alt_outlined,
    color: Color(0xFF6366F1),
  ),
  modelTest(
    label: 'Drill / Model Test',
    banglaLabel: 'মডেল টেস্ট / ড্রিল',
    icon: Icons.assignment_outlined,
    color: Color(0xFF0EA5E9),
  );

  final String label;
  final String banglaLabel;
  final IconData icon;
  final Color color;

  const MistakeSource({
    required this.label,
    required this.banglaLabel,
    required this.icon,
    required this.color,
  });
}

MistakeSource detectMistakeSource(DrillQuestion dq) {
  final topicLower = dq.topic.toLowerCase();
  final explanationLower = dq.explanation.toLowerCase();

  if (dq.explanation.contains('LiveMCQ') ||
      topicLower.contains('livemcq') ||
      topicLower.contains('ভয়েস') ||
      topicLower.contains('voice')) {
    return MistakeSource.liveMcqVoice;
  }

  if (topicLower.contains('ocr') ||
      topicLower.contains('vision') ||
      topicLower.contains('বই') ||
      topicLower.contains('scan') ||
      explanationLower.contains('ocr')) {
    return MistakeSource.bookScan;
  }

  return MistakeSource.modelTest;
}

class MistakeSubjectFolder {
  final String id;
  final String displayName;
  final IconData icon;
  final Color color;
  final List<DrillQuestion> questions;

  const MistakeSubjectFolder({
    required this.id,
    required this.displayName,
    required this.icon,
    required this.color,
    required this.questions,
  });

  int get totalCount => questions.length;
  int get masteredCount => questions.where((q) => q.isMastered).length;
  int get pendingCount => questions.where((q) => !q.isMastered).length;
  double get masteryRate =>
      totalCount == 0 ? 0.0 : (masteredCount / totalCount) * 100.0;
}

/// Categorizes a list of mistakes into standardized & custom subject folders.
List<MistakeSubjectFolder> groupMistakesIntoFolders(
  List<DrillQuestion> allMistakes,
) {
  final Map<String, List<DrillQuestion>> map = {};

  for (final q in allMistakes) {
    final normalizedKey = _normalizeSubjectKey(q.subject);
    map.putIfAbsent(normalizedKey, () => []).add(q);
  }

  final List<MistakeSubjectFolder> folders = [];

  // Pre-defined ordered categories if they contain items
  final knownConfigs = [
    _CategoryConfig(
      key: 'bangla',
      displayName: 'বাংলা ভাষা ও সাহিত্য',
      icon: Icons.menu_book_rounded,
      color: const Color(0xFF059669),
    ),
    _CategoryConfig(
      key: 'english',
      displayName: 'English Language & Lit',
      icon: Icons.language_rounded,
      color: const Color(0xFF2563EB),
    ),
    _CategoryConfig(
      key: 'bangladesh',
      displayName: 'বাংলাদেশ বিষয়াবলি',
      icon: Icons.flag_rounded,
      color: const Color(0xFFDC2626),
    ),
    _CategoryConfig(
      key: 'international',
      displayName: 'আন্তর্জাতিক বিষয়াবলি',
      icon: Icons.public_rounded,
      color: const Color(0xFF0284C7),
    ),
    _CategoryConfig(
      key: 'math',
      displayName: 'গাণিতিক যুক্তি ও মানসিক',
      icon: Icons.calculate_rounded,
      color: const Color(0xFFD97706),
    ),
    _CategoryConfig(
      key: 'science',
      displayName: 'সাধারণ বিজ্ঞান ও আইসিটি',
      icon: Icons.science_rounded,
      color: const Color(0xFF7C3AED),
    ),
    _CategoryConfig(
      key: 'geography_ethics',
      displayName: 'ভূগোল ও সুশাসন',
      icon: Icons.landscape_rounded,
      color: const Color(0xFF0D9488),
    ),
  ];

  for (final config in knownConfigs) {
    if (map.containsKey(config.key) && map[config.key]!.isNotEmpty) {
      folders.add(
        MistakeSubjectFolder(
          id: config.key,
          displayName: config.displayName,
          icon: config.icon,
          color: config.color,
          questions: map[config.key]!,
        ),
      );
    }
  }

  // Any remaining custom subjects (e.g., Petrobangla Technical, Engineering, etc.)
  map.forEach((key, list) {
    final alreadyAdded = folders.any((f) => f.id == key);
    if (!alreadyAdded && list.isNotEmpty) {
      final sampleSubject = list.first.subject;
      folders.add(
        MistakeSubjectFolder(
          id: key,
          displayName: sampleSubject,
          icon: Icons.folder_special_rounded,
          color: const Color(0xFF4F46E5),
          questions: list,
        ),
      );
    }
  });

  return folders;
}

String _normalizeSubjectKey(String rawSubject) {
  final lower = rawSubject.toLowerCase().trim();
  if (lower.contains('petrobangla') || lower.contains('পেট্রোবাংলা')) {
    return 'petrobangla';
  }
  if (lower.contains('bangla') || lower.contains('বাংলা')) return 'bangla';
  if (lower.contains('english') || lower.contains('ইংরেজি')) return 'english';
  if (lower.contains('bangladesh') || lower.contains('বাংলাদেশ')) {
    return 'bangladesh';
  }
  if (lower.contains('international') || lower.contains('আন্তর্জাতিক')) {
    return 'international';
  }
  if (lower.contains('math') ||
      lower.contains('গণিত') ||
      lower.contains('mental') ||
      lower.contains('মানসিক')) {
    return 'math';
  }
  if (lower.contains('science') ||
      lower.contains('বিজ্ঞান') ||
      lower.contains('ict') ||
      lower.contains('আইসিটি') ||
      lower.contains('computer') ||
      lower.contains('তথ্যপ্রযুক্তি')) {
    return 'science';
  }
  if (lower.contains('geography') ||
      lower.contains('ভূগোল') ||
      lower.contains('ethics') ||
      lower.contains('নৈতিকতা')) {
    return 'geography_ethics';
  }
  return lower;
}

class _CategoryConfig {
  final String key;
  final String displayName;
  final IconData icon;
  final Color color;

  const _CategoryConfig({
    required this.key,
    required this.displayName,
    required this.icon,
    required this.color,
  });
}
