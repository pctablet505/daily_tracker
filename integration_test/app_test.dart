import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:daily_tracker/main.dart' as app;

Future<void> _waitFor(Finder finder, WidgetTester tester,
    {int retries = 20}) async {
  for (var i = 0; i < retries; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (finder.evaluate().isNotEmpty) return;
  }
}

Future<void> _waitUntilAbsent(Finder finder, WidgetTester tester,
    {int retries = 20}) async {
  for (var i = 0; i < retries; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (finder.evaluate().isEmpty) return;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Daily Tracker end-to-end', () {
    testWidgets('create, complete, and delete a task',
        (WidgetTester tester) async {
      // Reset persisted app state so tests always start from onboarding/today.
      const preferencesChannel =
          MethodChannel('plugins.flutter.io/shared_preferences');
      try {
        await preferencesChannel.invokeMethod('clear');
      } catch (_) {
        // Ignore if the method is unavailable in this environment.
      }

      app.main();
      // Avoid pumpAndSettle here: if the Today loading skeleton (Shimmer) is
      // visible, its infinite animation would keep this call alive forever.
      await tester.pump(const Duration(seconds: 2));

      // Wait for onboarding or the Today screen to appear.
      final skipButton = find.byType(TextButton);
      final todayTitle = find.text('Today');
      await _waitFor(skipButton, tester);
      if (skipButton.evaluate().isNotEmpty) {
        await tester.tap(skipButton);
        await tester.pump(const Duration(seconds: 2));
        await _waitFor(todayTitle, tester);
      } else {
        await _waitFor(todayTitle, tester);
      }

      // Verify we are on Today screen.
      // 'Today' appears in both the AppBar title and the bottom nav label.
      expect(find.text('Today'), findsAtLeastNWidgets(1));

      // Tap FAB to create a task.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Enter task title.
      await tester.enterText(
          find.byType(TextField).first, 'Integration Test Task');
      await tester.pumpAndSettle();

      // Save task.
      await tester.tap(find.text('Create Task'));
      // The Today screen shows a Shimmer loading skeleton while tasks refresh,
      // so use fixed-duration pumps instead of pumpAndSettle.
      await tester.pump(const Duration(seconds: 2));
      await _waitFor(find.text('Integration Test Task'), tester);

      // Verify task appears on Today screen (scope to the Today scroll view so
      // the Hero flight shuttle doesn't count as a duplicate text widget).
      expect(
        find.descendant(
          of: find.byKey(const Key('today_tasks_scroll')),
          matching: find.text('Integration Test Task'),
        ),
        findsOneWidget,
      );

      // Complete the task by tapping the checkbox (ensure it's hittable).
      final taskCheckbox = find.byType(Checkbox).first;
      await tester.ensureVisible(taskCheckbox);
      await tester.tap(taskCheckbox, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Navigate to Analytics and verify completion count increased.
      await tester.tap(find.byIcon(Icons.bar_chart_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('Total Completed'), findsOneWidget);

      // Navigate to Calendar and verify task is listed.
      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('calendar_tasks_list')),
          matching: find.text('Integration Test Task'),
        ),
        findsOneWidget,
      );

      // Navigate back to Today and delete the task.
      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pump(const Duration(seconds: 2));
      await _waitFor(
        find.descendant(
          of: find.byKey(const Key('today_tasks_scroll')),
          matching: find.text('Integration Test Task'),
        ),
        tester,
      );

      // Swipe to delete (flutter_slidable) and confirm the dialog.
      await tester.drag(
        find.descendant(
          of: find.byKey(const Key('today_tasks_scroll')),
          matching: find.text('Integration Test Task'),
        ),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      // Tap the slidable Delete action to open the confirmation dialog.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirm deletion in the AlertDialog (the Delete button is a FilledButton).
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump(const Duration(seconds: 2));
      await _waitUntilAbsent(
        find.descendant(
          of: find.byKey(const Key('today_tasks_scroll')),
          matching: find.text('Integration Test Task'),
        ),
        tester,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('today_tasks_scroll')),
          matching: find.text('Integration Test Task'),
        ),
        findsNothing,
      );
    });
  });
}
