import 'package:flutter_test/flutter_test.dart';
import 'package:daily_tracker/data/models/task_model.dart';
import 'package:daily_tracker/data/models/task_log_model.dart';
import 'package:daily_tracker/data/models/daily_completion_model.dart';

void main() {
  group('TaskModel Tests', () {
    test('toMap/fromMap roundtrip preserves all fields', () {
      final original = TaskModel(
        id: 'test-id-123',
        title: 'Test Task',
        description: 'A description',
        createdAt: DateTime(2024, 6, 15, 10, 30),
        updatedAt: DateTime(2024, 6, 15, 12, 0),
        reminderTime: DateTime(2024, 6, 15, 14, 0),
        isCompleted: true,
        isRecurring: true,
        recurrenceRule: 'daily',
        category: 'Do',
        taskType: 'numeric',
        priority: 2,
        completedAt: DateTime(2024, 6, 15, 11, 0),
        isDeleted: true,
        version: 3,
        syncStatus: 'synced',
      );

      final map = original.toMap();
      final restored = TaskModel.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.title, equals(original.title));
      expect(restored.description, equals(original.description));
      expect(restored.isCompleted, isTrue);
      expect(restored.isRecurring, isTrue);
      expect(restored.recurrenceRule, equals('daily'));
      expect(restored.category, equals('Do'));
      expect(restored.taskType, equals('numeric'));
      expect(restored.priority, equals(2));
      expect(restored.isDeleted, isTrue);
      expect(restored.version, equals(3));
      expect(restored.syncStatus, equals('synced'));
    });

    test('fromMap with null optional fields uses defaults', () {
      final map = {
        'id': 'minimal-id',
        'title': 'Minimal',
        'createdAt': '2024-06-15T10:00:00.000',
        'updatedAt': '2024-06-15T10:00:00.000',
        'isCompleted': 0,
        'isRecurring': 0,
        'priority': 0,
        'isDeleted': 0,
        'version': 1,
        'syncStatus': 'pending',
      };

      final task = TaskModel.fromMap(map);
      expect(task.description, isNull);
      expect(task.reminderTime, isNull);
      expect(task.recurrenceRule, isNull);
      expect(task.category, isNull);
      expect(task.taskType, equals('checklist'));
      expect(task.completedAt, isNull);
    });

    test('fromMap with zero values for boolean fields', () {
      final map = {
        'id': 'zero-test',
        'title': 'Zero Test',
        'createdAt': '2024-06-15T10:00:00.000',
        'updatedAt': '2024-06-15T10:00:00.000',
        'isCompleted': 0,
        'isRecurring': 0,
        'priority': 0,
        'isDeleted': 0,
        'version': 1,
        'syncStatus': 'pending',
      };

      final task = TaskModel.fromMap(map);
      expect(task.isCompleted, isFalse);
      expect(task.isRecurring, isFalse);
      expect(task.isDeleted, isFalse);
    });

    test('copyWith overrides only specified fields', () {
      final original = TaskModel(
        id: 'original',
        title: 'Original',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      final updated = original.copyWith(title: 'Updated', priority: 1);
      expect(updated.id, equals('original'));
      expect(updated.title, equals('Updated'));
      expect(updated.priority, equals(1));
      expect(updated.isCompleted, equals(original.isCompleted));
    });

    test('equatable equality works correctly', () {
      final a = TaskModel(id: '1', title: 'A', createdAt: DateTime(2024, 1, 1), updatedAt: DateTime(2024, 1, 1));
      final b = TaskModel(id: '1', title: 'A', createdAt: DateTime(2024, 1, 1), updatedAt: DateTime(2024, 1, 1));
      final c = TaskModel(id: '2', title: 'B', createdAt: DateTime(2024, 1, 1), updatedAt: DateTime(2024, 1, 1));

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toMap produces correct SQLite-compatible values', () {
      final task = TaskModel(
        id: 'sqlite-test',
        title: 'SQLite Test',
        createdAt: DateTime(2024, 6, 15, 10, 30, 45),
        updatedAt: DateTime(2024, 6, 15, 10, 30, 45),
        isCompleted: true,
        isRecurring: false,
      );

      final map = task.toMap();
      expect(map['isCompleted'], equals(1));
      expect(map['isRecurring'], equals(0));
      expect(map['isDeleted'], equals(0));
      expect(map['createdAt'], equals('2024-06-15T10:30:45.000'));
    });
  });

  group('TaskLogModel Tests', () {
    test('roundtrip with all fields including mediaPath', () {
      final original = TaskLogModel(
        id: 'log-1',
        taskId: 'task-1',
        date: '2024-06-15',
        isCompleted: true,
        completedAt: DateTime(2024, 6, 15, 8, 30),
        comment: 'Did great today',
        mediaPath: '/photos/progress.jpg',
        createdAt: DateTime(2024, 6, 15, 8, 30),
        updatedAt: DateTime(2024, 6, 15, 20, 0),
        syncStatus: 'synced',
      );

      final map = original.toMap();
      final restored = TaskLogModel.fromMap(map);

      expect(restored.id, equals('log-1'));
      expect(restored.taskId, equals('task-1'));
      expect(restored.date, equals('2024-06-15'));
      expect(restored.isCompleted, isTrue);
      expect(restored.comment, equals('Did great today'));
      expect(restored.mediaPath, equals('/photos/progress.jpg'));
    });

    test('fromMap with minimal fields', () {
      final map = {
        'id': 'min-log',
        'taskId': 'task-1',
        'date': '2024-06-15',
        'isCompleted': 0,
        'createdAt': '2024-06-15T10:00:00.000',
        'updatedAt': '2024-06-15T10:00:00.000',
        'syncStatus': 'pending',
      };

      final log = TaskLogModel.fromMap(map);
      expect(log.comment, isNull);
      expect(log.mediaPath, isNull);
      expect(log.completedAt, isNull);
      expect(log.isCompleted, isFalse);
    });

    test('comment can be empty string', () {
      final log = TaskLogModel(
        id: 'empty-comment',
        taskId: 'task-1',
        date: '2024-06-15',
        comment: '',
        createdAt: DateTime(2024, 6, 15),
        updatedAt: DateTime(2024, 6, 15),
      );

      final map = log.toMap();
      expect(map['comment'], equals(''));
    });
  });

  group('DailyCompletionModel Tests', () {
    test('roundtrip with edge case values', () {
      final original = DailyCompletionModel(
        id: '2024-06-15',
        date: DateTime(2024, 6, 15),
        totalTasks: 0,
        completedTasks: 0,
        completionRate: 0.0,
        createdAt: DateTime(2024, 6, 15, 23, 59, 59),
      );

      final map = original.toMap();
      final restored = DailyCompletionModel.fromMap(map);

      expect(restored.totalTasks, equals(0));
      expect(restored.completedTasks, equals(0));
      expect(restored.completionRate, equals(0.0));
    });

    test('completionRate handles floating point', () {
      final completion = DailyCompletionModel(
        id: 'fp-test',
        date: DateTime(2024, 6, 15),
        totalTasks: 3,
        completedTasks: 1,
        completionRate: 0.3333333333,
      );

      final map = completion.toMap();
      final restored = DailyCompletionModel.fromMap(map);
      expect(restored.completionRate, closeTo(0.3333333333, 0.0001));
    });

    test('fromMap with null createdAt', () {
      final map = {
        'id': 'no-created',
        'date': '2024-06-15T00:00:00.000',
        'totalTasks': 5,
        'completedTasks': 3,
        'completionRate': 0.6,
      };

      final restored = DailyCompletionModel.fromMap(map);
      expect(restored.createdAt, isNull);
    });

    test('createdAt fallback in toMap when null', () {
      final completion = DailyCompletionModel(
        id: 'fallback',
        date: DateTime(2024, 6, 15),
        totalTasks: 1,
        completedTasks: 1,
        completionRate: 1.0,
      );

      final map = completion.toMap();
      expect(map['createdAt'], isNotNull);
    });
  });
}
