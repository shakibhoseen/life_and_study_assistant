import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/adaptive_study_plan.dart';
import 'package:life_and_study_assistant/core/services/ai/models/study_task.dart';
import 'package:life_and_study_assistant/features/study_planner/domain/study_task_completions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Finishing a micro-commitment used to leave no trace: the tick updated the
/// Riverpod state and nothing else, and the day's plan is re-read from its
/// cache on every rebuild, so the tick came back off every time.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StudyTaskCompletions.instance.clearAll();
  });

  Map<String, dynamic> taskJson({String? id, String title = 'MCQ ১০টি'}) => {
    'id': ?id,
    'title': title,
    'subject': 'বাংলা',
    'taskType': 'micro_mcq',
    'actionablePrompt': 'দশটি প্রশ্ন দেখে নিন',
  };

  group('a task id is the same every time the plan is read', () {
    test('an id the model gave is used as it is', () {
      expect(StudyTask.idFor(taskJson(id: 'abc'), 0), 'abc');
    });

    test('an id the model omitted is derived, not invented afresh', () {
      // It used to be DateTime.now().millisecondsSinceEpoch — a new id at
      // every parse, so nothing keyed on it could survive a rebuild.
      final first = StudyTask.idFor(taskJson(), 0);
      final second = StudyTask.idFor(taskJson(), 0);

      expect(first, second);
      expect(first, startsWith('task_'));
    });

    test('two different tasks still get different ids', () {
      expect(
        StudyTask.idFor(taskJson(title: 'MCQ ১০টি'), 0),
        isNot(StudyTask.idFor(taskJson(title: 'সূত্র মুখস্থ'), 0)),
      );
    });

    test('two identical tasks are told apart by their place', () {
      expect(
        StudyTask.idFor(taskJson(), 0),
        isNot(StudyTask.idFor(taskJson(), 1)),
      );
    });

    test('a whole plan parsed twice gives the same ids', () {
      Map<String, dynamic> planJson() => {
        'date': '2026-11-09',
        'energyLevel': 'medium',
        'fatigueScore': 5,
        'motivationalQuote': '',
        'summary': '',
        'recommendedStudyMinutes': 60,
        'recommendedFamilyMinutes': 30,
        'familyAndWellbeingAdvice': '',
        'tasks': [taskJson(), taskJson(title: 'সূত্র মুখস্থ'), taskJson()],
      };

      final first = AdaptiveStudyPlan.fromJson(planJson());
      final second = AdaptiveStudyPlan.fromJson(planJson());

      expect(
        first.tasks.map((t) => t.id).toList(),
        second.tasks.map((t) => t.id).toList(),
      );
      // Including the two that are word-for-word the same.
      expect(first.tasks.map((t) => t.id).toSet().length, 3);
    });
  });

  group('what was finished is remembered', () {
    const date = '2026-11-09';

    test('nothing is finished to begin with', () async {
      expect(await StudyTaskCompletions.instance.load(date), isEmpty);
    });

    test('a finished task is still finished when read back', () async {
      await StudyTaskCompletions.instance.setCompleted(
        date,
        'task_abc',
        done: true,
      );

      expect(
        await StudyTaskCompletions.instance.load(date),
        {'task_abc'},
      );
    });

    test('unticking takes it off again', () async {
      await StudyTaskCompletions.instance.setCompleted(
        date,
        'task_abc',
        done: true,
      );
      await StudyTaskCompletions.instance.setCompleted(
        date,
        'task_abc',
        done: false,
      );

      expect(await StudyTaskCompletions.instance.load(date), isEmpty);
    });

    test('finishing the same task twice is not two entries', () async {
      for (var i = 0; i < 3; i++) {
        await StudyTaskCompletions.instance.setCompleted(
          date,
          'task_abc',
          done: true,
        );
      }

      expect(await StudyTaskCompletions.instance.load(date).then((s) => s.length), 1);
    });

    test('one day says nothing about another', () async {
      await StudyTaskCompletions.instance.setCompleted(
        date,
        'task_abc',
        done: true,
      );

      expect(
        await StudyTaskCompletions.instance.load('2026-11-10'),
        isEmpty,
        reason: 'the plan is per day, and so are its ids',
      );
    });

    test('old days are swept rather than kept for ever', () async {
      final old = DateTime.now().subtract(const Duration(days: 40));
      final oldDate = old.toIso8601String().substring(0, 10);
      SharedPreferences.setMockInitialValues({
        'study_tasks_done_$oldDate': ['task_old'],
      });

      // Any write sweeps; the list lives in a file read in full at launch.
      await StudyTaskCompletions.instance.setCompleted(
        StudyTaskCompletions.today(),
        'task_new',
        done: true,
      );

      expect(await StudyTaskCompletions.instance.load(oldDate), isEmpty);
      expect(
        await StudyTaskCompletions.instance.load(StudyTaskCompletions.today()),
        {'task_new'},
      );
    });

    test('today is the date the plan is keyed on', () {
      expect(
        StudyTaskCompletions.today(),
        DateTime.now().toIso8601String().substring(0, 10),
      );
    });
  });
}
