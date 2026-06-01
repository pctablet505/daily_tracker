import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/task_model.dart';
import '../../data/models/daily_completion_model.dart';
import '../../data/models/task_log_model.dart';

class ExportService {
  final DatabaseHelper _db;

  ExportService(this._db);

  Future<String> exportToJson() async {
    final tasks = await _db.getAllActiveTasks();
    final completions = await _db.getDailyCompletionsRange(
      DateTime.now().subtract(const Duration(days: 365)),
      DateTime.now(),
    );
    final taskLogs = await _db.getAllTaskLogs();

    final exportData = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'tasks': tasks.map((t) => t.toMap()).toList(),
      'completions': completions.map((c) => c.toMap()).toList(),
      'taskLogs': taskLogs.map((l) => l.toMap()).toList(),
    };

    return jsonEncode(exportData);
  }

  Future<void> shareJsonExport() async {
    final jsonString = await exportToJson();
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/daily_tracker_backup.json');
    await file.writeAsString(jsonString);
    await Share.shareXFiles([XFile(file.path)], text: 'Daily Tracker Backup');
  }

  Future<String> exportToCsv() async {
    final completions = await _db.getDailyCompletionsRange(
      DateTime.now().subtract(const Duration(days: 365)),
      DateTime.now(),
    );

    final buffer = StringBuffer();
    buffer.writeln('Date,Total Tasks,Completed Tasks,Completion Rate %');

    for (final completion in completions) {
      final dateStr = completion.date.toIso8601String().split('T').first;
      buffer.writeln(
        '$dateStr,${completion.totalTasks},${completion.completedTasks},${(completion.completionRate * 100).toStringAsFixed(1)}',
      );
    }

    return buffer.toString();
  }

  Future<void> shareCsvExport() async {
    final csvString = await exportToCsv();
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/daily_tracker_analytics.csv');
    await file.writeAsString(csvString);
    await Share.shareXFiles([XFile(file.path)], text: 'Daily Tracker Analytics');
  }

  Future<bool> importFromJson(String jsonString) async {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final version = data['version'] as int? ?? 1;

      if (version != 1 && version != 2) {
        throw UnsupportedError('Unsupported backup version: $version');
      }

      final tasksData = data['tasks'] as List<dynamic>? ?? [];
      final completionsData = data['completions'] as List<dynamic>? ?? [];
      final taskLogsData = data['taskLogs'] as List<dynamic>? ?? [];

      for (final taskJson in tasksData) {
        final task = TaskModel.fromMap(taskJson as Map<String, dynamic>);
        await _db.insertTask(task);
      }

      for (final completionJson in completionsData) {
        final completion = DailyCompletionModel.fromMap(completionJson as Map<String, dynamic>);
        await _db.upsertDailyCompletion(completion);
      }

      for (final logJson in taskLogsData) {
        final log = TaskLogModel.fromMap(logJson as Map<String, dynamic>);
        await _db.insertTaskLog(log);
      }

      return true;
    } catch (e) {
      debugPrint('Import failed: $e');
      return false;
    }
  }
}
