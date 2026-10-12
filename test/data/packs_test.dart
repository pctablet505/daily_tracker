import 'dart:convert';

import 'package:daily_tracker/data/models.dart';
import 'package:daily_tracker/data/packs.dart';
import 'package:daily_tracker/logic/habit_form.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  const pack = StarterPack(
    id: 'p',
    name: 'Mine',
    description: 'Test pack',
    habits: [
      HabitForm(
        name: 'Drink water',
        logType: LogType.number,
        unit: 'glasses',
        goalText: '8',
        dayPart: DayPart.morning,
        area: 'Health',
      ),
      HabitForm(name: 'No sugar', kind: HabitKind.avoid),
      HabitForm(
        name: 'Journal',
        logType: LogType.note,
        reminderMinutes: 21 * 60,
        daysMask: 31,
      ),
    ],
  );

  group('pack file', () {
    test('a pack survives encode then decode', () {
      final back = decodePack(encodePack(pack));
      expect(back.name, 'Mine');
      expect(back.description, 'Test pack');
      expect(back.habits.map((h) => h.name), [
        'Drink water',
        'No sugar',
        'Journal',
      ]);
      final water = back.habits.first;
      expect(
        (water.logType, water.unit, water.goalText, water.dayPart, water.area),
        (LogType.number, 'glasses', '8', DayPart.morning, 'Health'),
      );
      expect(back.habits[1].kind, HabitKind.avoid);
      expect(back.habits[1].logsSlips, isTrue);
      expect(
        (back.habits[2].reminderMinutes, back.habits[2].daysMask),
        (21 * 60, 31),
      );
    });

    test('says what it is', () {
      final m = jsonDecode(encodePack(pack)) as Map<String, Object?>;
      expect((m['format'], m['version']), ('daily-tracker-pack', 1));
    });

    test('a minimal pack with only names is fine and gets defaults', () {
      final p = decodePack(
        jsonEncode({
          'format': 'daily-tracker-pack',
          'version': 1,
          'name': 'Tiny',
          'habits': [
            {'name': 'Stretch'},
          ],
        }),
      );
      expect(p.habits.single.logType, LogType.tick);
      expect(p.habits.single.daysMask, Habit.everyDay);
      expect(p.description, '');
    });

    group('is refused when', () {
      void refused(String why, Object? json) {
        test(
          why,
          () => expect(
            () => decodePack(json is String ? json : jsonEncode(json)),
            throwsFormatException,
          ),
        );
      }

      Map<String, Object?> good() => {
        'format': 'daily-tracker-pack',
        'version': 1,
        'name': 'X',
        'habits': [
          {'name': 'a'},
        ],
      };

      refused('it is not JSON', 'nope');
      refused('it is a backup, not a pack', {
        ...good(),
        'format': 'daily-tracker-backup',
      });
      refused('it is from a newer version', {...good(), 'version': 2});
      refused('it has a non-positive version', {...good(), 'version': 0});
      refused('a reminder is out of range', {
        ...good(),
        'habits': [
          {'name': 'a', 'reminderMinutes': 1440},
        ],
      });
      refused('it has no name', {...good()}..remove('name'));
      refused('it has no habits', {...good(), 'habits': []});
      refused('a habit has no name', {
        ...good(),
        'habits': [
          {'kind': 'build'},
        ],
      });
      refused('a habit has a blank name', {
        ...good(),
        'habits': [
          {'name': '  '},
        ],
      });
      refused('a habit has an unknown kind', {
        ...good(),
        'habits': [
          {'name': 'a', 'kind': 'maybe'},
        ],
      });
      refused('a habit has the wrong type of field', {
        ...good(),
        'habits': [
          {'name': 'a', 'goal': 'lots'},
        ],
      });
      refused('a number habit has a goal that is not a number', {
        ...good(),
        'habits': [
          {'name': 'a', 'logType': 'number', 'goal': 'lots'},
        ],
      });
      refused('a habit is not on any day', {
        ...good(),
        'habits': [
          {'name': 'a', 'daysMask': 0},
        ],
      });
      refused('a habit name is too long', {
        ...good(),
        'habits': [
          {'name': 'x' * 61},
        ],
      });
      refused('it holds too many habits', {
        ...good(),
        'habits': [
          for (var i = 0; i < 101; i++) {'name': 'h$i'},
        ],
      });
    });
  });

  group('adding a pack to what you already have', () {
    test('adds all of it to an empty app', () {
      final plan = planPackApply(const [], pack);
      expect(plan.toAdd.length, 3);
      expect(plan.skipped, isEmpty);
    });

    test('skips habits with the same name, ignoring case and spaces', () {
      final plan = planPackApply([
        habit('1').copyWith(name: '  drink WATER '),
      ], pack);
      expect(plan.toAdd.map((h) => h.name), ['No sugar', 'Journal']);
      expect(plan.skipped, ['Drink water']);
    });

    test(
      'an archived habit with the same name does not block adding it again',
      () {
        final archived = habit('1', end: tue).copyWith(name: 'Journal');
        expect(planPackApply([archived], pack).toAdd.length, 3);
      },
    );

    test('a name repeated inside the pack is added once', () {
      const dup = StarterPack(
        id: 'd',
        name: 'D',
        description: '',
        habits: [
          HabitForm(name: 'A'),
          HabitForm(name: ' a '),
        ],
      );
      final plan = planPackApply(const [], dup);
      expect(plan.toAdd.length, 1);
      expect(plan.skipped, [' a ']);
    });
  });

  group('the packs that ship with the app', () {
    test('there are some, with unique ids and valid habits', () {
      expect(starterPacks, isNotEmpty);
      expect(starterPacks.map((p) => p.id).toSet().length, starterPacks.length);
      for (final p in starterPacks) {
        expect(p.name, isNotEmpty);
        expect(p.habits, isNotEmpty, reason: p.name);
        for (final h in p.habits) {
          expect(h.isValid, isTrue, reason: '${p.name}: ${h.name}');
        }
        final names = p.habits.map((h) => h.name.toLowerCase()).toList();
        expect(
          names.toSet().length,
          names.length,
          reason: '${p.name} repeats a name',
        );
      }
    });

    test('the old generic templates are all still here, with their habits', () {
      final byName = {for (final p in starterPacks) p.name: p};
      for (final name in [
        'Morning routine',
        'Workout',
        'Evening wind-down',
        'Healthy habits',
        'Productivity',
        'Self care',
      ]) {
        expect(byName.containsKey(name), isTrue, reason: name);
      }
      expect(
        byName['Healthy habits']!.habits.map((h) => h.name),
        contains('Drink 8 glasses of water'),
      );
      expect(
        byName['Healthy habits']!.habits
            .firstWhere((h) => h.name.contains('water'))
            .logType,
        LogType.number,
      );
      expect(
        byName['Self care']!.habits
            .firstWhere((h) => h.name.contains('Journal'))
            .logType,
        LogType.note,
      );
      expect(
        byName['Evening wind-down']!.habits.any(
          (h) => h.kind == HabitKind.avoid,
        ),
        isTrue,
      );
    });

    test('no personal content ships in the app', () {
      final text = starterPacks
          .map(
            (p) =>
                '${p.name} ${p.description} ${p.habits.map((h) => h.name).join(' ')}',
          )
          .join(' ')
          .toLowerCase();
      expect(text.contains('headman'), isFalse);
    });
  });

  group('first-run suggestions', () {
    test(
      'are valid, have unique names, and the avoid ones are stay-clear habits',
      () {
        final all = [...onboardingDo, ...onboardingAvoid];
        for (final h in all) {
          expect(h.isValid, isTrue, reason: h.name);
        }
        expect(all.map((h) => h.name.toLowerCase()).toSet().length, all.length);
        expect(onboardingDo.every((h) => h.kind == HabitKind.build), isTrue);
        expect(onboardingAvoid.every((h) => h.logsSlips), isTrue);
      },
    );
  });
}
