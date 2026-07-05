import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/gatt_names.dart';
import '../../core/hex.dart';
import 'device_controller.dart';

/// GATT 服务浏览器（第 4 课）：Service 分组展开，特征卡片支持读/写。
class GattBrowser extends StatelessWidget {
  const GattBrowser({super.key, required this.controller});

  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.discovering) {
      return const Card(
        child: ListTile(
          leading: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('正在发现服务…'),
        ),
      );
    }
    if (controller.services.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.account_tree_outlined),
          title: const Text('GATT 服务'),
          subtitle: Text(controller.isConnected ? '未发现服务' : '连接后可用'),
          enabled: false,
        ),
      );
    }
    return Column(
      children: [
        for (final service in controller.services)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              title: Text(serviceDisplayName(service.serviceUuid)),
              subtitle: Text(
                '${service.characteristics.length} 个特征',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              children: [
                for (final c in service.characteristics)
                  _CharacteristicTile(controller: controller, characteristic: c),
              ],
            ),
          ),
      ],
    );
  }
}

class _CharacteristicTile extends StatelessWidget {
  const _CharacteristicTile({
    required this.controller,
    required this.characteristic,
  });

  final DeviceController controller;
  final BluetoothCharacteristic characteristic;

  @override
  Widget build(BuildContext context) {
    final props = characteristic.properties;
    final value = characteristic.lastValue;
    final text = tryDecodeUtf8(value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(characteristicDisplayName(characteristic.uuid),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              if (props.read) const _PropBadge('读'),
              if (props.write) const _PropBadge('写'),
              if (props.writeWithoutResponse) const _PropBadge('免响写'),
              if (props.notify) const _PropBadge('通知'),
              if (props.indicate) const _PropBadge('指示'),
            ],
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('HEX: ${toHexString(value)}',
                style: Theme.of(context).textTheme.bodySmall),
            if (text != null)
              Text('文本: $text', style: Theme.of(context).textTheme.bodySmall),
          ],
          Row(
            children: [
              if (props.read)
                TextButton.icon(
                  onPressed: () =>
                      controller.readCharacteristic(characteristic),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('读取'),
                ),
              if (props.write || props.writeWithoutResponse)
                TextButton.icon(
                  onPressed: () => _showWriteDialog(context),
                  icon: const Icon(Icons.upload, size: 16),
                  label: const Text('写入'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showWriteDialog(BuildContext context) async {
    final props = characteristic.properties;
    final input = TextEditingController();
    // 默认选 with response（可靠）；特征不支持时退到免响写
    var withResponse = props.write;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('写入特征'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: input,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '十六进制字节',
                  hintText: '如 48 69 或 4869',
                ),
              ),
              // 两种写类型都支持时才有选择余地（讲义第三节的选型题）
              if (props.write && props.writeWithoutResponse)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('要求响应 (with response)'),
                  value: withResponse,
                  onChanged: (v) => setState(() => withResponse = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('写入'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final bytes = tryParseHex(input.text);
    if (bytes == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('十六进制格式不合法（需偶数个 0-9A-F 字符）')),
      );
      return;
    }
    final ok = await controller.writeCharacteristic(
      characteristic,
      bytes,
      withResponse: withResponse,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '已写入 ${bytes.length} 字节' : '写入失败，详见错误信息')),
    );
  }
}

class _PropBadge extends StatelessWidget {
  const _PropBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}
