import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/task_provider.dart';

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  final List<_TaskTemplate> _templates = const [
    _TaskTemplate(
      name: 'Headman Habits',
      icon: Icons.military_tech,
      description: 'Goal: To be a 10/10 — Recreate a new you. A complete 90-day challenge to rebuild yourself.',
      dos: [
        _TemplateTask(title: 'Pray Daily (be thankful)', taskType: 'checklist'),
        _TemplateTask(title: 'Weigh yourself', taskType: 'numeric', unit: 'kg'),
        _TemplateTask(title: '1 hour everyday in nature/sun', taskType: 'checklist'),
        _TemplateTask(title: 'Workout everyday 1 hour minimum', taskType: 'checklist'),
        _TemplateTask(title: 'Interact with someone new everyday', taskType: 'text'),
        _TemplateTask(title: 'Progress photo everyday', taskType: 'photo'),
      ],
      donts: [
        _TemplateTask(title: 'No caffeine', taskType: 'checklist'),
        _TemplateTask(title: 'No Sugar/Processed food', taskType: 'checklist'),
        _TemplateTask(title: 'No smoking/vaping/drugs/weed/tobacco', taskType: 'checklist'),
        _TemplateTask(title: 'No porn/dirty websites', taskType: 'checklist'),
        _TemplateTask(title: 'No jerking off', taskType: 'checklist'),
        _TemplateTask(title: 'No Social media scrolling', taskType: 'checklist'),
      ],
    ),
    _TaskTemplate(
      name: 'Morning Routine',
      icon: Icons.wb_sunny,
      description: 'Start your day with energy and focus.',
      dos: [
        _TemplateTask(title: 'Drink a glass of water', taskType: 'checklist'),
        _TemplateTask(title: 'Stretch for 5 minutes', taskType: 'checklist'),
        _TemplateTask(title: 'Meditate for 10 minutes', taskType: 'checklist'),
        _TemplateTask(title: 'Plan your day', taskType: 'checklist'),
      ],
      donts: [],
    ),
    _TaskTemplate(
      name: 'Workout',
      icon: Icons.fitness_center,
      description: 'Build strength and endurance.',
      dos: [
        _TemplateTask(title: 'Warm up 5 min', taskType: 'checklist'),
        _TemplateTask(title: 'Main workout 30 min', taskType: 'checklist'),
        _TemplateTask(title: 'Cool down stretch', taskType: 'checklist'),
        _TemplateTask(title: 'Drink protein shake', taskType: 'checklist'),
      ],
      donts: [],
    ),
    _TaskTemplate(
      name: 'Evening Wind Down',
      icon: Icons.bedtime,
      description: 'Relax and prepare for quality sleep.',
      dos: [
        _TemplateTask(title: 'Review today\'s accomplishments', taskType: 'checklist'),
        _TemplateTask(title: 'Prepare for tomorrow', taskType: 'checklist'),
        _TemplateTask(title: 'Read for 20 minutes', taskType: 'checklist'),
      ],
      donts: [
        _TemplateTask(title: 'No screens 30 min before bed', taskType: 'checklist'),
      ],
    ),
    _TaskTemplate(
      name: 'Healthy Habits',
      icon: Icons.favorite,
      description: 'Nourish your body and mind.',
      dos: [
        _TemplateTask(title: 'Eat 3 healthy meals', taskType: 'checklist'),
        _TemplateTask(title: 'Drink 8 glasses of water', taskType: 'numeric', unit: 'glasses'),
        _TemplateTask(title: 'Take vitamins', taskType: 'checklist'),
        _TemplateTask(title: 'Walk 10,000 steps', taskType: 'numeric', unit: 'steps'),
      ],
      donts: [],
    ),
    _TaskTemplate(
      name: 'Productivity',
      icon: Icons.lightbulb,
      description: 'Maximize your output and focus.',
      dos: [
        _TemplateTask(title: 'Complete top 3 priorities', taskType: 'checklist'),
        _TemplateTask(title: 'Check emails (2 times only)', taskType: 'checklist'),
        _TemplateTask(title: 'Take a break every 90 min', taskType: 'checklist'),
        _TemplateTask(title: 'Update task list', taskType: 'checklist'),
      ],
      donts: [],
    ),
    _TaskTemplate(
      name: 'Self Care',
      icon: Icons.spa,
      description: 'Take time for yourself.',
      dos: [
        _TemplateTask(title: 'Skincare routine', taskType: 'checklist'),
        _TemplateTask(title: 'Journal for 10 minutes', taskType: 'text'),
        _TemplateTask(title: 'Call a loved one', taskType: 'checklist'),
        _TemplateTask(title: 'Practice gratitude', taskType: 'checklist'),
      ],
      donts: [],
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
                      '${template.dos.length + template.donts.length} tasks',
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
    final allTasks = [...template.dos, ...template.donts];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Apply "${template.name}"?'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (template.description != null) ...[
                  Text(
                    template.description!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text('This will add ${allTasks.length} tasks to your today list:'),
                const SizedBox(height: 12),
                if (template.dos.isNotEmpty) ...[
                  Text(
                    'DOs:',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...template.dos.map((task) => _buildTaskPreview(context, task, Icons.check_circle_outline)),
                  const SizedBox(height: 12),
                ],
                if (template.donts.isNotEmpty) ...[
                  Text(
                    'DON\'Ts:',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...template.donts.map((task) => _buildTaskPreview(context, task, Icons.block)),
                ],
              ],
            ),
          ),
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
      final createdIds = <String>[];
      for (final task in template.dos) {
        final created = await actions.createTask(
          title: task.title,
          description: task.unit,
          category: 'Do',
          taskType: task.taskType,
        );
        createdIds.add(created.id);
      }
      for (final task in template.donts) {
        final created = await actions.createTask(
          title: task.title,
          description: task.unit,
          category: 'Don\'t',
          taskType: task.taskType,
        );
        createdIds.add(created.id);
      }
      if (context.mounted) {
        context.go('/today');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${allTasks.length} tasks from ${template.name}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                for (final id in createdIds) {
                  await actions.deleteTask(id);
                }
              },
            ),
          ),
        );
      }
    }
  }

  Widget _buildTaskPreview(BuildContext context, _TemplateTask task, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(task.title)),
          if (task.taskType != 'checklist')
            Icon(
              task.taskType == 'numeric' ? Icons.numbers :
              task.taskType == 'text' ? Icons.notes :
              task.taskType == 'photo' ? Icons.camera_alt :
              Icons.help_outline,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

class _TemplateTask {
  final String title;
  final String taskType;
  final String? unit;

  const _TemplateTask({
    required this.title,
    this.taskType = 'checklist',
    this.unit,
  });
}

class _TaskTemplate {
  final String name;
  final IconData icon;
  final String? description;
  final List<_TemplateTask> dos;
  final List<_TemplateTask> donts;

  const _TaskTemplate({
    required this.name,
    required this.icon,
    this.description,
    required this.dos,
    required this.donts,
  });
}
