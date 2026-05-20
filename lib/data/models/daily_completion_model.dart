import 'package:equatable/equatable.dart';

class DailyCompletionModel extends Equatable {
  final String id;
  final DateTime date;
  final int totalTasks;
  final int completedTasks;
  final double completionRate;
  final DateTime? createdAt;

  const DailyCompletionModel({
    required this.id,
    required this.date,
    required this.totalTasks,
    required this.completedTasks,
    required this.completionRate,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'totalTasks': totalTasks,
      'completedTasks': completedTasks,
      'completionRate': completionRate,
      'createdAt': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  factory DailyCompletionModel.fromMap(Map<String, dynamic> map) {
    return DailyCompletionModel(
      id: map['id'] as String,
      date: DateTime.parse(map['date'] as String),
      totalTasks: map['totalTasks'] as int,
      completedTasks: map['completedTasks'] as int,
      completionRate: map['completionRate'] as double,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, date, totalTasks, completedTasks, completionRate];
}
