import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/config/notification_constants.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_prompts.dart';
import 'package:life_and_study_assistant/core/services/ai/models/adaptive_study_plan.dart';
import 'package:life_and_study_assistant/core/services/ai/models/study_task.dart';

void main() {
  group('Notification & Automation Constants Tests', () {
    test('Notification channels and action ids are properly defined', () {
      expect(NotificationConstants.officeChannelId, isNotEmpty);
      expect(NotificationConstants.mealChannelId, isNotEmpty);
      expect(NotificationConstants.actionMealYes, equals('meal_action_yes'));
      expect(NotificationConstants.actionMealNo, equals('meal_action_no'));
      expect(
        NotificationConstants.actionCheckInDone,
        equals('checkin_action_done'),
      );
    });
  });

  group('Adaptive AI Study Planner Models & Prompt Tests', () {
    test('StudyTask JSON serialization and deserialization', () {
      final task = StudyTask(
        id: 'task_1',
        title: '১০টি বিগত বছরের MCQ: কারক ও বিভক্তি',
        subject: 'Bangla Grammar',
        estimatedMinutes: 10,
        taskType: 'micro_mcq',
        actionablePrompt: 'Solve 10 questions in LiveMCQ',
        isCompleted: false,
      );

      final json = task.toJson();
      final fromJson = StudyTask.fromJson(json);

      expect(fromJson.id, equals('task_1'));
      expect(fromJson.estimatedMinutes, equals(10));
      expect(fromJson.subject, equals('Bangla Grammar'));
      expect(fromJson.isCompleted, isFalse);
    });

    test('AdaptiveStudyPlan serialization with micro-commitments', () {
      final plan = AdaptiveStudyPlan(
        date: '2026-10-26',
        energyLevel: 'Low',
        fatigueScore: 8,
        motivationalQuote: 'Take it easy tonight.',
        summary: '10 minute micro-task only.',
        recommendedStudyMinutes: 10,
        recommendedFamilyMinutes: 90,
        familyAndWellbeingAdvice: 'Spend time with spouse and rest.',
        burnoutWarning: 'High fatigue detected',
        tasks: [
          StudyTask(
            id: 'task_1',
            title: '10 MCQs on Bangla Karok',
            subject: 'Bangla Grammar',
            estimatedMinutes: 10,
            taskType: 'micro_mcq',
            actionablePrompt: 'Solve 10 questions in LiveMCQ',
          ),
        ],
      );

      final jsonStr = plan.toJsonString();
      final parsed = AdaptiveStudyPlan.fromJsonString(jsonStr);

      expect(parsed, isNotNull);
      expect(parsed!.energyLevel, equals('Low'));
      expect(parsed.fatigueScore, equals(8));
      expect(parsed.recommendedStudyMinutes, equals(10));
      expect(parsed.recommendedFamilyMinutes, equals(90));
      expect(parsed.tasks.length, equals(1));
    });

    test('GeminiPrompts builds structured prompt with user context', () {
      final prompt = GeminiPrompts.buildStudyPlanPrompt(
        energyLevel: 'Low',
        fatigueScore: 8,
        weakTopics: [
          {'subject': 'Bangla Grammar', 'topic': 'কারক ও বিভক্তি'},
        ],
        upcomingExams: [
          {'title': 'LiveMCQ Final 14', 'examDate': '2026-10-28'},
        ],
      );

      expect(prompt, contains('User Energy Level: Low'));
      expect(prompt, contains('Office Fatigue Score: 8 / 10'));
      expect(prompt, contains('কারক ও বিভক্তি'));
      expect(prompt, contains('LiveMCQ Final 14'));
    });

    test('the plan schema still demands every field the model reads', () {
      // These used to be spelled out as example JSON in the prompt. They moved
      // into responseSchema, where the API enforces them, so the contract is
      // checked there now.
      final schema = studyPlanSchema.toJson();
      final properties = (schema['properties'] as Map).keys
          .cast<String>()
          .toSet();

      expect(
        properties,
        containsAll(<String>[
          'date',
          'energyLevel',
          'fatigueScore',
          'motivationalQuote',
          'summary',
          'recommendedStudyMinutes',
          'recommendedFamilyMinutes',
          'familyAndWellbeingAdvice',
          'burnoutWarning',
          'tasks',
        ]),
      );

      final task = ((schema['properties'] as Map)['tasks'] as Map)['items'];
      final taskProps = ((task as Map)['properties'] as Map).keys
          .cast<String>()
          .toSet();

      expect(
        taskProps,
        containsAll(<String>[
          'id',
          'title',
          'subject',
          'estimatedMinutes',
          'taskType',
          'actionablePrompt',
        ]),
      );
    });
  });
}
