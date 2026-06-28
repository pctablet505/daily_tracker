class BadgeModel {
  final String id;
  final String type;
  final int threshold;
  final String title;
  final DateTime? earnedAt;

  const BadgeModel({
    required this.id,
    required this.type,
    required this.threshold,
    required this.title,
    this.earnedAt,
  });

  bool get isEarned => earnedAt != null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'threshold': threshold,
        'title': title,
        'earnedAt': earnedAt?.toIso8601String(),
      };

  factory BadgeModel.fromMap(Map<String, dynamic> m) => BadgeModel(
        id: m['id'] as String,
        type: m['type'] as String,
        threshold: m['threshold'] as int,
        title: m['title'] as String,
        earnedAt: m['earnedAt'] != null
            ? DateTime.parse(m['earnedAt'] as String)
            : null,
      );
}
