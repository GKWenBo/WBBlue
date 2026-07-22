import 'package:flutter/material.dart';

import '../demo/mock_demo_page.dart';
import '../platform/platform_info_page.dart';
import '../scan/scan_page.dart';

/// 「设备管家」首页（第 10 课）：综合项目的门面，把各课能力串成一个入口。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备管家')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('BLE 实战全流程',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('扫描 · 连接 · GATT 读写 · 订阅 · 私有协议 · 自动重连',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          _EntryCard(
            icon: Icons.bluetooth_searching,
            title: '真机模式',
            subtitle: '扫描附近设备 → 连接 → GATT/心率/协议控制台',
            color: Colors.blue,
            onTap: () => _push(context, const ScanPage()),
          ),
          _EntryCard(
            icon: Icons.science_outlined,
            title: '离线演示（Mock）',
            subtitle: '无需真机：虚拟心率带 + 固件设备 + 故障注入',
            color: Colors.teal,
            onTap: () => _push(context, const MockDemoPage()),
          ),
          _EntryCard(
            icon: Icons.info_outline,
            title: '双端差异与后台',
            subtitle: 'iOS / Android 平台差异与后台保活模型',
            color: Colors.deepPurple,
            onTap: () => _push(context, const PlatformInfoPage()),
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('课程能力清单',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Text('• 第 2-3 课：扫描 / 连接（超时、状态流、幽灵设备治理）\n'
                      '• 第 4-5 课：GATT 读写 / 订阅通知（心率实时曲线）\n'
                      '• 第 6 课：私有协议（CRC / 半包粘包 / 分包）\n'
                      '• 第 7 课：自动重连（指数退避 / 重建订阅）\n'
                      '• 第 8 课：抽象接口 + Mock 双实现（可离线可测试）\n'
                      '• 第 9 课：双端差异 / 后台保活'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => page));
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
