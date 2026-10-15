import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../state/providers.dart';

/// Deletes a habit after a confirmation, with an Undo in a snackbar. The photo
/// files go only once the snackbar has closed without Undo.
Future<bool> confirmAndDeleteHabit(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final actions = ref.read(actionsProvider);
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${habit.name}"?'),
      content: const Text(
        'Its history is deleted with it. To keep the history, archive the habit instead.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep it'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (sure != true) return false;
  final DeletedHabit gone = await actions.deleteHabit(habit.id);
  messenger.hideCurrentSnackBar();
  // False when the habit could not be brought back: it stays deleted.
  Future<bool> undo() async {
    try {
      await actions.undoDelete(gone);
      return true;
    } catch (e) {
      debugPrint('Bringing back a deleted habit failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not bring it back.')),
      );
      return false;
    }
  }

  Future<bool>? undone;
  unawaited(
    messenger
        .showSnackBar(
          SnackBar(
            content: Text('Deleted ${habit.name}'),
            duration: const Duration(seconds: 6),
            // An action would otherwise keep it open until tapped, and the
            // photos go only once it closes.
            persist: false,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => undone = undo(),
            ),
          ),
        )
        .closed
        .then((_) async {
          if (undone == null || !await undone!) {
            await actions.finishDelete(gone);
          }
        })
        // The photos left behind go with the sweep at the next start.
        .catchError(
          (Object e) => debugPrint('Removing deleted photos failed: $e'),
        ),
  );
  return true;
}
