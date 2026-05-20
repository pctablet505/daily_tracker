import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/extensions/date_extensions.dart';
import '../../../core/utils/id_generator.dart';
import '../../../data/models/task_model.dart';
import '../../providers/task_provider.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  final String taskId;
  final bool isNew;

  const TaskDetailScreen({
    super.key,
    required this.taskId,
    this.isNew = false,
  });

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _reminderTime;
  bool _isRecurring = false;
  String? _recurrenceRule;
  int _priority = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isNew) {
      _loadTask();
    }
  }

  Future<void> _loadTask() async {
    final repository = ref.read(taskRepositoryProvider);
    final task = await repository.getTask(widget.taskId);
    if (task != null && mounted) {
      setState(() {
        _titleController.text = task.title;
        _descriptionController.text = task.description ?? '';
        _reminderTime = task.reminderTime;
        _isRecurring = task.isRecurring;
        _recurrenceRule = task.recurrenceRule;
        _priority = task.priority;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New Task' : 'Edit Task'),
        actions: [
          if (!widget.isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Task Title',
                hintText: 'What do you need to do?',
                prefixIcon: Icon(Icons.title),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 1,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Add more details...',
                prefixIcon: Icon(Icons.notes),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              minLines: 2,
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Reminder'),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.access_time, color: colorScheme.primary),
                    title: Text(_reminderTime != null
                        ? _reminderTime!.formattedTime
                        : 'No reminder set'),
                    subtitle: _reminderTime != null
                        ? Text(_reminderTime!.formattedDate)
                        : null,
                    trailing: _reminderTime != null
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _reminderTime = null),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _pickReminderTime,
                  ),
                  if (_reminderTime != null) ...[
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(
                        Icons.repeat,
                        color: _isRecurring ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      title: const Text('Repeat Daily'),
                      subtitle: const Text('Reset this task every day'),
                      value: _isRecurring,
                      onChanged: (value) => setState(() => _isRecurring = value),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Priority'),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Low'),
                  icon: Icon(Icons.arrow_downward),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Medium'),
                  icon: Icon(Icons.remove),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('High'),
                  icon: Icon(Icons.arrow_upward),
                ),
              ],
              selected: {_priority},
              onSelectionChanged: (Set<int> newSelection) {
                setState(() => _priority = newSelection.first);
              },
              multiSelectionEnabled: false,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _isLoading ? null : _saveTask,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(widget.isNew ? 'Create Task' : 'Save Changes'),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Future<void> _pickReminderTime() async {
    final now = DateTime.now();
    final time = await showTimePicker(
      context: context,
      initialTime: _reminderTime != null
          ? TimeOfDay.fromDateTime(_reminderTime!)
          : TimeOfDay.now(),
    );

    if (time != null && mounted) {
      final date = DateTime(now.year, now.month, now.day, time.hour, time.minute);
      setState(() => _reminderTime = date);
    }
  }

  Future<void> _saveTask() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task title')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final actions = ref.read(taskActionsProvider);

      if (widget.isNew) {
        await actions.createTask(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          reminderTime: _reminderTime,
          isRecurring: _isRecurring,
          recurrenceRule: _isRecurring ? 'daily' : null,
          priority: _priority,
        );
      } else {
        final repository = ref.read(taskRepositoryProvider);
        final existing = await repository.getTask(widget.taskId);
        if (existing != null) {
          await actions.updateTask(
            existing,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            reminderTime: _reminderTime,
            isRecurring: _isRecurring,
            recurrenceRule: _isRecurring ? 'daily' : null,
            priority: _priority,
          );
        }
      }

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task?'),
        content: const Text('This task will be moved to trash. You can restore it later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final actions = ref.read(taskActionsProvider);
      await actions.deleteTask(widget.taskId);
      if (mounted) context.pop();
    }
  }
}
