import 'package:flutter_test/flutter_test.dart';
import 'package:daily_tracker/core/services/export_service.dart';
import 'package:daily_tracker/data/local/database_helper.dart';
import 'package:daily_tracker/data/models/task_model.dart';
import 'package:daily_tracker/data/models/daily_completion_model.dart';
import 'package:daily_tracker/data/models/task_log_model.dart';

class MockDatabaseHelper implements DatabaseHelper {
  final List<TaskModel> tasks = [];
  final List<DailyCompletionModel> completions = [];
  final List<TaskLogModel> logs = [];

  @override
  Future<List<TaskModel>> getAllActiveTasks() async {
    return tasks;
  }

  @override
  Future<List<DailyCompletionModel>> getDailyCompletionsRange(DateTime start, DateTime end) async {
    return completions;
  }

  @override
  Future<List<TaskLogModel>> getAllTaskLogs() async {
    return logs;
  }

  @override
  Future<String> insertTask(TaskModel task) async {
    tasks.add(task);
    return task.id;
  }

  @override
  Future<void> upsertDailyCompletion(DailyCompletionModel completion) async {
    completions.add(completion);
  }

  @override
  Future<String> insertTaskLog(TaskLogModel log) async {
    logs.add(log);
    return log.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ExportService Tests', () {
    late MockDatabaseHelper mockDb;
    late ExportService exportService;

    setUp(() {
      mockDb = MockDatabaseHelper();
      exportService = ExportService(mockDb);
    });

    test('Export and import task logs JSON successfully', () async {
      // 1. Arrange: add sample data to mock DB
      final task = TaskModel(
        id: 'task-1',
        title: 'No Sugar',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final completion = DailyCompletionModel(
        id: 'comp-1',
        date: DateTime.now(),
        totalTasks: 5,
        completedTasks: 3,
        completionRate: 0.6,
      );
      final log = TaskLogModel(
        id: 'log-1',
        taskId: 'task-1',
        date: '2026-05-31',
        isCompleted: true,
        comment: 'Felt great, avoided sugar',
        mediaPath: '/media/sugar.jpg',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      mockDb.tasks.add(task);
      mockDb.completions.add(completion);
      mockDb.logs.add(log);

      // 2. Act: Export to JSON
      final jsonString = await exportService.exportToJson();

      // 3. Verify JSON contains the exported task log fields
      expect(jsonString, contains('task-1'));
      expect(jsonString, contains('No Sugar'));
      expect(jsonString, contains('Felt great, avoided sugar'));
      expect(jsonString, contains('/media/sugar.jpg'));

      // 4. Act: Reset DB and Import from JSON
      mockDb.tasks.clear();
      mockDb.completions.clear();
      mockDb.logs.clear();

      final success = await exportService.importFromJson(jsonString);

      // 5. Assert: Verify import succeeded and data restored
      expect(success, isTrue);
      expect(mockDb.tasks, hasLength(1));
      expect(mockDb.tasks.first.title, 'No Sugar');

      expect(mockDb.completions, hasLength(1));
      expect(mockDb.completions.first.completedTasks, 3);

      expect(mockDb.logs, hasLength(1));
      expect(mockDb.logs.first.comment, 'Felt great, avoided sugar');
      expect(mockDb.logs.first.mediaPath, '/media/sugar.jpg');
    });
  });
}
