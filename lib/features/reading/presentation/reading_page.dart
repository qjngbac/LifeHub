import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';
import 'package:lifehub/features/reading/presentation/reading_detail_page.dart';
import 'package:lifehub/features/reading/presentation/reading_form.dart';

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({super.key});

  @override
  ConsumerState<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends ConsumerState<ReadingPage> {
  var query = '';
  var revision = 0;

  @override
  Widget build(BuildContext context) {
    final repository = ReadingRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('阅读进度')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(repository),
        icon: const Icon(Icons.add),
        label: const Text('读物'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            hintText: '在阅读模块内搜索',
            leading: const Icon(Icons.search),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            key: ValueKey('$revision:$query'),
            future: repository.search(query),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) return const Center(child: Text('还没有阅读记录'));
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final progress = row.totalProgress == null
                      ? '${row.currentProgress}'
                      : '${row.currentProgress}/${row.totalProgress}';
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(row.title),
                      subtitle: Text(
                          '${row.author ?? '未填写作者'} · $progress ${_unit(row.progressUnit)}'),
                      trailing: IconButton(
                        tooltip: '进度加一',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: row.totalProgress != null &&
                                row.currentProgress >= row.totalProgress!
                            ? null
                            : () async {
                                await repository.updateProgress(
                                    row.id, row.currentProgress + 1);
                                if (mounted) setState(() => revision++);
                              },
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReadingDetailPage(itemId: row.id),
                          ),
                        );
                        if (mounted) setState(() => revision++);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _add(ReadingRepository repository) async {
    final draft = await showReadingForm(context);
    if (draft == null) return;
    await repository.create(draft);
    if (mounted) setState(() => revision++);
  }
}

String _unit(String value) => switch (value) {
      'PAGE' => '页',
      'CHAPTER' => '章',
      'PERCENT' => '%',
      _ => value
    };
