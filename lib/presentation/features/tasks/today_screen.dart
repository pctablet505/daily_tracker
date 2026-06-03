import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/date_extensions.dart';
import '../../../core/utils/id_generator.dart';
import '../../../data/models/task_log_model.dart';
import '../../../data/models/task_model.dart';
import '../../providers/task_provider.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedCategoryProvider = StateProvider<String?>((ref) => null);

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  final _searchController = TextEditingController();
  bool _isSearching = false;

  DateTime get _today => DateTime.now().dateOnly;

  @override
  void initState() {
    super.initState();
    // Reset global filter providers so they don't persist across visits
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(searchQueryProvider.notifier).state = '';
      ref.read(selectedCategoryProvider.notifier).state = null;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(allTasksProvider);
    final completedAsync = ref.watch(completedTasksTodayProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search tasks...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                style: Theme.of(context).textTheme.titleMedium,
                onChanged: (value) {
                  ref.read(searchQueryProvider.notifier).state = value;
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _today.isToday ? 'Today' : _today.formattedDate,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    DateFormat('EEEE, MMMM d').format(_today),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  ref.read(searchQueryProvider.notifier).state = '';
                }
              });
            },
          ),
          Consumer(
            builder: (context, ref, child) {
              final completed = completedAsync.value?.length ?? 0;
              final total = (tasksAsync.value?.length ?? 0);
              final progress = total > 0 ? completed / total : 0.0;

              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 4,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: tasksAsync.when(
          data: (tasks) {
            // Apply search and category filters
            var filteredTasks = tasks;
            if (searchQuery.isNotEmpty) {
              final query = searchQuery.toLowerCase();
              filteredTasks = filteredTasks.where((t) {
                return t.title.toLowerCase().contains(query) ||
                    (t.description?.toLowerCase().contains(query) ?? false);
              }).toList();
            }
            if (selectedCategory != null) {
              filteredTasks = filteredTasks.where((t) => t.category == selectedCategory).toList();
            }

            if (filteredTasks.isEmpty && tasks.isEmpty) {
              return _EmptyState(onAddTask: () => _openNewTask(context));
            }

            if (filteredTasks.isEmpty) {
              return _NoResultsState(
                onClearFilters: () {
                  ref.read(searchQueryProvider.notifier).state = '';
                  ref.read(selectedCategoryProvider.notifier).state = null;
                  _searchController.clear();
                  setState(() => _isSearching = false);
                },
              );
            }

            // Group by category and completion
            final dosPending = filteredTasks.where((t) => t.category == 'Do' && !t.isCompleted).toList();
            final dosCompleted = filteredTasks.where((t) => t.category == 'Do' && t.isCompleted).toList();
            final dontsPending = filteredTasks.where((t) => t.category == 'Don\'t' && !t.isCompleted).toList();
            final dontsCompleted = filteredTasks.where((t) => t.category == 'Don\'t' && t.isCompleted).toList();
            final otherPending = filteredTasks.where((t) => t.category != 'Do' && t.category != 'Don\'t' && !t.isCompleted).toList();
            final otherCompleted = filteredTasks.where((t) => t.category != 'Do' && t.category != 'Don\'t' && t.isCompleted).toList();

            return CustomScrollView(
              slivers: [
                // Category filter chips
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: Text(
                              'All',
                              style: TextStyle(
                                fontWeight: selectedCategory == null ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            selected: selectedCategory == null,
                            onSelected: (_) {
                              ref.read(selectedCategoryProvider.notifier).state = null;
                            },
                            selectedColor: Theme.of(context).colorScheme.primaryContainer,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            showCheckmark: false,
                          ),
                          const SizedBox(width: 8),
                          ...AppConstants.categories.map((cat) {
                            final isSelected = selectedCategory == cat;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(
                                  cat,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                selected: isSelected,
                                onSelected: (_) {
                                  ref.read(selectedCategoryProvider.notifier).state =
                                      isSelected ? null : cat;
                                },
                                selectedColor: Theme.of(context).colorScheme.primaryContainer,
                                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                showCheckmark: false,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),

                // DOs - Pending
                if (dosPending.isNotEmpty) ...[
                  _buildSectionHeader(context, 'DOs (${dosPending.length})', color: Theme.of(context).colorScheme.primary),
                  _buildTaskList(context, ref, dosPending),
                ],

                // DON'Ts - Pending
                if (dontsPending.isNotEmpty) ...[
                  _buildSectionHeader(context, 'DON\'Ts (${dontsPending.length})', color: Theme.of(context).colorScheme.error),
                  _buildTaskList(context, ref, dontsPending),
                ],

                // Other - Pending
                if (otherPending.isNotEmpty) ...[
                  _buildSectionHeader(context, 'Pending (${otherPending.length})', color: Theme.of(context).colorScheme.primary),
                  _buildTaskList(context, ref, otherPending),
                ],

                // DOs - Completed
                if (dosCompleted.isNotEmpty) ...[
                  _buildSectionHeader(context, 'DOs Completed (${dosCompleted.length})', color: Theme.of(context).colorScheme.onSurfaceVariant),
                  _buildTaskList(context, ref, dosCompleted, isCompleted: true),
                ],

                // DON'Ts - Completed
                if (dontsCompleted.isNotEmpty) ...[
                  _buildSectionHeader(context, 'DON\'Ts Completed (${dontsCompleted.length})', color: Theme.of(context).colorScheme.onSurfaceVariant),
                  _buildTaskList(context, ref, dontsCompleted, isCompleted: true),
                ],

                // Other - Completed
                if (otherCompleted.isNotEmpty) ...[
                  _buildSectionHeader(context, 'Completed (${otherCompleted.length})', color: Theme.of(context).colorScheme.onSurfaceVariant),
                  _buildTaskList(context, ref, otherCompleted, isCompleted: true),
                ],

                const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
              ],
            );
          },
          loading: () => const _LoadingState(),
          error: (error, _) => Center(child: Text('Error: $error')),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewTask(context),
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {required Color color}) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      sliver: SliverToBoxAdapter(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  Widget _buildTaskList(BuildContext context, WidgetRef ref, List<TaskModel> tasks, {bool isCompleted = false}) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final task = tasks[index];
          return Slidable(
            key: ValueKey(task.id),
            startActionPane: ActionPane(
              motion: const ScrollMotion(),
              children: [
                SlidableAction(
                  onPressed: (_) async {
                    final actions = ref.read(taskActionsProvider);
                    await actions.toggleCompletion(task);
                  },
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  icon: task.isCompleted ? Icons.undo : Icons.check,
                  label: task.isCompleted ? 'Undo' : 'Done',
                  borderRadius: BorderRadius.circular(12),
                ),
              ],
            ),
            endActionPane: ActionPane(
              motion: const ScrollMotion(),
              children: [
                SlidableAction(
                  onPressed: (_) {
                    context.push('/task/${task.id}');
                  },
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  icon: Icons.edit,
                  label: 'Edit',
                  borderRadius: BorderRadius.circular(12),
                ),
                SlidableAction(
                  onPressed: (_) async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Task?'),
                        content: const Text('This task will be moved to trash. You can restore it later.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(ctx).colorScheme.error,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      final actions = ref.read(taskActionsProvider);
                      await actions.deleteTask(task.id);
                    }
                  },
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                  icon: Icons.delete,
                  label: 'Delete',
                  borderRadius: BorderRadius.circular(12),
                ),
              ],
            ),
            child: TaskCard(
              task: task,
              isCompleted: isCompleted,
            ),
          );
        },
      ),
    );
  }

  Future<void> _onRefresh() async {
    ref.invalidate(allTasksProvider);
    ref.invalidate(taskLogProvider);
    ref.invalidate(taskLogHistoryProvider);
    ref.invalidate(allTaskLogsProvider);
  }

  void _openNewTask(BuildContext context) {
    final newId = IdGenerator.generate();
    context.push('/task/$newId?new=true');
  }
}

class TaskCard extends ConsumerStatefulWidget {
  final TaskModel task;
  final bool isCompleted;

  const TaskCard({
    super.key,
    required this.task,
    this.isCompleted = false,
  });

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  final _valueController = TextEditingController();
  final _commentController = TextEditingController();
  String? _photoPath;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _syncControllers();
    }
  }

  void _syncControllers() {
    _valueController.clear();
    _commentController.clear();
    _photoPath = null;
  }

  @override
  void dispose() {
    _valueController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final task = widget.task;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _openTaskDetail(),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (task.taskType == 'checklist')
                    GestureDetector(
                      onTap: _toggleChecklist,
                      behavior: HitTestBehavior.opaque,
                      child: AbsorbPointer(
                        child: Checkbox(
                          value: task.isCompleted,
                          onChanged: (_) {},
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    )
                  else
                    _buildTypeIcon(colorScheme),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: widget.isCompleted ? TextDecoration.lineThrough : null,
                                color: widget.isCompleted
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.onSurface,
                              ),
                        ),
                        if (task.category != null)
                          Chip(
                            label: Text(
                              task.category!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: task.category == 'Don\'t'
                                        ? colorScheme.onErrorContainer
                                        : colorScheme.onSecondaryContainer,
                                  ),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: task.category == 'Don\'t'
                                ? colorScheme.errorContainer
                                : colorScheme.secondaryContainer,
                            side: BorderSide.none,
                          ),
                      ],
                    ),
                  ),
                  if (task.priority > 0)
                    Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _priorityColor(task.priority, colorScheme),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),

              // Show input fields for non-checklist pending tasks
              if (!widget.isCompleted && task.taskType != 'checklist') ...[
                const SizedBox(height: 8),
                _buildTaskInput(colorScheme),
              ],

              // Show saved data for completed non-checklist tasks
              if (widget.isCompleted && task.taskType != 'checklist') ...[
                const SizedBox(height: 8),
                _buildCompletedData(colorScheme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeIcon(ColorScheme colorScheme) {
    final icon = widget.task.taskType == 'numeric' ? Icons.numbers :
                 widget.task.taskType == 'text' ? Icons.notes :
                 widget.task.taskType == 'photo' ? Icons.camera_alt :
                 Icons.check_circle_outline;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Icon(icon, color: colorScheme.primary, size: 24),
    );
  }

  Widget _buildTaskInput(ColorScheme colorScheme) {
    final task = widget.task;

    switch (task.taskType) {
      case 'numeric':
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _valueController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saveAndComplete(),
                decoration: InputDecoration(
                  hintText: 'Enter value',
                  suffixText: task.description?.isNotEmpty == true ? task.description : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildSaveButton(),
          ],
        );

      case 'text':
        return Column(
          children: [
            TextField(
              controller: _commentController,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveAndComplete(),
              decoration: InputDecoration(
                hintText: 'Add notes / comment...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: _buildSaveButton(),
            ),
          ],
        );

      case 'photo':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_photoPath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_photoPath!),
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: Text(_photoPath == null ? 'Take Photo' : 'Retake'),
                ),
                const SizedBox(width: 8),
                if (_photoPath != null) _buildSaveButton(),
              ],
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSaveButton() {
    return FilledButton.icon(
      onPressed: _isSaving ? null : _saveAndComplete,
      icon: _isSaving
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.check, size: 18),
      label: Text(_isSaving ? 'Saving...' : 'Done'),
    );
  }

  Widget _buildCompletedData(ColorScheme colorScheme) {
    return Consumer(
      builder: (context, ref, child) {
        final today = DateTime.now().dateOnly;
        final logAsync = ref.watch(taskLogProvider(TaskLogParam(widget.task.id, today)));

        return logAsync.when(
          data: (log) {
            if (log == null) return const SizedBox.shrink();

            if (widget.task.taskType == 'photo' && log.mediaPath != null) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(log.mediaPath!),
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              );
            }

            if (log.comment != null && log.comment!.isNotEmpty) {
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  log.comment!,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              );
            }

            return const SizedBox.shrink();
          },
          loading: () => const SizedBox(height: 20, child: LinearProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
    );
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, maxWidth: 1200, maxHeight: 1200);
    if (picked != null) {
      setState(() => _photoPath = picked.path);
    }
  }

  Future<void> _saveAndComplete() async {
    setState(() => _isSaving = true);
    try {
      final task = widget.task;
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      String? comment;
      String? mediaPath;

      if (task.taskType == 'numeric') {
        comment = _valueController.text.trim();
        if (comment.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a value')),
          );
          return;
        }
      } else if (task.taskType == 'text') {
        comment = _commentController.text.trim();
        if (comment.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please add a note')),
          );
          return;
        }
      } else if (task.taskType == 'photo') {
        if (_photoPath == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please take a photo')),
          );
          return;
        }
        mediaPath = _photoPath;
      }

      final actions = ref.read(taskActionsProvider);
      // Mark task as completed first (creates today's log), then update log with data
      if (!task.isCompleted) {
        await actions.toggleCompletion(task);
      }
      await actions.saveTaskLog(TaskLogModel(
        id: IdGenerator.generate(),
        taskId: task.id,
        date: dateStr,
        isCompleted: true,
        completedAt: today,
        comment: comment,
        mediaPath: mediaPath,
        createdAt: today,
        updatedAt: today,
      ));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleChecklist() async {
    final actions = ref.read(taskActionsProvider);
    await actions.toggleCompletion(widget.task);
  }

  void _openTaskDetail() {
    context.push('/task/${widget.task.id}');
  }

  Color _priorityColor(int priority, ColorScheme scheme) {
    switch (priority) {
      case 2:
        return scheme.error;
      case 1:
        return scheme.tertiary;
      default:
        return scheme.surfaceContainerHighest;
    }
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddTask;

  const _EmptyState({required this.onAddTask});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 80,
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No tasks for today',
                      style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add your first task to start tracking your daily goals.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: onAddTask,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Task'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoResultsState extends StatelessWidget {
  final VoidCallback onClearFilters;

  const _NoResultsState({required this.onClearFilters});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No tasks found',
                      style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try adjusting your search or filters.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onClearFilters,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear Filters'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 80,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
