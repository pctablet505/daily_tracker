import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import '../../../core/services/dependency_injection.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/daily_completion_model.dart';
import '../../providers/task_provider.dart';
import '../../widgets/common/section_title.dart';
import '../../widgets/common/stat_card.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _streak = 0;
  int _bestStreak = 0;
  int _totalTasks = 0;
  int _completedTasks = 0;
  double _avgRate = 0.0;
  bool _isLoading = true;
  List<DailyStat> _weeklyStats = [];
  List<CategoryStat> _categoryStats = [];
  int _todayTotal = 0;
  int _todayCompleted = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final db = getIt<DatabaseHelper>();
    final streak = await db.getStreakCount();
    final bestStreak = await db.getBestStreakCount();
    final total = await db.getTotalTasksCount();
    final completed = await db.getCompletedTasksCount();
    final avg = await db.getAverageCompletionRate();
    final categoryStats = await db.getCategoryStats();

    // Get today's completion
    final todayCompletion = await db.getDailyCompletion(DateTime.now());
    final todayTotal = todayCompletion?.totalTasks ?? 0;
    final todayCompleted = todayCompletion?.completedTasks ?? 0;

    // Get last 7 days of completion data
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 6));
    final completions = await db.getDailyCompletionsRange(weekStart, now);

    final stats = <DailyStat>[];
    for (int i = 6; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final completion = completions.firstWhere(
        (c) => c.date.year == date.year && c.date.month == date.month && c.date.day == date.day,
        orElse: () => DailyCompletionModel(
          id: '',
          date: date,
          totalTasks: 0,
          completedTasks: 0,
          completionRate: 0.0,
        ),
      );
      stats.add(DailyStat(
        date: completion.date,
        completed: completion.completedTasks,
        total: completion.totalTasks,
      ));
    }

    if (mounted) {
      setState(() {
        _streak = streak;
        _bestStreak = bestStreak;
        _totalTasks = total;
        _completedTasks = completed;
        _avgRate = avg;
        _weeklyStats = stats;
        _categoryStats = categoryStats;
        _todayTotal = todayTotal;
        _todayCompleted = todayCompleted;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadStats();
                ref.invalidate(allTasksProvider);
                ref.invalidate(allTaskLogsProvider);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle('Overview'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            icon: Icons.local_fire_department,
                            iconColor: Colors.orange,
                            value: '$_streak',
                            label: 'Day Streak',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            icon: Icons.emoji_events,
                            iconColor: Colors.amber,
                            value: '$_bestStreak',
                            label: 'Best Streak',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            icon: Icons.trending_up,
                            iconColor: colorScheme.tertiary,
                            value: '${(_avgRate * 100).toInt()}%',
                            label: 'Avg Rate',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            icon: Icons.check_circle,
                            iconColor: colorScheme.primary,
                            value: '$_completedTasks',
                            label: 'Total Completed',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            icon: Icons.task_alt,
                            iconColor: colorScheme.secondary,
                            value: '$_totalTasks',
                            label: 'Active Tasks',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SectionTitle('Weekly Progress'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: _buildWeeklyChart(colorScheme),
                    ),
                    const SizedBox(height: 24),
                    const SectionTitle('Today\'s Completion'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: _buildPieChart(colorScheme),
                    ),
                    const SizedBox(height: 24),
                    const SectionTitle('Category Breakdown'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: _categoryStats.isEmpty ? 60 : _categoryStats.length * 56.0,
                      child: _categoryStats.isEmpty
                          ? Center(
                              child: Text(
                                'No category data yet',
                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                              ),
                            )
                          : _buildCategoryChart(colorScheme),
                    ),
                    const SizedBox(height: 24),
                    const SectionTitle('Activity History Log'),
                    const SizedBox(height: 12),
                    _buildActivityHistoryFeed(context),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildActivityHistoryFeed(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final tasksAsync = ref.watch(allTasksProvider);
    final logsAsync = ref.watch(allTaskLogsProvider);

    return tasksAsync.when(
      data: (tasks) {
        final taskMap = {for (var t in tasks) t.id: t};

        return logsAsync.when(
          data: (logs) {
            // Filter logs to only show active log points
            final activeLogs = logs.where((l) {
              final taskExists = taskMap.containsKey(l.taskId);
              final hasData = l.isCompleted ||
                  (l.comment != null && l.comment!.isNotEmpty) ||
                  (l.mediaPath != null && l.mediaPath!.isNotEmpty);
              return taskExists && hasData;
            }).toList();

            if (activeLogs.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.history_toggle_off,
                          size: 48,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No tracking history logged yet',
                          style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeLogs.length,
              itemBuilder: (context, index) {
                final log = activeLogs[index];
                final task = taskMap[log.taskId];
                if (task == null) {
                  // Task was deleted but log remains — skip orphaned log
                  return const SizedBox.shrink();
                }
                final taskTitle = task.title;
                final category = task.category ?? 'Other';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              log.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: log.isCompleted ? colorScheme.primary : colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                taskTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                category,
                                style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          log.date,
                          style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                        if (log.comment != null && log.comment!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            log.comment!,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                        if (log.mediaPath != null && log.mediaPath!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(log.mediaPath!),
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error loading logs: $err')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error loading tasks: $err')),
    );
  }

  Widget _buildWeeklyChart(ColorScheme scheme) {
    if (_weeklyStats.every((s) => s.total == 0)) {
      return Center(
        child: Text(
          'No data for this week',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: _weeklyStats.map((s) => s.total).reduce((a, b) => a > b ? a : b).toDouble() + 1,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < _weeklyStats.length) {
                  final dayName = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][_weeklyStats[index].date.weekday - 1];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      dayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(_weeklyStats.length, (index) {
          final stat = _weeklyStats[index];
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: stat.total.toDouble(),
                color: scheme.primary,
                width: 16,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildPieChart(ColorScheme scheme) {
    final remaining = _todayTotal - _todayCompleted;
    final completed = _todayCompleted;

    if (_todayTotal == 0) {
      return Center(
        child: Text(
          'No tasks for today yet',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: [
          PieChartSectionData(
            color: scheme.primary,
            value: completed.toDouble(),
            title: completed > 0 ? '$completed' : '',
            radius: 60,
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            color: scheme.surfaceContainerHighest,
            value: remaining.toDouble(),
            title: remaining > 0 ? '$remaining' : '',
            radius: 60,
            titleStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChart(ColorScheme scheme) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _categoryStats.length,
      itemBuilder: (context, index) {
        final stat = _categoryStats[index];
        final rate = stat.completionRate;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    stat.category,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    '${stat.completed}/${stat.total} (${(rate * 100).toInt()}%)',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: rate,
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DailyStat {
  final DateTime date;
  final int completed;
  final int total;

  DailyStat({required this.date, required this.completed, required this.total});
}
