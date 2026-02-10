import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_overlay.dart';
import 'writing_submission_detail_screen.dart';

class WritingHistoryScreen extends StatefulWidget {
  const WritingHistoryScreen({super.key});

  @override
  State<WritingHistoryScreen> createState() => _WritingHistoryScreenState();
}

class _WritingHistoryScreenState extends State<WritingHistoryScreen> {
  List<WritingSubmissionListItem>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<AuthProvider>().api.getWritingHistory(limit: 100);
      if (mounted) setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История проверок'),
      ),
      body: _loading
          ? const LoadingOverlay(message: 'Загрузка истории…', compact: true)
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline,
                  message: _error!,
                  actionLabel: 'Повторить',
                  onAction: _load,
                )
              : (_items == null || _items!.isEmpty)
                  ? const EmptyState(
                      icon: Icons.history,
                      message: 'Пока нет сохранённых проверок. Отправьте текст на проверку в IELTS Письмо.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        itemCount: _items!.length,
                        itemBuilder: (context, i) {
                          final item = _items![i];
                          final timeStr = item.timeUsedSeconds != null
                              ? '${item.timeUsedSeconds! ~/ 60}:${(item.timeUsedSeconds! % 60).toString().padLeft(2, '0')}'
                              : '—';
                          final dateStr = _formatDate(item.createdAt);
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              title: Text('${item.wordCount} слов · $timeStr', style: Theme.of(context).textTheme.titleSmall),
                              subtitle: Text(
                                item.evaluationPreview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(dateStr, style: Theme.of(context).textTheme.bodySmall),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WritingSubmissionDetailScreen(submissionId: item.id),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Сегодня ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}
