import 'package:equatable/equatable.dart';

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
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? reminderTime,
    bool? isCompleted,
    bool? isRecurring,
    String? recurrenceRule,
    String? category,
    String? taskType,
    int? priority,
    DateTime? completedAt,
    bool? isDeleted,
    int? version,
    String? syncStatus,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderTime: reminderTime ?? this.reminderTime,
      isCompleted: isCompleted ?? this.isCompleted,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      category: category ?? this.category,
      taskType: taskType ?? this.taskType,
      priority: priority ?? this.priority,
      completedAt: completedAt ?? this.completedAt,
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
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      reminderTime: map['reminderTime'] != null
          ? DateTime.parse(map['reminderTime'] as String)
          : null,
      isCompleted: (map['isCompleted'] as int) == 1,
      isRecurring: (map['isRecurring'] as int) == 1,
      recurrenceRule: map['recurrenceRule'] as String?,
      category: map['category'] as String?,
      taskType: map['taskType'] as String? ?? 'checklist',
      priority: map['priority'] as int? ?? 0,
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'] as String)
          : null,
      isDeleted: (map['isDeleted'] as int? ?? 0) == 1,
      version: map['version'] as int? ?? 1,
      syncStatus: map['syncStatus'] as String? ?? 'synced',
    );
  }

  @override
  List<Object?> get props => [
        id, title, description, createdAt, updatedAt, reminderTime,
        isCompleted, isRecurring, recurrenceRule, category, taskType, priority,
        completedAt, isDeleted, version, syncStatus,
      ];
}
