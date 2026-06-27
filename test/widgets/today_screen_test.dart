import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_tracker/data/models/task_model.dart';
import 'package:daily_tracker/presentation/features/tasks/today_screen.dart';
import 'package:daily_tracker/presentation/providers/task_provider.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('TodayScreen', () {
    testWidgets('shows empty state when no tasks', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            allTasksProvider.overrideWith((ref) => []),
            completedTasksTodayProvider.overrideWith((ref) => []),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No tasks for today'), findsOneWidget);
      expect(find.text('Add Task'), findsOneWidget);
    });

    testWidgets('renders pending and completed sections',
        (WidgetTester tester) async {
      final tasks = [
        TaskModel(
          id: '1',
          title: 'Drink water',
          category: 'Do',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        TaskModel(
          id: '2',
          title: 'Avoid sugar',
          category: 'Don\'t',
          isCompleted: true,
          completedAt: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            allTasksProvider.overrideWith((ref) => tasks),
            completedTasksTodayProvider.overrideWith((ref) => [tasks[1]]),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DOs (1)'), findsOneWidget);
      expect(find.text('DON\'Ts Completed (1)'), findsOneWidget);
      expect(find.text('Drink water'), findsOneWidget);
      expect(find.text('Avoid sugar'), findsOneWidget);
    });

    testWidgets('search filters tasks', (WidgetTester tester) async {
      final tasks = [
        TaskModel(
          id: '1',
          title: 'Drink water',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        TaskModel(
          id: '2',
          title: 'Exercise',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            allTasksProvider.overrideWith((ref) => tasks),
            completedTasksTodayProvider.overrideWith((ref) => []),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'water');
      await tester.pumpAndSettle();

      expect(find.text('Drink water'), findsOneWidget);
      expect(find.text('Exercise'), findsNothing);
    });

    testWidgets('category chips filter tasks', (WidgetTester tester) async {
      final tasks = [
        TaskModel(
          id: '1',
          title: 'Work task',
          category: 'Work',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        TaskModel(
          id: '2',
          title: 'Health task',
          category: 'Health',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            allTasksProvider.overrideWith((ref) => tasks),
            completedTasksTodayProvider.overrideWith((ref) => []),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Work'));
      await tester.pumpAndSettle();

      expect(find.text('Work task'), findsOneWidget);
      expect(find.text('Health task'), findsNothing);
    });
  });
}

Widget _buildTestApp({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: const TodayScreen(),
      // Provide a simple GoRouter so context.push does not crash.
      builder: (context, child) {
        final router = GoRouter(
          initialLocation: '/today',
          routes: [
            GoRoute(
              path: '/today',
              builder: (context, state) => child!,
            ),
            GoRoute(
              path: '/task/:id',
              builder: (context, state) =>
                  const Scaffold(body: Text('Task Detail')),
            ),
          ],
        );
        return MaterialApp.router(
          routerConfig: router,
        );
      },
    ),
  );
}
