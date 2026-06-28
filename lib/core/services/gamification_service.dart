import '../constants/badge_catalog.dart';
import '../../data/models/badge_model.dart';
import '../utils/app_logger.dart';

typedef BadgeQuery = Future<List<BadgeModel>> Function();
typedef BadgeEarner = Future<void> Function(BadgeModel);
typedef IntQuery = Future<int> Function();

class GamificationService {
  final IntQuery getStreak;
  final IntQuery getBestStreak;
  final IntQuery getTotalCompleted;
  final BadgeQuery getBadges;
  final BadgeEarner earnBadge;

  GamificationService({
    required this.getStreak,
    required this.getBestStreak,
    required this.getTotalCompleted,
    required this.getBadges,
    required this.earnBadge,
  });

  Future<List<BadgeModel>> evaluateBadges() async {
    final newlyEarned = <BadgeModel>[];
    try {
      final streak = await getStreak();
      final bestStreak = await getBestStreak();
      final totalCompleted = await getTotalCompleted();
      final existing = await getBadges();
      final earnedIds = existing.where((b) => b.isEarned).map((b) => b.id).toSet();

      for (final def in BadgeCatalog.all) {
        if (earnedIds.contains(def.id)) continue;
        bool shouldEarn = false;
        if (def.type == 'streak') {
          shouldEarn = streak >= def.threshold || bestStreak >= def.threshold;
        } else if (def.type == 'total') {
          shouldEarn = totalCompleted >= def.threshold;
        }
        if (!shouldEarn) continue;
        final badge = BadgeModel(
          id: def.id,
          type: def.type,
          threshold: def.threshold,
          title: def.title,
          earnedAt: DateTime.now(),
        );
        await earnBadge(badge);
        newlyEarned.add(badge);
      }
    } catch (e) {
      AppLogger.e('GamificationService.evaluateBadges: $e');
    }
    return newlyEarned;
  }
}
