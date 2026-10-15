import 'package:daily_tracker/ui/screens/habits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpAll(loadAppFont);

  testWidgets('a write does not blank the list to a spinner', (tester) async {
    final l = sampleLedger();
    await pumpScreen(
      tester,
      const Scaffold(body: HabitsScreen()),
      overrides: [...await baseOverrides(), ledgerByRevision(l, l)],
    );
    expect(find.text('Go for a run'), findsOneWidget);
    bumpRevision(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Go for a run'), findsOneWidget);
  });

  testWidgets('a habit cannot be moved while an area filter is on', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const Scaffold(body: HabitsScreen()),
      overrides: await baseOverrides(ledger: sampleLedger()),
      size: const Size(360, 1600),
    );
    final semantics = tester.ensureSemantics();
    expect(_moveActions(tester, 'Go for a run'), isNotEmpty);
    await tester.tap(find.widgetWithText(FilterChip, 'Health'));
    await tester.pumpAndSettle();
    // Moving would do nothing: the full order has no place for it.
    expect(_moveActions(tester, 'Go for a run'), isEmpty);
    semantics.dispose();
  });

  // The stand-in database fails every write.
  testWidgets('a move that did not save says so', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(body: HabitsScreen()),
      overrides: await baseOverrides(ledger: sampleLedger()),
      size: const Size(360, 1600),
    );
    final semantics = tester.ensureSemantics();
    _performMove(tester, 'Go for a run', 'Move down');
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(find.text('That did not save. Try again.'), findsOneWidget);
  });

  testWidgets('a delete that did not save says so', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(body: HabitsScreen()),
      overrides: await baseOverrides(ledger: sampleLedger()),
      size: const Size(360, 1600),
    );
    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('That did not save. Try again.'), findsOneWidget);
  });
}

/// Runs the screen reader's [action] on the row that shows [title].
void _performMove(WidgetTester tester, String title, String action) {
  for (
    SemanticsNode? n = tester.getSemantics(find.text(title));
    n != null;
    n = n.parent
  ) {
    for (final id
        in n.getSemanticsData().customSemanticsActionIds ?? const <int>[]) {
      if (CustomSemanticsAction.getAction(id)!.label == action) {
        n.owner!.performAction(n.id, SemanticsAction.customAction, id);
        return;
      }
    }
  }
  fail('no "$action" on $title');
}

/// The screen reader's custom actions on the row that shows [title].
List<String> _moveActions(WidgetTester tester, String title) {
  final labels = <String>[];
  for (
    SemanticsNode? n = tester.getSemantics(find.text(title));
    n != null;
    n = n.parent
  ) {
    for (final id
        in n.getSemanticsData().customSemanticsActionIds ?? const <int>[]) {
      labels.add(CustomSemanticsAction.getAction(id)!.label!);
    }
  }
  return labels;
}
