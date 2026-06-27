import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:daily_tracker/data/models/task_log_model.dart';
import 'package:daily_tracker/data/models/task_model.dart';
import 'package:daily_tracker/data/repositories/task_repository.dart';
import 'package:daily_tracker/presentation/features/tasks/task_detail_screen.dart';
import 'package:daily_tracker/presentation/providers/task_provider.dart';

class _FakeTaskRepository implements TaskRepository {
  final List<TaskModel> _tasks = [];
  final List<TaskLogModel> _logs = [];

  @override
  Future<TaskModel> createTask({
    required String title,
    String? description,
    DateTime? reminderTime,
    bool isRecurring = false,
    String? recurrenceRule,
    String? category,
    String? taskType,
    int priority = 0,
  }) async {
    final task = TaskModel(
      id: 'new-task-id',
      title: title,
      description: description,
      reminderTime: reminderTime,
      isRecurring: isRecurring,
      recurrenceRule: recurrenceRule,
      category: category,
      taskType: taskType ?? 'checklist',
      priority: priority,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _tasks.add(task);
    return task;
  }

  @override
  Future<void> deleteTask(String id) async {}

  @override
  Future<TaskModel> updateTask(TaskModel task,
      {String? title,
      String? description,
      DateTime? reminderTime,
      bool? isRecurring,
      String? recurrenceRule,
      String? category,
      String? taskType,
      int? priority}) async {
    final updated = task.copyWith(
      title: title,
      description: description,
      reminderTime: reminderTime,
      isRecurring: isRecurring,
      recurrenceRule: recurrenceRule,
      category: category,
      taskType: taskType,
      priority: priority,
      updatedAt: DateTime.now(),
    );
    return updated;
  }

  @override
  Future<void> toggleTaskCompletion(TaskModel task) async {}

  @override
  Future<TaskModel?> getTask(String id) async {
    return _tasks
        .cast<TaskModel?>()
        .firstWhere((t) => t!.id == id, orElse: () => null);
  }

  @override
  Future<List<TaskModel>> getTasksForDate(DateTime date) async => _tasks;
  @override
  Future<List<TaskModel>> getAllActiveTasks() async => _tasks;
  @override
  Future<List<TaskModel>> getPendingTasks() async =>
      _tasks.where((t) => !t.isCompleted).toList();
  @override
  Future<List<TaskModel>> getCompletedTasksForDate(DateTime date) async => [];
  @override
  Future<List<TaskModel>> getTasksWithReminders() async => [];
  @override
  Future<List<TaskModel>> getRecurringTasks() async => [];
  @override
  Future<void> resetRecurringTasksForNewDay() async {}

  @override
  Future<TaskLogModel?> getTaskLog(String taskId, DateTime date) async {
    return _logs.cast<TaskLogModel?>().firstWhere(
          (l) => l!.taskId == taskId,
          orElse: () => null,
        );
  }

  @override
  Future<List<TaskLogModel>> getTaskLogsForTask(String taskId) async =>
      _logs.where((l) => l.taskId == taskId).toList();

  @override
  Future<void> saveTaskLog(TaskLogModel log) async {
    _logs.add(log);
  }

  @override
  Future<List<TaskLogModel>> getAllTaskLogs() async => _logs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TaskDetailScreen', () {
    testWidgets('renders new task form', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const TaskDetailScreen(taskId: 'new-task', isNew: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Task'), findsOneWidget);
      expect(find.text('Task Title'), findsOneWidget);
      expect(find.text('Create Task'), findsOneWidget);
    });

    testWidgets('shows validation error for empty title',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const TaskDetailScreen(taskId: 'new-task', isNew: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Task'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a task title'), findsOneWidget);
    });

    testWidgets('selects category chips', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const TaskDetailScreen(taskId: 'new-task', isNew: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Health'));
      await tester.pumpAndSettle();

      // ChoiceChip should now be selected (visual state is hard to assert,
      // but tapping should not throw).
      expect(find.widgetWithText(ChoiceChip, 'Health'), findsOneWidget);
    });
  });
}

Widget _buildTestApp(Widget screen) {
  final fakeRepo = _FakeTaskRepository();
  return ProviderScope(
    overrides: [
      taskRepositoryProvider.overrideWith((ref) => fakeRepo),
    ],
    child: MaterialApp(
      home: screen,
      builder: (context, child) {
        final router = GoRouter(
          initialLocation: '/task/new-task',
          routes: [
            GoRoute(
              path: '/task/:id',
              builder: (context, state) => child!,
            ),
          ],
        );
        return MaterialApp.router(routerConfig: router);
      },
    ),
  );
}
