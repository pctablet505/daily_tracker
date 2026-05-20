import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/services/dependency_injection.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/daily_completion_model.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _streak = 0;
  int _totalTasks = 0;
  int _completedTasks = 0;
  double _avgRate = 0.0;
  bool _isLoading = true;
  List<DailyStat> _weeklyStats = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final db = getIt<DatabaseHelper>();
    final streak = await db.getStreakCount();
    final total = await db.getTotalTasksCount();
    final completed = await db.getCompletedTasksCount();
    final avg = await db.getAverageCompletionRate();

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
        _totalTasks = total;
        _completedTasks = completed;
        _avgRate = avg;
        _weeklyStats = stats;
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
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Overview'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.local_fire_department,
                            iconColor: Colors.orange,
                            value: '$_streak',
                            label: 'Day Streak',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.check_circle,
                            iconColor: colorScheme.primary,
                            value: '$_completedTasks',
                            label: 'Completed',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.trending_up,
                            iconColor: colorScheme.tertiary,
                            value: '${(_avgRate * 100).toInt()}%',
                            label: 'Avg Rate',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Weekly Progress'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: _buildWeeklyChart(colorScheme),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Completion Distribution'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: _buildPieChart(colorScheme),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
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
    final remaining = _totalTasks - _completedTasks;
    final completed = _completedTasks;

    if (_totalTasks == 0) {
      return Center(
        child: Text(
          'No tasks yet',
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
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class DailyStat {
  final DateTime date;
  final int completed;
  final int total;

  DailyStat({required this.date, required this.completed, required this.total});
}
