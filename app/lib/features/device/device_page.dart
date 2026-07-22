import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocol/protocol_console_page.dart';
import 'device_controller.dart';
import 'gatt_browser.dart';
import 'heart_rate_chart.dart';

/// 设备详情页骨架（第 3 课）：连接状态卡片 + 动作按钮。
/// GATT 服务浏览与读写在第 4 课长到这页下方。
class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.device, required this.name});

  final BluetoothDevice device;
  final String name;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final DeviceController _controller = DeviceController(widget.device);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.name.isEmpty ? '未知设备' : widget.name),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StateCard(controller: _controller, device: widget.device),
              const SizedBox(height: 16),
              _ActionButtons(controller: _controller),
              if (_controller.hrSamples.isNotEmpty) ...[
                const SizedBox(height: 16),
                HeartRateChart(
                  samples: _controller.hrSamples,
                  currentBpm: _controller.currentBpm,
                  capacity: DeviceController.maxHrSamples,
                ),
              ],
              if (_controller.isConnected &&
                  _controller.services.isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProtocolConsolePage(
                        device: widget.device,
                        services: _controller.services,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.terminal),
                  label: const Text('私有协议控制台（第 6 课）'),
                ),
              ],
              const SizedBox(height: 24),
              GattBrowser(controller: _controller),
            ],
          ),
        );
      },
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.controller, required this.device});

  final DeviceController controller;
  final BluetoothDevice device;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = controller.isConnected;
    final reason = DeviceController.describeDisconnect(
      controller.disconnectReason,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: connected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 8),
                Text(
                  controller.busy ? '处理中…' : (connected ? '已连接' : '未连接'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (controller.linkRssi != null)
                  Text('链路 RSSI: ${controller.linkRssi} dBm'),
              ],
            ),
            const SizedBox(height: 8),
            Text(device.remoteId.str,
                style: Theme.of(context).textTheme.bodySmall),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(reason, style: TextStyle(color: scheme.error)),
            ],
            if (controller.lastError != null) ...[
              const SizedBox(height: 8),
              Text(controller.lastError!,
                  style: TextStyle(color: scheme.error),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.controller});

  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    final connected = controller.isConnected;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: controller.busy
                ? null
                : (connected ? controller.disconnect : controller.connect),
            icon: controller.busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(connected ? Icons.link_off : Icons.link),
            label: Text(connected ? '断开' : '连接'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: connected ? controller.readRssi : null,
            icon: const Icon(Icons.network_check),
            label: const Text('读取 RSSI'),
          ),
        ),
      ],
    );
  }
}
