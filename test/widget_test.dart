import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_tracker/app.dart';
import 'package:daily_tracker/presentation/providers/task_provider.dart';
import 'package:daily_tracker/presentation/providers/update_provider.dart';
import 'package:daily_tracker/core/extensions/date_extensions.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Daily Tracker App smoke test', (WidgetTester tester) async {
    final today = DateTime.now().dateOnly;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasksForDateProvider(today).overrideWith((ref) => []),
          pendingTasksProvider.overrideWith((ref) => []),
          completedTasksTodayProvider.overrideWith((ref) => []),
          updateCheckProvider.overrideWith((ref) => null),
          allTasksProvider.overrideWith((ref) => []),
          allTaskLogsProvider.overrideWith((ref) => []),
        ],
        child: const DailyTrackerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DailyTrackerApp), findsOneWidget);
  });
}

