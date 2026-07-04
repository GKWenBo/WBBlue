import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../device/device_page.dart';
import 'scan_controller.dart';

/// 扫描页（第 2 课）：空态 / 错误态 / 过滤开关 / 结果列表。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final ScanController _controller = ScanController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 进详情页前先停扫描：安卓上边扫边连会显著提高 status 133 概率（第一条军规）
  Future<void> _openDevice(BuildContext context, ScanResult result) async {
    await _controller.stopScan();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DevicePage(
          device: result.device,
          name: ScanController.displayName(result),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final bluetoothOff =
            _controller.adapterState != BluetoothAdapterState.on;
        return Scaffold(
          appBar: AppBar(title: const Text('扫描附近的 BLE 设备')),
          body: Column(
            children: [
              if (_controller.lastError != null)
                _ErrorBanner(
                  message: _controller.lastError!,
                  onDismiss: () => _controller.startScan(),
                ),
              _FilterBar(controller: _controller),
              const Divider(height: 1),
              Expanded(
                child: bluetoothOff
                    ? _EmptyHint(
                        icon: Icons.bluetooth_disabled,
                        text: '蓝牙未开启\n请在系统设置中打开蓝牙',
                      )
                    : _controller.visibleResults.isEmpty
                        ? _EmptyHint(
                            icon: Icons.radar,
                            text: _controller.isScanning
                                ? '正在扫描…\n把模拟外设的手机凑近一点'
                                : '点击右下角开始扫描',
                          )
                        : ListView.separated(
                            itemCount: _controller.visibleResults.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1, indent: 16),
                            itemBuilder: (context, index) {
                              final result =
                                  _controller.visibleResults[index];
                              return _ResultTile(
                                result: result,
                                onTap: () => _openDevice(context, result),
                              );
                            },
                          ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: bluetoothOff ? null : _controller.toggleScan,
            icon: Icon(_controller.isScanning ? Icons.stop : Icons.search),
            label: Text(_controller.isScanning ? '停止' : '扫描'),
          ),
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('隐藏无名设备'),
            selected: controller.hideUnnamed,
            onSelected: controller.setHideUnnamed,
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('只看心率服务'),
            selected: controller.onlyHeartRate,
            onSelected: controller.setOnlyHeartRate,
          ),
          const Spacer(),
          Text(
            '${controller.visibleResults.length} 台',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.onTap});

  final ScanResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = ScanController.displayName(result);
    final adv = result.advertisementData;
    return ListTile(
      // 不可连接的设备（纯广播的信标）没有详情页可看
      onTap: adv.connectable ? onTap : null,
      leading: _RssiIndicator(rssi: result.rssi),
      title: Text(name.isEmpty ? '（无名设备）' : name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 安卓显示真 MAC；iOS 是系统生成的 UUID，换台手机就不同
          Text(result.device.remoteId.str),
          if (adv.serviceUuids.isNotEmpty)
            Text('服务: ${adv.serviceUuids.map(_shortUuid).join(', ')}'),
          if (adv.manufacturerData.isNotEmpty)
            Text(_manufacturerSummary(adv.manufacturerData),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: adv.connectable
          ? const Icon(Icons.link, size: 18)
          : const Icon(Icons.link_off, size: 18),
      isThreeLine:
          adv.serviceUuids.isNotEmpty || adv.manufacturerData.isNotEmpty,
    );
  }

  /// 标准 16-bit UUID 只显示短形式（0000180d-... → 180D）
  static String _shortUuid(Guid g) {
    final s = g.str;
    return s.length == 36 && s.startsWith('0000') && s.contains('-0000-1000-')
        ? s.substring(4, 8).toUpperCase()
        : s;
  }

  static String _manufacturerSummary(Map<int, List<int>> data) {
    final e = data.entries.first;
    final id = '0x${e.key.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    final bytes = e.value
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    return '厂商 $id: $bytes${e.value.length > 8 ? ' …' : ''}';
  }
}

/// RSSI 信号强度指示：只做条目内图标，不参与排序（避免列表乱跳）
class _RssiIndicator extends StatelessWidget {
  const _RssiIndicator({required this.rssi});

  final int rssi;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (rssi) {
      > -60 => (Icons.signal_cellular_alt, Colors.green),
      > -75 => (Icons.signal_cellular_alt_2_bar, Colors.orange),
      _ => (Icons.signal_cellular_alt_1_bar, Colors.grey),
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        Text('$rssi', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MaterialBanner(
      backgroundColor: scheme.errorContainer,
      content: Text(message,
          style: TextStyle(color: scheme.onErrorContainer),
          maxLines: 3,
          overflow: TextOverflow.ellipsis),
      actions: [
        TextButton(onPressed: onDismiss, child: const Text('重试')),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
