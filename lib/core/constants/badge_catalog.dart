class BadgeDefinition {
  final String id;
  final String type; // streak|total|quality
  final int threshold;
  final String title;
  final String description;
  final String emoji;

  const BadgeDefinition({
    required this.id,
    required this.type,
    required this.threshold,
    required this.title,
    required this.description,
    required this.emoji,
  });
}

class BadgeCatalog {
  static const List<BadgeDefinition> all = [
    BadgeDefinition(id: 'streak_3', type: 'streak', threshold: 3, title: 'Getting Started', description: '3-day streak', emoji: '🌱'),
    BadgeDefinition(id: 'streak_7', type: 'streak', threshold: 7, title: 'Week Warrior', description: '7-day streak', emoji: '🔥'),
    BadgeDefinition(id: 'streak_14', type: 'streak', threshold: 14, title: 'Fortnight', description: '14-day streak', emoji: '⚡'),
    BadgeDefinition(id: 'streak_30', type: 'streak', threshold: 30, title: 'Monthly Master', description: '30-day streak', emoji: '🏆'),
    BadgeDefinition(id: 'streak_60', type: 'streak', threshold: 60, title: 'Iron Will', description: '60-day streak', emoji: '💪'),
    BadgeDefinition(id: 'streak_100', type: 'streak', threshold: 100, title: 'Century', description: '100-day streak', emoji: '💯'),
    BadgeDefinition(id: 'streak_365', type: 'streak', threshold: 365, title: 'Year of You', description: '365-day streak', emoji: '🌟'),
    BadgeDefinition(id: 'total_50', type: 'total', threshold: 50, title: 'Half Century', description: '50 tasks completed', emoji: '🎯'),
    BadgeDefinition(id: 'total_250', type: 'total', threshold: 250, title: 'Quarter K', description: '250 tasks completed', emoji: '🚀'),
    BadgeDefinition(id: 'total_1000', type: 'total', threshold: 1000, title: 'Thousand Strong', description: '1000 tasks completed', emoji: '👑'),
    BadgeDefinition(id: 'quality_perfect_day', type: 'quality', threshold: 1, title: 'Perfect Day', description: '100% completion in a day', emoji: '✨'),
    BadgeDefinition(id: 'quality_perfect_week', type: 'quality', threshold: 7, title: 'Perfect Week', description: '7 consecutive 100% days', emoji: '🎖️'),
  ];

  static BadgeDefinition? findById(String id) {
    try {
      return all.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }
}
