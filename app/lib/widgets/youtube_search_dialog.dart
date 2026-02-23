import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/youtube_provider.dart';

class YoutubeSearchDialog extends StatefulWidget {
  const YoutubeSearchDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => const YoutubeSearchDialog(),
    );
  }

  @override
  State<YoutubeSearchDialog> createState() => _YoutubeSearchDialogState();
}

class _YoutubeSearchDialogState extends State<YoutubeSearchDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      context.read<YoutubeProvider>().searchYoutube(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<YoutubeProvider>();

    return Dialog(
      child: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search YouTube...',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _onSearch,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _onSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: provider.isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : provider.searchResults.isEmpty
                      ? const Center(child: Text('Нет результатов'))
                      : ListView.separated(
                          itemCount: provider.searchResults.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final video = provider.searchResults[index];
                            final thumbnailUrl = (video.thumbnails != null && video.thumbnails!.isNotEmpty) 
                                ? video.thumbnails!.last['url'] as String? 
                                : null;
                            
                            return ListTile(
                              leading: thumbnailUrl != null
                                  ? Image.network(thumbnailUrl, width: 80, fit: BoxFit.cover)
                                  : Container(width: 80, color: Colors.grey),
                              title: Text(video.title ?? 'Без названия', maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(video.duration != null ? '${(video.duration! / 60).floor()}:${(video.duration! % 60).toInt().toString().padLeft(2, '0')}' : ''),
                              onTap: () {
                                Navigator.of(context).pop(video.url);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
