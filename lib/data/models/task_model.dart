import 'package:equatable/equatable.dart';
import '../../core/utils/safe_parse.dart';

class _NullableSentinel {
  const _NullableSentinel();
}

const _nullableSentinel = _NullableSentinel();

class TaskModel extends Equatable {
  final String id;
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? reminderTime;
  final bool isCompleted;
  final bool isRecurring;
  final String? recurrenceRule;
  final String? category;
  final String? taskType;
  final int priority;
  final DateTime? completedAt;
  final bool isDeleted;
  final int version;
  final String syncStatus;

  const TaskModel({
    required this.id,
    required this.title,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.reminderTime,
    this.isCompleted = false,
    this.isRecurring = false,
    this.recurrenceRule,
    this.category,
    this.taskType = 'checklist',
    this.priority = 0,
    this.completedAt,
    this.isDeleted = false,
    this.version = 1,
    this.syncStatus = 'pending',
  });

  TaskModel copyWith({
    String? id,
    String? title,
    Object? description = _nullableSentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? reminderTime = _nullableSentinel,
    bool? isCompleted,
    bool? isRecurring,
    Object? recurrenceRule = _nullableSentinel,
    Object? category = _nullableSentinel,
    Object? taskType = _nullableSentinel,
    int? priority,
    Object? completedAt = _nullableSentinel,
    bool? isDeleted,
    int? version,
    String? syncStatus,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description == _nullableSentinel
          ? this.description
          : description as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderTime: reminderTime == _nullableSentinel
          ? this.reminderTime
          : reminderTime as DateTime?,
      isCompleted: isCompleted ?? this.isCompleted,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceRule: recurrenceRule == _nullableSentinel
          ? this.recurrenceRule
          : recurrenceRule as String?,
      category:
          category == _nullableSentinel ? this.category : category as String?,
      taskType:
          taskType == _nullableSentinel ? this.taskType : taskType as String?,
      priority: priority ?? this.priority,
      completedAt: completedAt == _nullableSentinel
          ? this.completedAt
          : completedAt as DateTime?,
      isDeleted: isDeleted ?? this.isDeleted,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'reminderTime': reminderTime?.toIso8601String(),
      'isCompleted': isCompleted ? 1 : 0,
      'isRecurring': isRecurring ? 1 : 0,
      'recurrenceRule': recurrenceRule,
      'category': category,
      'taskType': taskType,
      'priority': priority,
      'completedAt': completedAt?.toIso8601String(),
      'isDeleted': isDeleted ? 1 : 0,
      'version': version,
      'syncStatus': syncStatus,
    };
  }

  factory TaskModel.fromMap(Map<String, dynamic> map) {
    return TaskModel(
      id: SafeParse.string(map['id'], defaultValue: ''),
      title: SafeParse.string(map['title'], defaultValue: ''),
      description: SafeParse.stringNullable(map['description']),
      createdAt: SafeParse.dateTimeOrNow(map['createdAt']),
      updatedAt: SafeParse.dateTimeOrNow(map['updatedAt']),
      reminderTime: SafeParse.dateTime(map['reminderTime']),
      isCompleted: SafeParse.boolean(map['isCompleted']),
      isRecurring: SafeParse.boolean(map['isRecurring']),
      recurrenceRule: SafeParse.stringNullable(map['recurrenceRule']),
      category: SafeParse.stringNullable(map['category']),
      taskType: SafeParse.stringNullable(map['taskType']) ?? 'checklist',
      priority: SafeParse.integer(map['priority']),
      completedAt: SafeParse.dateTime(map['completedAt']),
      isDeleted: SafeParse.boolean(map['isDeleted']),
      version: SafeParse.integer(map['version'], defaultValue: 1),
      syncStatus: SafeParse.stringNullable(map['syncStatus']) ?? 'pending',
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        createdAt,
        updatedAt,
        reminderTime,
        isCompleted,
        isRecurring,
        recurrenceRule,
        category,
        taskType,
        priority,
        completedAt,
        isDeleted,
        version,
        syncStatus,
      ];
}
