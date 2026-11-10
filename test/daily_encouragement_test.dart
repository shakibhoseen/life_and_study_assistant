import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_prompts.dart';
import 'package:life_and_study_assistant/core/services/ai/models/adaptive_study_plan.dart';
import 'package:life_and_study_assistant/features/study_planner/domain/daily_encouragement.dart';

/// There were four encouragement lines in the whole app, one per energy level,
/// so the same sentence came back every evening until it stopped being read.
void main() {
  group('picking the line', () {
    test('the same day gives the same line however often it is asked', () {
      final date = DateTime(2026, 11, 10);

      final first = encouragementFor(date: date, energyLevel: 'low');
      final again = encouragementFor(date: date, energyLevel: 'low');

      // The plan is rebuilt whenever the dashboard is reopened. A line that
      // changed each time would be a slot machine, not a companion.
      expect(again, first);
    });

    test('the time of day does not change it', () {
      final morning = DateTime(2026, 11, 10, 6, 30);
      final night = DateTime(2026, 11, 10, 23, 45);

      expect(
        encouragementFor(date: night, energyLevel: 'medium'),
        encouragementFor(date: morning, energyLevel: 'medium'),
      );
    });

    test('tomorrow is a different line', () {
      expect(
        encouragementFor(date: DateTime(2026, 11, 11), energyLevel: 'low'),
        isNot(encouragementFor(date: DateTime(2026, 11, 10), energyLevel: 'low')),
      );
    });

    test('a whole pool passes before anything repeats', () {
      final pool = encouragementPools[DayMood.low]!;
      final seen = <String>{};

      for (var i = 0; i < pool.length; i++) {
        seen.add(
          encouragementFor(
            date: DateTime(2026, 11, 10).add(Duration(days: i)),
            energyLevel: 'low',
          ),
        );
      }

      expect(seen.length, pool.length);
    });
  });

  group('which pool', () {
    test('an off day is its own kind of day', () {
      expect(
        moodFrom(energyLevel: 'low', isOffDay: true),
        DayMood.offDay,
      );
      expect(
        encouragementPools[DayMood.offDay],
        contains(
          encouragementFor(
            date: DateTime(2026, 11, 10),
            energyLevel: 'low',
            isOffDay: true,
          ),
        ),
      );
    });

    test('the energy wording is read loosely', () {
      // It comes from the model as well as from the local planner, so it
      // arrives as 'Low', 'low energy', or anything in between.
      expect(moodFrom(energyLevel: 'Low', isOffDay: false), DayMood.low);
      expect(moodFrom(energyLevel: '  high  ', isOffDay: false), DayMood.high);
      expect(moodFrom(energyLevel: 'HIGH energy', isOffDay: false), DayMood.high);
    });

    test('anything unrecognised lands on the middle pool', () {
      expect(moodFrom(energyLevel: '', isOffDay: false), DayMood.medium);
      expect(moodFrom(energyLevel: 'মাঝারি', isOffDay: false), DayMood.medium);
    });
  });

  group('the model is not asked for one', () {
    test('the plan schema has no field for it', () {
      final schema = jsonDecode(jsonEncode(studyPlanSchema.toJson())) as Map;
      final properties = (schema['properties'] as Map).keys.cast<String>();

      // Output that is never read is output paid for twice: once in tokens,
      // once in being ignored.
      expect(properties, isNot(contains('motivationalQuote')));
    });

    test('the prompt tells the model to spend the words elsewhere', () {
      final prompt = GeminiPrompts.buildStudyPlanPrompt(
        energyLevel: 'Low',
        fatigueScore: 8,
        weakTopics: const [],
        upcomingExams: const [],
        today: DateTime(2026, 11, 10),
      );

      expect(prompt, contains('Do not write any encouragement'));
    });

    test('a quote in the json is ignored, not shown', () {
      final plan = AdaptiveStudyPlan.fromJson({
        'date': '2026-11-10',
        'energyLevel': 'Low',
        'motivationalQuote': 'Small consistent steps lead to great things.',
        'tasks': const [],
      });

      // Plans cached before the change still carry one.
      expect(plan.motivationalQuote, isNot(contains('Small consistent')));
      expect(
        plan.motivationalQuote,
        encouragementFor(date: DateTime(2026, 11, 10), energyLevel: 'Low'),
      );
    });
  });

  group('the lines themselves', () {
    test('every pool has enough of them to not go stale in a week', () {
      for (final entry in encouragementPools.entries) {
        expect(
          entry.value.length,
          greaterThanOrEqualTo(7),
          reason: '${entry.key} has too few lines',
        );
      }
    });

    test('no line appears twice, in a pool or across them', () {
      final all = encouragementPools.values.expand((p) => p).toList();
      expect(all.toSet().length, all.length);
    });

    test('none of them is the stock saying that was there before', () {
      final all = encouragementPools.values.expand((p) => p);
      for (final line in all) {
        expect(line.contains('পদক্ষেপ'), isFalse, reason: line);
        expect(line.contains('পাহাড়'), isFalse, reason: line);
        expect(line.toLowerCase().contains('small steps'), isFalse);
      }
    });

    test('they are short enough to read on a card', () {
      for (final line in encouragementPools.values.expand((p) => p)) {
        expect(line.length, lessThanOrEqualTo(110), reason: line);
        expect(line.trim(), line);
        expect(line, isNotEmpty);
      }
    });
  });
}
