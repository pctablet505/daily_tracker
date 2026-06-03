import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/date_extensions.dart';
import '../../../core/utils/id_generator.dart';
import '../../../data/models/task_log_model.dart';
import '../../providers/task_provider.dart';
import '../../../services/media/media_service.dart';
import '../../widgets/common/section_title.dart';

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
  final _commentController = TextEditingController();
  DateTime? _reminderTime;
  bool _isRecurring = false;
  String? _category;
  String? _taskType = 'checklist';
  int _priority = 0;
  bool _isLoading = false;

  // Daily log state fields
  TaskLogModel? _todayLog;
  String? _mediaPath;
  bool _logCompleted = false;

  @override
  void initState() {
    super.initState();
    _loadTask();
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
        _category = task.category;
        _taskType = task.taskType;
        _priority = task.priority;
      });
    }

    // Load today's log
    final today = DateTime.now();
    final log = await repository.getTaskLog(widget.taskId, today);
    if (log != null && mounted) {
      setState(() {
        _todayLog = log;
        _commentController.text = log.comment ?? '';
        _mediaPath = log.mediaPath;
        _logCompleted = log.isCompleted;
      });
    }
    // Note: We do NOT infer today's log completion from task.isCompleted,
    // because task.isCompleted reflects the last time the task was toggled,
    // which may be from a previous day. Creating a false log for "today"
    // would inflate today's completion stats incorrectly.
  }

  Future<void> _pickImage() async {
    final path = await MediaService.pickAndSaveImage();
    if (path != null && mounted) {
      setState(() => _mediaPath = path);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _commentController.dispose();
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
            const SectionTitle('Reminder'),
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
            const SectionTitle('Category'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...AppConstants.categories.map((cat) {
                  final isSelected = _category == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _category = selected ? cat : null);
                    },
                  );
                }),
              ],
            ),
            const SizedBox(height: 24),
            const SectionTitle('Priority'),
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
            const SizedBox(height: 24),
            const SectionTitle('Task Type'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _taskType,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.category_outlined),
                hintText: 'Select task type',
              ),
              items: const [
                DropdownMenuItem(value: 'checklist', child: Text('Checklist')),
                DropdownMenuItem(value: 'numeric', child: Text('Numeric (e.g. weight)')),
                DropdownMenuItem(value: 'text', child: Text('Text (e.g. notes)')),
                DropdownMenuItem(value: 'photo', child: Text('Photo (e.g. progress pic)')),
              ],
              onChanged: (value) => setState(() => _taskType = value),
            ),
            const SizedBox(height: 24),
            const SectionTitle("Today's Entry & Progress"),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Completed for Today"),
                      subtitle: const Text("Mark this task as done today"),
                      value: _logCompleted,
                      onChanged: (value) => setState(() => _logCompleted = value ?? false),
                    ),
                    const SizedBox(height: 12),
                    if (_taskType == 'numeric')
                      TextField(
                        controller: _commentController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: "Value (e.g. weight, measurement)",
                          hintText: "Enter a numeric value...",
                          prefixIcon: Icon(Icons.numbers),
                        ),
                        maxLines: 1,
                      )
                    else
                      TextField(
                        controller: _commentController,
                        decoration: const InputDecoration(
                          labelText: "Comment / Notes",
                          hintText: "Enter notes, interactions, comments...",
                          prefixIcon: Icon(Icons.note_alt_outlined),
                        ),
                        maxLines: 2,
                      ),
                    const SizedBox(height: 16),
                    Text(
                      "Media / Photo Upload",
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_mediaPath == null)
                      OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text("Attach Photo"),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_mediaPath!),
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: _pickImage,
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text("Change"),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () => setState(() => _mediaPath = null),
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                label: const Text("Remove", style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const SectionTitle("Historical Logs"),
            const SizedBox(height: 8),
            Consumer(
              builder: (context, ref, child) {
                final historyAsync = ref.watch(taskLogHistoryProvider(widget.taskId));
                return historyAsync.when(
                  data: (logs) {
                    if (logs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            "No historical logs recorded yet",
                            style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: logs.map((log) => _buildHistoryCard(context, log)).toList(),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text("Error: $err")),
                );
              },
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

  Widget _buildHistoryCard(BuildContext context, TaskLogModel log) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                ),
                const SizedBox(width: 8),
                Text(
                  log.date,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
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
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickReminderTime() async {
    final now = DateTime.now();
    // Pick date first, then time
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderTime ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _reminderTime != null
          ? TimeOfDay.fromDateTime(_reminderTime!)
          : TimeOfDay.now(),
    );

    if (time != null && mounted) {
      final reminder = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      setState(() => _reminderTime = reminder);
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

      String currentTaskId = widget.taskId;
      if (widget.isNew) {
        final task = await actions.createTask(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          reminderTime: _reminderTime,
          isRecurring: _isRecurring,
          recurrenceRule: _isRecurring ? 'daily' : null,
          category: _category,
          taskType: _taskType,
          priority: _priority,
        );
        currentTaskId = task.id;
      } else {
        final repository = ref.read(taskRepositoryProvider);
        final existing = await repository.getTask(widget.taskId);
        if (existing == null) {
          throw StateError('Task no longer exists. It may have been deleted.');
        }
        await actions.updateTask(
          existing,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          reminderTime: _reminderTime,
          isRecurring: _isRecurring,
          recurrenceRule: _isRecurring ? 'daily' : null,
          category: _category,
          taskType: _taskType,
          priority: _priority,
        );
      }

      // Save today's log
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      final log = TaskLogModel(
        id: _todayLog?.id ?? IdGenerator.generate(),
        taskId: currentTaskId,
        date: dateStr,
        isCompleted: _logCompleted,
        completedAt: _logCompleted ? (_todayLog?.completedAt ?? today) : null,
        comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
        mediaPath: _mediaPath,
        createdAt: _todayLog?.createdAt ?? today,
        updatedAt: today,
      );
      await actions.saveTaskLog(log);

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
