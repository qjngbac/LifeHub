import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/data_health/data/data_health_repository.dart';

class DataHealthPage extends ConsumerWidget {
  const DataHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('数据健康')),
        body: FutureBuilder<DataHealthReport>(
          future: DataHealthRepository(ref.read(databaseProvider)).inspect(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('数据检查失败'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final report = snapshot.data!;
            if (report.issues.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_outlined, size: 64),
                    SizedBox(height: 16),
                    Text('没有发现数据问题'),
                    SizedBox(height: 8),
                    Text('这项检查只读取数据，不会自动修改。'),
                  ],
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(
                      report.hasErrors
                          ? Icons.error_outline
                          : Icons.info_outline,
                    ),
                    title: Text('发现 ${report.issues.length} 项问题'),
                    subtitle: const Text('这里只报告问题，不会自动修复或删除数据。'),
                  ),
                ),
                ...report.issues.map((issue) => Card(
                      child: ListTile(
                        leading: Icon(
                          issue.severity == DataHealthSeverity.error
                              ? Icons.error_outline
                              : Icons.warning_amber_outlined,
                          color: issue.severity == DataHealthSeverity.error
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                        title: Text(issue.message),
                        subtitle: Text(issue.code),
                      ),
                    )),
              ],
            );
          },
        ),
      );
}
