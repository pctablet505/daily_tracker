import 'package:equatable/equatable.dart';

class TaskLogModel extends Equatable {
  final String id;
  final String taskId;
  final String date; // Format: YYYY-MM-DD
  final bool isCompleted;
  final DateTime? completedAt;
  final String? comment;
  final String? mediaPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;

  const TaskLogModel({
    required this.id,
    required this.taskId,
    required this.date,
    this.isCompleted = false,
    this.completedAt,
    this.comment,
    this.mediaPath,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
  });

  TaskLogModel copyWith({
    String? id,
    String? taskId,
    String? date,
    bool? isCompleted,
    DateTime? completedAt,
    String? comment,
    String? mediaPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return TaskLogModel(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      date: date ?? this.date,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      comment: comment ?? this.comment,
      mediaPath: mediaPath ?? this.mediaPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'taskId': taskId,
      'date': date,
      'isCompleted': isCompleted ? 1 : 0,
      'completedAt': completedAt?.toIso8601String(),
      'comment': comment,
      'mediaPath': mediaPath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus,
    };
  }

  factory TaskLogModel.fromMap(Map<String, dynamic> map) {
    return TaskLogModel(
      id: map['id'] as String,
      taskId: map['taskId'] as String,
      date: map['date'] as String,
      isCompleted: (map['isCompleted'] as int) == 1,
      completedAt: map['completedAt'] != null ? DateTime.parse(map['completedAt'] as String) : null,
      comment: map['comment'] as String?,
      mediaPath: map['mediaPath'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      syncStatus: map['syncStatus'] as String? ?? 'pending',
    );
  }

  @override
  List<Object?> get props => [id, taskId, date, isCompleted, completedAt, comment, mediaPath, createdAt, updatedAt, syncStatus];
}
