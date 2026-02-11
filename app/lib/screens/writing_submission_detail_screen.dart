import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/loading_overlay.dart';

class WritingSubmissionDetailScreen extends StatefulWidget {
  const WritingSubmissionDetailScreen({super.key, required this.submissionId});

  final String submissionId;

  @override
  State<WritingSubmissionDetailScreen> createState() => _WritingSubmissionDetailScreenState();
}

class _WritingSubmissionDetailScreenState extends State<WritingSubmissionDetailScreen> {
  WritingSubmissionDetail? _detail;
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
      final d = await context.read<AuthProvider>().api.getWritingSubmission(widget.submissionId);
      if (mounted) setState(() {
        _detail = d;
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
        title: const Text('Проверка'),
      ),
      body: _loading
          ? const LoadingOverlay(message: 'Загрузка…', compact: true)
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))
              : _detail == null
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      padding: AppTheme.paddingScreen,
                      child: _buildContent(_detail!),
                    ),
    );
  }

  void _copyToClipboard(String text, String label) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label скопировано')));
  }

  Widget _buildContent(WritingSubmissionDetail r) {
    final timeStr = r.timeUsedSeconds != null
        ? '${r.timeUsedSeconds! ~/ 60}:${(r.timeUsedSeconds! % 60).toString().padLeft(2, '0')}'
        : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${r.wordCount} слов · время: $timeStr · ${_formatDate(r.createdAt)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 16),
        _Section(title: 'Исходный текст', child: Text(r.originalText), onCopy: () => _copyToClipboard(r.originalText, 'Исходный текст')),
        _Section(title: 'Оценка', child: Text(r.evaluation)),
        _Section(title: 'Исправленный текст', child: Text(r.correctedText), onCopy: () => _copyToClipboard(r.correctedText, 'Исправленный текст')),
        if (r.errors.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Ошибки (${r.errors.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          ...r.errors.map((e) => Card(
            child: Padding(
              padding: AppTheme.paddingCard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(label: Text(e.type, style: const TextStyle(fontSize: 12))),
                      const SizedBox(width: 8),
                      Expanded(child: Text('«${e.original}» → ${e.correction}', style: const TextStyle(fontWeight: FontWeight.w500))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(e.explanation, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          )),
          const SizedBox(height: 16),
        ],
        if (r.recommendations.isNotEmpty) _Section(title: 'Рекомендации', child: Text(r.recommendations)),
      ],
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.onCopy});

  final String title;
  final Widget child;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (onCopy != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: onCopy,
                  tooltip: 'Копировать',
                  style: IconButton.styleFrom(minimumSize: const Size(36, 36), padding: EdgeInsets.zero),
                ),
              ],
            ],
          ),
        ),
        Card(
          child: Padding(
            padding: AppTheme.paddingCard,
            child: child,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
