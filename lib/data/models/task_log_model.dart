import 'package:equatable/equatable.dart';
import '../../core/utils/safe_parse.dart';

class _NullableSentinel {
  const _NullableSentinel();
}

const _nullableSentinel = _NullableSentinel();

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
    Object? completedAt = _nullableSentinel,
    Object? comment = _nullableSentinel,
    Object? mediaPath = _nullableSentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return TaskLogModel(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      date: date ?? this.date,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt == _nullableSentinel
          ? this.completedAt
          : completedAt as DateTime?,
      comment: comment == _nullableSentinel ? this.comment : comment as String?,
      mediaPath: mediaPath == _nullableSentinel
          ? this.mediaPath
          : mediaPath as String?,
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
      id: SafeParse.string(map['id'], defaultValue: ''),
      taskId: SafeParse.string(map['taskId'], defaultValue: ''),
      date: SafeParse.string(map['date'], defaultValue: ''),
      isCompleted: SafeParse.boolean(map['isCompleted']),
      completedAt: SafeParse.dateTime(map['completedAt']),
      comment: SafeParse.stringNullable(map['comment']),
      mediaPath: SafeParse.stringNullable(map['mediaPath']),
      createdAt: SafeParse.dateTimeOrNow(map['createdAt']),
      updatedAt: SafeParse.dateTimeOrNow(map['updatedAt']),
      syncStatus: SafeParse.stringNullable(map['syncStatus']) ?? 'pending',
    );
  }

  @override
  List<Object?> get props => [
        id,
        taskId,
        date,
        isCompleted,
        completedAt,
        comment,
        mediaPath,
        createdAt,
        updatedAt,
        syncStatus
      ];
}
