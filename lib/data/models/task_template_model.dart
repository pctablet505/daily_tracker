import 'dart:convert';

class TemplateTaskConfig {
  final String title;
  final String? description;
  final String category;
  final String taskType;
  final int priority;
  final bool isRecurring;

  const TemplateTaskConfig({
    required this.title,
    this.description,
    required this.category,
    this.taskType = 'checklist',
    this.priority = 0,
    this.isRecurring = true,
  });

  Map<String, dynamic> toMap() => {
        'title': title,
        'description': description,
        'category': category,
        'taskType': taskType,
        'priority': priority,
        'isRecurring': isRecurring ? 1 : 0,
      };

  factory TemplateTaskConfig.fromMap(Map<String, dynamic> m) =>
      TemplateTaskConfig(
        title: m['title'] as String,
        description: m['description'] as String?,
        category: m['category'] as String,
        taskType: (m['taskType'] as String?) ?? 'checklist',
        priority: (m['priority'] as int?) ?? 0,
        isRecurring: ((m['isRecurring'] as int?) ?? 1) == 1,
      );
}

class TaskTemplateModel {
  final String id;
  final String name;
  final String? description;
  final String? icon;
  final bool isBuiltIn;
  final List<TemplateTaskConfig> tasks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TaskTemplateModel({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    this.isBuiltIn = false,
    required this.tasks,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'icon': icon,
        'isBuiltIn': isBuiltIn ? 1 : 0,
        'tasksJson': jsonEncode(tasks.map((t) => t.toMap()).toList()),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TaskTemplateModel.fromMap(Map<String, dynamic> m) => TaskTemplateModel(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        icon: m['icon'] as String?,
        isBuiltIn: ((m['isBuiltIn'] as int?) ?? 0) == 1,
        tasks: (jsonDecode(m['tasksJson'] as String) as List)
            .map((e) => TemplateTaskConfig.fromMap(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );
}
