import 'dart:convert';

import '../logic/habit_form.dart';
import 'models.dart';

const packFormat = 'daily-tracker-pack';
const packVersion = 1;
const maxPackHabits = 100;

/// A set of habits to add in one go. Packs are data: the ones below ship with
/// the app, and anyone can load their own from a file.
final class StarterPack {
  const StarterPack({
    required this.id,
    required this.name,
    required this.description,
    required this.habits,
  });
  final String id;
  final String name;
  final String description;
  final List<HabitForm> habits;
}

// Starter packs

const starterPacks = <StarterPack>[
  StarterPack(
    id: 'morning',
    name: 'Morning routine',
    description: 'Start your day with energy and focus.',
    habits: [
      HabitForm(
        name: 'Drink a glass of water',
        dayPart: DayPart.morning,
        area: 'Health',
      ),
      HabitForm(
        name: 'Stretch for 5 minutes',
        dayPart: DayPart.morning,
        area: 'Health',
      ),
      HabitForm(
        name: 'Meditate for 10 minutes',
        dayPart: DayPart.morning,
        area: 'Mind',
      ),
      HabitForm(name: 'Plan your day', dayPart: DayPart.morning, area: 'Work'),
    ],
  ),
  StarterPack(
    id: 'workout',
    name: 'Workout',
    description: 'Build strength and endurance.',
    habits: [
      HabitForm(name: 'Warm up 5 min', area: 'Health'),
      HabitForm(name: 'Main workout 30 min', area: 'Health'),
      HabitForm(name: 'Cool down stretch', area: 'Health'),
      HabitForm(name: 'Drink protein shake', area: 'Health'),
    ],
  ),
  StarterPack(
    id: 'evening',
    name: 'Evening wind-down',
    description: 'Relax and prepare for quality sleep.',
    habits: [
      HabitForm(
        name: 'Review today’s accomplishments',
        dayPart: DayPart.evening,
        area: 'Mind',
      ),
      HabitForm(
        name: 'Prepare for tomorrow',
        dayPart: DayPart.evening,
        area: 'Work',
      ),
      HabitForm(
        name: 'Read for 20 minutes',
        dayPart: DayPart.evening,
        area: 'Mind',
      ),
      HabitForm(
        name: 'No screens 30 min before bed',
        kind: HabitKind.avoid,
        dayPart: DayPart.evening,
        area: 'Health',
      ),
    ],
  ),
  StarterPack(
    id: 'healthy',
    name: 'Healthy habits',
    description: 'Nourish your body and mind.',
    habits: [
      HabitForm(name: 'Eat 3 healthy meals', area: 'Health'),
      HabitForm(
        name: 'Drink 8 glasses of water',
        logType: LogType.number,
        unit: 'glasses',
        goalText: '8',
        area: 'Health',
      ),
      HabitForm(
        name: 'Take vitamins',
        dayPart: DayPart.morning,
        area: 'Health',
      ),
      HabitForm(
        name: 'Walk 10,000 steps',
        logType: LogType.number,
        unit: 'steps',
        goalText: '10000',
        area: 'Health',
      ),
    ],
  ),
  StarterPack(
    id: 'productivity',
    name: 'Productivity',
    description: 'Maximize your output and focus.',
    habits: [
      HabitForm(name: 'Complete top 3 priorities', area: 'Work'),
      HabitForm(name: 'Check emails (2 times only)', area: 'Work'),
      HabitForm(name: 'Take a break every 90 min', area: 'Work'),
      HabitForm(
        name: 'Update task list',
        dayPart: DayPart.evening,
        area: 'Work',
      ),
    ],
  ),
  StarterPack(
    id: 'selfcare',
    name: 'Self care',
    description: 'Take time for yourself.',
    habits: [
      HabitForm(name: 'Skincare routine', area: 'Health'),
      HabitForm(
        name: 'Journal for 10 minutes',
        logType: LogType.note,
        dayPart: DayPart.evening,
        area: 'Mind',
      ),
      HabitForm(name: 'Call a loved one', area: 'People'),
      HabitForm(name: 'Practice gratitude', area: 'Mind'),
    ],
  ),
];

// Pack files

Map<String, Object?> _habitMap(HabitForm f) => {
  'name': f.name,
  if (f.description.isNotEmpty) 'description': f.description,
  'kind': f.kind.name,
  'logType': f.logType.name,
  if (f.unit.isNotEmpty) 'unit': f.unit,
  if (f.goalText.isNotEmpty) 'goal': f.goalText,
  'daysMask': f.daysMask,
  'dayPart': f.dayPart.name,
  if (f.reminderMinutes != null) 'reminderMinutes': f.reminderMinutes,
  if (f.area.isNotEmpty) 'area': f.area,
  'avoidMode': f.avoidMode.name,
};

String encodePack(StarterPack pack) =>
    const JsonEncoder.withIndent('  ').convert({
      'format': packFormat,
      'version': packVersion,
      'name': pack.name,
      'description': pack.description,
      'habits': [for (final h in pack.habits) _habitMap(h)],
    });

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('Unknown value in the pack', name.toString());
}

/// Reads a pack file. Throws [FormatException] with a message fit to show.
StarterPack decodePack(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const FormatException('This is not a Daily Tracker pack.');
  }
  if (root is! Map<String, Object?> || root['format'] != packFormat) {
    throw const FormatException('This is not a Daily Tracker pack.');
  }
  final version = root['version'];
  if (version is! int)
    throw const FormatException('The pack has no version number.');
  if (version < 1) throw const FormatException('The pack file is damaged.');
  if (version > packVersion) {
    throw const FormatException(
      'This pack was made by a newer version of the app. Update the app and try again.',
    );
  }
  const damaged = FormatException('The pack file is damaged.');
  int? finiteInt(Object? v) {
    if (v == null) return null;
    if (v is! num || !v.isFinite) throw damaged;
    return v.toInt();
  }

  try {
    final name = (root['name'] as String?)?.trim() ?? '';
    final list = root['habits'] as List<Object?>? ?? const [];
    if (name.isEmpty || list.isEmpty) throw damaged;
    if (list.length > maxPackHabits)
      throw const FormatException('This pack has too many habits.');
    final habits = <HabitForm>[];
    for (final raw in list) {
      final m = raw! as Map<String, Object?>;
      final habitName = (m['name'] as String?)?.trim() ?? '';
      if (habitName.isEmpty) throw damaged;
      final goal = m['goal'];
      if (goal is num && !goal.isFinite) throw damaged;
      final rem = finiteInt(m['reminderMinutes']);
      if (rem != null && (rem < 0 || rem >= 24 * 60)) throw damaged;
      final form = HabitForm(
        name: habitName,
        description: (m['description'] as String?) ?? '',
        kind: _enum(HabitKind.values, m['kind'], HabitKind.build),
        logType: _enum(LogType.values, m['logType'], LogType.tick),
        unit: (m['unit'] as String?) ?? '',
        goalText: goal == null
            ? ''
            : (goal is num ? goal.toString() : goal as String),
        daysMask: finiteInt(m['daysMask']) ?? Habit.everyDay,
        dayPart: _enum(DayPart.values, m['dayPart'], DayPart.anytime),
        reminderMinutes: rem,
        area: (m['area'] as String?) ?? '',
        avoidMode: _enum(AvoidMode.values, m['avoidMode'], AvoidMode.track),
      );
      if (!form.isValid ||
          (goal is String && form.goal == null && goal.trim().isNotEmpty))
        throw damaged;
      habits.add(form);
    }
    return StarterPack(
      id: 'file',
      name: name,
      description: (root['description'] as String?) ?? '',
      habits: habits,
    );
  } on TypeError {
    throw damaged;
  } on FormatException catch (e) {
    if (identical(e, damaged) || e.message.contains('too many')) rethrow;
    throw damaged;
  }
}

// Adding a pack

typedef PackPlan = ({List<HabitForm> toAdd, List<String> skipped});

String _key(String name) => name.trim().toLowerCase();

/// Which habits of [pack] to add: those whose name is not already used by an
/// active habit (or earlier in the same pack). Archived habits do not count.
PackPlan planPackApply(Iterable<Habit> existing, StarterPack pack) {
  final taken = {
    for (final h in existing)
      if (!h.isArchived) _key(h.name),
  };
  final toAdd = <HabitForm>[];
  final skipped = <String>[];
  for (final f in pack.habits) {
    if (taken.add(_key(f.name))) {
      toAdd.add(f);
    } else {
      skipped.add(f.name);
    }
  }
  return (toAdd: toAdd, skipped: skipped);
}

// First-run suggestions

/// What the first-run screen offers to start with: things to do, then things to stay clear of.
const onboardingDo = <HabitForm>[
  HabitForm(
    name: 'Drink water',
    logType: LogType.number,
    unit: 'glasses',
    goalText: '8',
    area: 'Health',
  ),
  HabitForm(name: 'Exercise', dayPart: DayPart.morning, area: 'Health'),
  HabitForm(name: 'Walk outside', area: 'Health'),
  HabitForm(name: 'Read', dayPart: DayPart.evening, area: 'Mind'),
  HabitForm(name: 'Meditate', dayPart: DayPart.morning, area: 'Mind'),
  HabitForm(
    name: 'Journal',
    logType: LogType.note,
    dayPart: DayPart.evening,
    area: 'Mind',
  ),
  HabitForm(
    name: 'Weigh yourself',
    logType: LogType.number,
    unit: 'kg',
    dayPart: DayPart.morning,
    area: 'Health',
  ),
  HabitForm(name: 'Take vitamins', dayPart: DayPart.morning, area: 'Health'),
];

const onboardingAvoid = <HabitForm>[
  HabitForm(name: 'No added sugar', kind: HabitKind.avoid, area: 'Health'),
  HabitForm(
    name: 'No caffeine after noon',
    kind: HabitKind.avoid,
    area: 'Health',
  ),
  HabitForm(
    name: 'No social media scrolling',
    kind: HabitKind.avoid,
    area: 'Mind',
  ),
  HabitForm(
    name: 'No late-night snacks',
    kind: HabitKind.avoid,
    dayPart: DayPart.evening,
    area: 'Health',
  ),
];
