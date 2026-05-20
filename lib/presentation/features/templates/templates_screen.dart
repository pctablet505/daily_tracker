import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/id_generator.dart';
import '../../providers/task_provider.dart';

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  final List<_TaskTemplate> _templates = const [
    _TaskTemplate(
      name: 'Morning Routine',
      icon: Icons.wb_sunny,
      tasks: [
        'Drink a glass of water',
        'Stretch for 5 minutes',
        'Meditate for 10 minutes',
        'Plan your day',
      ],
    ),
    _TaskTemplate(
      name: 'Workout',
      icon: Icons.fitness_center,
      tasks: [
        'Warm up 5 min',
        'Main workout 30 min',
        'Cool down stretch',
        'Drink protein shake',
      ],
    ),
    _TaskTemplate(
      name: 'Evening Wind Down',
      icon: Icons.bedtime,
      tasks: [
        'Review today\'s accomplishments',
        'Prepare for tomorrow',
        'Read for 20 minutes',
        'No screens 30 min before bed',
      ],
    ),
    _TaskTemplate(
      name: 'Healthy Habits',
      icon: Icons.favorite,
      tasks: [
        'Eat 3 healthy meals',
        'Drink 8 glasses of water',
        'Take vitamins',
        'Walk 10,000 steps',
      ],
    ),
    _TaskTemplate(
      name: 'Productivity',
      icon: Icons.lightbulb,
      tasks: [
        'Complete top 3 priorities',
        'Check emails (2 times only)',
        'Take a break every 90 min',
        'Update task list',
      ],
    ),
    _TaskTemplate(
      name: 'Self Care',
      icon: Icons.spa,
      tasks: [
        'Skincare routine',
        'Journal for 10 minutes',
        'Call a loved one',
        'Practice gratitude',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Templates')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _templates.length,
        itemBuilder: (context, index) {
          final template = _templates[index];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _applyTemplate(context, ref, template),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(template.icon, size: 40, color: colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      template.name,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${template.tasks.length} tasks',
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _applyTemplate(BuildContext context, WidgetRef ref, _TaskTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Apply "${template.name}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will add ${template.tasks.length} tasks to your today list:'),
            const SizedBox(height: 12),
            ...template.tasks.map((task) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(task)),
                    ],
                  ),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final actions = ref.read(taskActionsProvider);
      for (final taskTitle in template.tasks) {
        await actions.createTask(title: taskTitle);
      }
      if (context.mounted) {
        context.go('/today');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${template.tasks.length} tasks from ${template.name}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                // In a real app, we'd track these IDs and delete them
              },
            ),
          ),
        );
      }
    }
  }
}

class _TaskTemplate {
  final String name;
  final IconData icon;
  final List<String> tasks;

  const _TaskTemplate({
    required this.name,
    required this.icon,
    required this.tasks,
  });
}
