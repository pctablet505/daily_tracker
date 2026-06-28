import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/extensions/date_extensions.dart';
import '../../../data/models/task_model.dart';
import '../../providers/task_provider.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late DateTime _focusedMonth;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay.dateOnly;
    _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  }

  Future<void> _onRefresh() async {
    ref.invalidate(
        tasksForDateProvider(_selectedDay ?? DateTime.now().dateOnly));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final monthMap = ref.watch(monthCompletionsProvider(_focusedMonth)).value ?? {};
    final tasksAsync = ref
        .watch(tasksForDateProvider(_selectedDay ?? DateTime.now().dateOnly));

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: Column(
        children: [
          TableCalendar<TaskModel>(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay.dateOnly;
                _focusedDay = focusedDay;
              });
            },
            onFormatChanged: (format) {
              setState(() => _calendarFormat = format);
            },
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
                _focusedMonth = DateTime(focusedDay.year, focusedDay.month, 1);
              });
            },
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(color: colorScheme.onPrimaryContainer),
              selectedDecoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: TextStyle(color: colorScheme.onPrimary),
              markerDecoration: BoxDecoration(
                color: colorScheme.tertiary,
                shape: BoxShape.circle,
              ),
              markersMaxCount: 3,
            ),
            headerStyle: HeaderStyle(
              formatButtonDecoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              formatButtonTextStyle:
                  TextStyle(color: colorScheme.onPrimaryContainer),
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, _) {
                final key = DateTime(day.year, day.month, day.day);
                final c = monthMap[key];
                if (c == null || c.totalTasks == 0) return null;
                final pct = c.completionRate;
                final color = pct >= 1.0
                    ? Colors.green
                    : pct > 0
                        ? Colors.amber
                        : Theme.of(context).colorScheme.outlineVariant;
                return Positioned(
                  bottom: 4,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: Colors.green, label: 'Done'),
                const SizedBox(width: 16),
                _LegendDot(color: Colors.amber, label: 'Partial'),
                const SizedBox(width: 16),
                _LegendDot(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  label: 'Missed',
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: tasksAsync.when(
                data: (tasks) {
                  if (tasks.isEmpty) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                minHeight: constraints.maxHeight),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.event_available_outlined,
                                    size: 48,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No tasks for ${_selectedDay?.formattedDate ?? 'today'}',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }
                  return ListView.builder(
                    key: const Key('calendar_tasks_list'),
                    padding: const EdgeInsets.all(16),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Slidable(
                          key: ValueKey(task.id),
                          endActionPane: ActionPane(
                            motion: const ScrollMotion(),
                            children: [
                              SlidableAction(
                                onPressed: (_) =>
                                    context.push('/task/${task.id}'),
                                backgroundColor: colorScheme.primary,
                                foregroundColor: Colors.white,
                                icon: Icons.edit,
                                label: 'Edit',
                                borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(12)),
                              ),
                              SlidableAction(
                                onPressed: (_) async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Task?'),
                                      content: const Text(
                                          'This task will be moved to trash. You can restore it later.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                Theme.of(ctx).colorScheme.error,
                                          ),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && context.mounted) {
                                    final actions =
                                        ref.read(taskActionsProvider);
                                    await actions.deleteTask(task.id);
                                  }
                                },
                                backgroundColor: colorScheme.error,
                                foregroundColor: Colors.white,
                                icon: Icons.delete,
                                label: 'Delete',
                                borderRadius: const BorderRadius.horizontal(
                                    right: Radius.circular(12)),
                              ),
                            ],
                          ),
                          child: ListTile(
                            leading: Checkbox(
                              value: task.isCompleted,
                              onChanged: (value) async {
                                HapticFeedback.mediumImpact();
                                final actions = ref.read(taskActionsProvider);
                                try {
                                  await actions.toggleCompletion(task);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Could not update task: $e')),
                                    );
                                  }
                                }
                              },
                            ),
                            title: Text(
                              task.title,
                              style: TextStyle(
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: task.isCompleted
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.onSurface,
                              ),
                            ),
                            subtitle: task.reminderTime != null
                                ? Text(task.reminderTime!.formattedTime)
                                : null,
                            trailing: _priorityDot(task.priority, colorScheme),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Error: $error')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priorityDot(int priority, ColorScheme scheme) {
    Color color;
    switch (priority) {
      case 2:
        color = scheme.error;
        break;
      case 1:
        color = scheme.tertiary;
        break;
      default:
        color = scheme.surfaceContainerHighest;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
      ],
    );
  }
}
