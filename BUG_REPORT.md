# Daily Tracker - Comprehensive Bug Report

> **Status as of 2026-06-27:** All 31 issues below have been resolved in the current source (latest commit `7a8099e`). The file/line references are stale; use this document only as historical context. See `data/context/projects/daily-tracker/AGENTS.md` (or the project session logs) for the latest verification notes.

## Critical Bugs (Crash / Data Loss)

### 1. DatabaseHelper.getTaskLogsForDate - MISSING whereArgs [CRASH/DATA LEAK]
**File:** `lib/data/local/database_helper.dart:498-505`
**Issue:** Query has `where: 'date = ?'` but **no `whereArgs`** parameter. SQLite ignores the `?` placeholder and returns ALL task logs instead of filtering by date.
**Impact:** Any feature using this method gets wrong data. Could leak logs across dates.

### 2. TaskModel.fromMap - Unsafe null casts [CRASH]
**File:** `lib/data/models/task_model.dart:109-110`
**Issue:** `(map['isCompleted'] as int) == 1` and `(map['isRecurring'] as int) == 1` will throw `TypeError` if column value is null (corrupted DB, schema migration issue).
**Fix:** Use `(map['isCompleted'] as int? ?? 0) == 1`

### 3. TaskLogModel.fromMap - Unsafe DateTime.parse [CRASH]
**File:** `lib/data/models/task_log_model.dart:78-79`
**Issue:** `DateTime.parse(map['createdAt'] as String)` throws `FormatException` on corrupted/malformed date strings. No fallback.

### 4. DailyCompletionModel.fromMap - Unsafe DateTime.parse [CRASH]
**File:** `lib/data/models/daily_completion_model.dart:34-40`
**Issue:** Same as above - `DateTime.parse` with no error handling.

### 5. NotificationService.scheduleTaskReminder - No exact alarm permission check [CRASH]
**File:** `lib/services/notification/notification_service.dart:106`
**Issue:** On Android 12+ (API 31+), `zonedSchedule` with `exactAllowWhileIdle` throws `SecurityException` if `SCHEDULE_EXACT_ALARM` permission is not granted by user in system settings.
**Impact:** Task creation fails silently when reminder scheduling is attempted (though template tasks have no reminders, manual tasks with reminders crash).

### 6. ExportService.importFromJson - No transaction, causes duplicates [DATA CORRUPTION]
**File:** `lib/core/services/export_service.dart:70-103`
**Issue:** Import inserts on top of existing data without clearing first. If import fails halfway, partial corrupt data remains. No SQLite transaction wrapper.
**Impact:** Duplicate tasks, incomplete restores.

### 7. TaskActions.createTask - Reminder exception blocks provider refresh [UI BUG]
**File:** `lib/presentation/providers/task_provider.dart:94-111`
**Issue:** `await _reminderService.scheduleTaskReminder(task)` is called BEFORE `refreshAllTaskProviders()`. If reminder scheduling throws (e.g., permission denied), the exception propagates up, task is in DB but UI never refreshes.
**Impact:** User creates task, sees no update, thinks it failed.

---

## High Severity Bugs (Wrong Behavior)

### 8. CalendarScreen uses createdAt filter instead of showing all daily tasks [FUNCTIONAL]
**File:** `lib/presentation/features/calendar/calendar_screen.dart`
**Issue:** `tasksForDateProvider` calls `getTasksForDate()` which filters by `createdAt`. In a daily tracker, tasks should appear EVERY day, not just on their creation date.
**Impact:** Calendar shows empty for any day except when tasks were created.

### 9. DatabaseHelper._updateDailyCompletion counts ALL tasks for "today" [WRONG STATS]
**File:** `lib/data/local/database_helper.dart:250-280`
**Issue:** `totalResult` counts ALL `isDeleted = 0` tasks regardless of when they were created. A task created tomorrow would be counted in today's stats.
**Impact:** Completion rate, streak calculations are wrong.

### 10. AnalyticsScreen._loadStats - No error handling, infinite loading [UI FREEZE]
**File:** `lib/presentation/features/analytics/analytics_screen.dart:37-90`
**Issue:** If any DB query throws, `_isLoading` stays true forever. No try-catch around `_loadStats`.
**Impact:** Analytics screen permanently shows loading spinner on any DB error.

### 11. AppLockScreen._checkPin - Race condition with rapid input [SECURITY]
**File:** `lib/presentation/features/lock/app_lock_screen.dart:62-86`
**Issue:** `_enteredPin` is read in async `_checkPin()` after await. If user taps digits rapidly, `_enteredPin` can be modified between the await and the read.
**Impact:** Wrong PIN validation, potential lock bypass.

### 12. TodayScreen TaskCard - Controllers not reset when task changes [UI BUG]
**File:** `lib/presentation/features/tasks/today_screen.dart:404-415`
**Issue:** `didUpdateWidget` not overridden. If the same TaskCard widget is reused with a different task (e.g., in ListView recycling), controllers keep old values.
**Impact:** Wrong values shown for tasks.

### 13. TodayScreen TaskCard._saveAndComplete - _photoPath not reset after save [UI BUG]
**File:** `lib/presentation/features/tasks/today_screen.dart:667-719`
**Issue:** After saving a photo task, `_photoPath` stays set. If user interacts with another photo task, old photo appears.

### 14. TaskDetailScreen - _taskType null by default, dropdown shows empty [UI BUG]
**File:** `lib/presentation/features/tasks/task_detail_screen.dart:34`
**Issue:** `_taskType` initializes to null. Dropdown doesn't have a null item, so it shows as empty/blank.
**Fix:** Default to 'checklist'.

### 15. BackgroundService.registerUpdateCheck - ExistingWorkPolicy.keep [STALE SCHEDULES]
**File:** `lib/services/background/background_service.dart:111-122`
**Issue:** Uses `ExistingWorkPolicy.keep` which means if the periodic task already exists, it won't update the schedule. App updates that change the frequency won't take effect.
**Fix:** Use `ExistingWorkPolicy.update` or `replace`.

### 16. QuietHoursService.adjustForQuietHours - Strips sub-minute precision [BUG]
**File:** `lib/services/notification/quiet_hours_service.dart:28-52`
**Issue:** Reconstructs DateTime with only hour/minute from endParts, losing seconds and milliseconds from original scheduledTime. Also doesn't handle timezone properly.

### 17. SettingsScreen._importData - Doesn't clear existing data [DUPLICATES]
**File:** `lib/presentation/features/settings/settings_screen.dart:272-358`
**Issue:** Import adds to existing data without clearing first. User gets duplicate tasks.

### 18. ExportService.shareJsonExport - Temp file never cleaned up [STORAGE LEAK]
**File:** `lib/core/services/export_service.dart:35-41`
**Issue:** Creates temp file but never deletes it. Repeated exports fill up storage.

---

## Medium Severity Bugs (Code Smell / Edge Cases)

### 19. TodayScreen._saveAndComplete - No numeric validation for numeric tasks
**File:** `lib/presentation/features/tasks/today_screen.dart:677-684`
**Issue:** Any text can be entered for "numeric" tasks. No validation that input is actually a number.

### 20. TaskDetailScreen._pickReminderTime - Always sets to today
**File:** `lib/presentation/features/tasks/task_detail_screen.dart:423-436`
**Issue:** Reminder is always set to today's date. User can't schedule for tomorrow.

### 21. TaskDetailScreen._saveTask - Doesn't handle task not found for edit
**File:** `lib/presentation/features/tasks/task_detail_screen.dart:466-484`
**Issue:** If task was deleted while screen is open, `existing` is null and update is silently skipped.

### 22. DatabaseHelper.insertTask - Doesn't verify insert success
**File:** `lib/data/local/database_helper.dart:115-121`
**Issue:** `db.insert()` returns row ID. If it's -1 (error), code still returns `task.id` as if success.

### 23. SyncService - debugPrint statements in production code
**File:** `lib/services/sync/sync_service.dart`
**Issue:** Multiple debugPrint calls that log potentially sensitive info (emails, tokens).

### 24. UpdateService._isNewerVersion - Returns false for equal versions
**File:** `lib/services/notification/update_dialog.dart:67-82`
**Issue:** Actually correct behavior (no update for equal), but the catch block returns false which might suppress valid updates on parse errors.

### 25. TaskRepository.toggleTaskCompletion - Creates updated model but doesn't use for DB update
**File:** `lib/data/repositories/task_repository.dart:73-76`
**Issue:** Creates `updated` copy but only uses for reminder scheduling. The DB update uses `task.id` and computed `newStatus` directly.

### 26. TodayScreen - searchQueryProvider and selectedCategoryProvider persist across visits
**File:** `lib/presentation/features/tasks/today_screen.dart:15-17`
**Issue:** Global providers that aren't reset when leaving/returning to Today screen.

### 27. CalendarScreen - Checkbox onChanged doesn't handle errors
**File:** `lib/presentation/features/calendar/calendar_screen.dart:127-131`
**Issue:** If toggleCompletion throws, checkbox stays in visually toggled state but DB wasn't updated.

### 28. TaskActions._runMediaCleanup - Fire-and-forget without awaiting
**File:** `lib/presentation/providers/task_provider.dart:167-180`
**Issue:** Cleanup runs async but caller doesn't await. Potential race condition if deleteTask is called rapidly.

---

## Tests Issues

### 29. export_service_test.dart uses mocks (MockDatabaseHelper)
**File:** `test/export_service_test.dart`
**Issue:** Test uses mock instead of real code. Doesn't test actual serialization/deserialization edge cases (null fields, malformed JSON, version mismatch).

### 30. widget_test.dart uses provider overrides (not testing real integration)
**File:** `test/widget_test.dart`
**Issue:** All providers overridden with empty lists. Not a real integration test.

### 31. Missing tests for DatabaseHelper, TaskRepository, Services
**Issue:** No tests for the core data layer, notification scheduling, quiet hours logic, or background tasks.
