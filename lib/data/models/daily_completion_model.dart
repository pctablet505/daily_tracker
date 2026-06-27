import 'package:equatable/equatable.dart';
import '../../core/utils/safe_parse.dart';

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
      'createdAt':
          createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  factory DailyCompletionModel.fromMap(Map<String, dynamic> map) {
    return DailyCompletionModel(
      id: SafeParse.string(map['id'], defaultValue: ''),
      date: SafeParse.dateTimeOrNow(map['date']),
      totalTasks: SafeParse.integer(map['totalTasks']),
      completedTasks: SafeParse.integer(map['completedTasks']),
      completionRate: SafeParse.float(map['completionRate']),
      createdAt: SafeParse.dateTime(map['createdAt']),
    );
  }

  @override
  List<Object?> get props =>
      [id, date, totalTasks, completedTasks, completionRate];
}
