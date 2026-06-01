import 'dart:convert';
import 'dart:io';
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
    try {
      await Share.shareXFiles([XFile(file.path)], text: 'Daily Tracker Backup');
    } finally {
      // Clean up temp file after sharing
      if (await file.exists()) {
        await file.delete();
      }
    }
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
    try {
      await Share.shareXFiles([XFile(file.path)], text: 'Daily Tracker Analytics');
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<bool> importFromJson(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final version = data['version'] as int? ?? 1;

    if (version != 1 && version != 2) {
      throw UnsupportedError('Unsupported backup version: $version');
    }

    final tasksData = data['tasks'] as List<dynamic>? ?? [];
    final completionsData = data['completions'] as List<dynamic>? ?? [];
    final taskLogsData = data['taskLogs'] as List<dynamic>? ?? [];

    // Validate ALL data BEFORE touching the database to ensure atomicity
    final tasks = <TaskModel>[];
    for (final taskJson in tasksData) {
      final task = TaskModel.fromMap(taskJson as Map<String, dynamic>);
      if (task.id.isEmpty || task.title.isEmpty) {
        throw FormatException('Invalid task: empty id or title');
      }
      tasks.add(task);
    }

    final completions = <DailyCompletionModel>[];
    for (final completionJson in completionsData) {
      final completion = DailyCompletionModel.fromMap(completionJson as Map<String, dynamic>);
      if (completion.id.isEmpty) {
        throw FormatException('Invalid completion: empty id');
      }
      completions.add(completion);
    }

    final logs = <TaskLogModel>[];
    for (final logJson in taskLogsData) {
      final log = TaskLogModel.fromMap(logJson as Map<String, dynamic>);
      if (log.id.isEmpty || log.taskId.isEmpty) {
        throw FormatException('Invalid task log: empty id or taskId');
      }
      logs.add(log);
    }

    // Atomic import: wipe only after validation, then insert everything
    await _db.wipeAllData();

    for (final task in tasks) {
      await _db.insertTask(task);
    }
    for (final completion in completions) {
      await _db.upsertDailyCompletion(completion);
    }
    for (final log in logs) {
      await _db.insertTaskLog(log);
    }

    return true;
  }
}
