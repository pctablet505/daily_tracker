import 'package:equatable/equatable.dart';

class SyncQueueModel extends Equatable {
  final String id;
  final String entityType;
  final String entityId;
  final String operation;
  final String payload;
  final DateTime createdAt;
  final int retryCount;
  final bool isProcessed;

  const SyncQueueModel({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.isProcessed = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entityType': entityType,
      'entityId': entityId,
      'operation': operation,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
      'isProcessed': isProcessed ? 1 : 0,
    };
  }

  factory SyncQueueModel.fromMap(Map<String, dynamic> map) {
    return SyncQueueModel(
      id: map['id'] as String,
      entityType: map['entityType'] as String,
      entityId: map['entityId'] as String,
      operation: map['operation'] as String,
      payload: map['payload'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      retryCount: map['retryCount'] as int? ?? 0,
      isProcessed: (map['isProcessed'] as int? ?? 0) == 1,
    );
  }

  @override
  List<Object?> get props => [id, entityType, entityId, operation, payload, createdAt, retryCount, isProcessed];
}
