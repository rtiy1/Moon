import 'package:flutter/material.dart';

import 'api.dart';
import 'session.dart';
import 'widgets.dart';
import 'login_screen.dart';

/// 设置底部弹窗：用户信息 / 服务器信息 / 修改密码 / 清理数据 / 登出
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  String _username = '';
  String _server = '';
  String _siteName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = await Session.username;
    final s = await Session.serverUrl;
    final n = await Session.siteName;
    if (mounted) {
      setState(() {
        _username = u ?? '';
        _server = s ?? '';
        _siteName = n ?? 'LunaTV';
      });
    }
  }

  void _changePassword() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: oldCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '当前密码')),
            TextField(
                controller: newCtrl,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: '新密码（至少 6 位）')),
            TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '确认新密码')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (newCtrl.text.length < 6) {
                toast(context, '新密码至少 6 位', error: true);
                return;
              }
              if (newCtrl.text != confirmCtrl.text) {
                toast(context, '两次输入不一致', error: true);
                return;
              }
              final r =
                  await Api.changePassword(oldCtrl.text, newCtrl.text);
              if (!context.mounted) return;
              if (r.ok) {
                Navigator.pop(ctx);
                toast(context, '密码已修改');
              } else {
                toast(context, r.error ?? '修改失败', error: true);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(String title, Future<void> Function() action) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await action();
              if (mounted) toast(context, '已完成');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            CircleAvatar(
              radius: 28,
              backgroundColor: kAccent.withValues(alpha: 0.2),
              child: const Icon(Icons.person, color: kAccent, size: 30),
            ),
            const SizedBox(height: 8),
            Text(_username.isEmpty ? '用户' : _username,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('$_siteName · $_server',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('修改密码'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changePassword,
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('清空播放记录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _confirm(
                  '清空所有播放记录？', () => Api.clearPlayRecords()),
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('清空搜索历史'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _confirm(
                  '清空搜索历史？', () => Api.clearSearchHistory()),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('登出',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                await Session.logout();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
