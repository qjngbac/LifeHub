import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/security/app_lock.dart';
import 'package:lifehub/shared/ui/app_lock_dialogs.dart';

/// 二级密码管理页（我的 → 安全与隐私 → 二级密码）。
class AppLockPage extends ConsumerWidget {
  const AppLockPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('二级密码')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    lock.configured ? Icons.lock : Icons.lock_open_outlined,
                    color: lock.configured
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(lock.configured ? '已开启' : '未开启'),
                  subtitle: Text(
                    lock.configured
                        ? '查看私密便签等内容需要输入二级密码；解锁后 '
                            '${AppLockNotifier.unlockWindow.inMinutes} 分钟内免重复输入'
                        : '开启后，查看私密便签等内容需要先输入二级密码',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption_outlined),
                  title: Text(lock.configured ? '修改二级密码' : '开启二级密码'),
                  subtitle: const Text('4-16 位，需输入两次确认'),
                  onTap: () => changeAppPin(context, ref),
                ),
                if (lock.configured) ...[
                  ListTile(
                    leading: const Icon(Icons.lock_reset_outlined),
                    title: const Text('立即锁定'),
                    subtitle: const Text('清除本机解锁状态，下次查看需重新输入'),
                    onTap: () {
                      ref.read(appLockProvider.notifier).lock();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已锁定')),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_open_outlined),
                    title: const Text('关闭二级密码'),
                    subtitle: const Text('关闭后私密便签将不再受保护'),
                    onTap: () => disableAppPin(context, ref),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('说明', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            '· 二级密码只保存在本机（PBKDF2 加盐哈希），不会上传，也不会写进备份文件。\n'
            '· 忘记密码只能清除这层锁，私密内容本身不会因此丢失。\n'
            '· 本地数据库里的私密正文仍是明文存储：二级密码保护的是"查看入口"，'
            '不等于磁盘加密。',
            style: TextStyle(height: 1.5),
          ),
        ],
      ),
    );
  }
}
