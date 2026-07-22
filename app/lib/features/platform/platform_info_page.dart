import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// 双端平台差异与后台行为对照（第 9 课）。
/// 纯讲解页：高亮当前运行平台，把 iOS / Android 的后台蓝牙模型讲清。
class PlatformInfoPage extends StatelessWidget {
  const PlatformInfoPage({super.key});

  bool get _isIOS => Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('双端差异与后台')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: Icon(_isIOS ? Icons.apple : Icons.android),
              title: Text('当前平台：${_isIOS ? 'iOS' : 'Android'}'),
              subtitle: Text(_isIOS
                  ? '后台由系统代管，可被设备事件唤醒'
                  : '后台需前台服务保活，否则会被限制'),
            ),
          ),
          const SizedBox(height: 8),
          _section('设备标识', const [
            ['iOS', '系统生成 UUID，换机即变，拿不到 MAC'],
            ['Android', '真实 MAC，跨机稳定（但 RPA 设备会变）'],
          ]),
          _section('订阅 CCCD', const [
            ['iOS', 'setNotifyValue 一步搞定，看不到 0x2902'],
            ['Android', '需 setCharacteristicNotification + 手写 CCCD'],
          ]),
          _section('MTU', const [
            ['iOS', '系统自动协商，App 不能指定'],
            ['Android', '可 requestMtu，最高 517'],
          ]),
          _section('后台保活', const [
            ['iOS', 'bluetooth-central 后台模式 + State Restoration'],
            ['Android', '前台服务（常驻通知）+ 电池优化白名单'],
          ]),
          _section('后台扫描', const [
            ['iOS', '必须带服务 UUID 过滤，间隔被拉长'],
            ['Android', '前台服务下可扫，但厂商 ROM 限制多'],
          ]),
          const SizedBox(height: 16),
          const _BackgroundNotes(),
        ],
      ),
    );
  }

  Widget _section(String title, List<List<String>> rows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(r[0],
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    Expanded(child: Text(r[1])),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundNotes extends StatelessWidget {
  const _BackgroundNotes();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('两条铁律', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('• iOS：用户上滑手动杀 App 后，State Restoration 也救不回来——'
                '这是系统政策，产品设计上要引导用户别杀。模拟器不支持状态恢复，必须真机验证。'),
            SizedBox(height: 6),
            Text('• Android：前台服务能保活，但国产 ROM（小米/华为/OPPO）的后台管控/'
                '电量优化会额外杀进程，必须引导用户把 App 加入电池优化白名单，否则一切配置白搭。'),
          ],
        ),
      ),
    );
  }
}
