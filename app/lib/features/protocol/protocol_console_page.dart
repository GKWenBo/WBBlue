import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/gatt_names.dart';
import '../../core/hex.dart';
import 'protocol_session.dart';

/// 私有协议控制台（第 6 课）：选一条写特征 + 一条通知特征，
/// 手动构帧发送，实时看解出的帧 / 坏帧重同步。
class ProtocolConsolePage extends StatefulWidget {
  const ProtocolConsolePage({
    super.key,
    required this.device,
    required this.services,
  });

  final BluetoothDevice device;
  final List<BluetoothService> services;

  @override
  State<ProtocolConsolePage> createState() => _ProtocolConsolePageState();
}

class _ProtocolConsolePageState extends State<ProtocolConsolePage> {
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  ProtocolSession? _session;

  final _cmdCtrl = TextEditingController(text: '10');
  final _payloadCtrl = TextEditingController(text: '01 02 03');

  late final List<BluetoothCharacteristic> _writable;
  late final List<BluetoothCharacteristic> _notifiable;

  @override
  void initState() {
    super.initState();
    final all = widget.services.expand((s) => s.characteristics).toList();
    _writable = all
        .where((c) => c.properties.write || c.properties.writeWithoutResponse)
        .toList();
    _notifiable =
        all.where((c) => c.properties.notify || c.properties.indicate).toList();
    // 常见私有协议是「同一 Service 下一写一通知」，尝试各自预选第一条
    _writeChar = _writable.isNotEmpty ? _writable.first : null;
    _notifyChar = _notifiable.isNotEmpty ? _notifiable.first : null;
  }

  @override
  void dispose() {
    _session?.dispose();
    _cmdCtrl.dispose();
    _payloadCtrl.dispose();
    super.dispose();
  }

  Future<void> _bind() async {
    if (_writeChar == null || _notifyChar == null) return;
    _session?.dispose();
    final session = ProtocolSession(
      device: widget.device,
      writeChar: _writeChar!,
      notifyChar: _notifyChar!,
    );
    setState(() => _session = session);
    await session.start();
  }

  Future<void> _send() async {
    final session = _session;
    if (session == null) return;
    final cmd = tryParseHex(_cmdCtrl.text);
    final payload = tryParseHex(_payloadCtrl.text) ?? Uint8List(0);
    if (cmd == null || cmd.length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('命令字需为 1 个十六进制字节，如 10')),
      );
      return;
    }
    await session.send(cmd.first, payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('私有协议控制台')),
      body: Column(
        children: [
          _selectors(),
          const Divider(height: 1),
          _composer(),
          const Divider(height: 1),
          Expanded(child: _logView()),
        ],
      ),
    );
  }

  Widget _selectors() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _charDropdown(
            label: '写特征（下发）',
            value: _writeChar,
            items: _writable,
            onChanged: (c) => setState(() => _writeChar = c),
          ),
          const SizedBox(height: 8),
          _charDropdown(
            label: '通知特征（上报）',
            value: _notifyChar,
            items: _notifiable,
            onChanged: (c) => setState(() => _notifyChar = c),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  (_writeChar != null && _notifyChar != null) ? _bind : null,
              icon: const Icon(Icons.link),
              label: Text(_session == null ? '绑定并订阅' : '重新绑定'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _charDropdown({
    required String label,
    required BluetoothCharacteristic? value,
    required List<BluetoothCharacteristic> items,
    required ValueChanged<BluetoothCharacteristic?> onChanged,
  }) {
    return DropdownButtonFormField<BluetoothCharacteristic>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final c in items)
          DropdownMenuItem(
            value: c,
            child: Text(characteristicDisplayName(c.uuid),
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _composer() {
    final enabled = _session != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: TextField(
              controller: _cmdCtrl,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'cmd', hintText: '10'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _payloadCtrl,
              enabled: enabled,
              decoration:
                  const InputDecoration(labelText: 'payload (hex)', hintText: '01 02'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: enabled ? _send : null,
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }

  Widget _logView() {
    final session = _session;
    if (session == null) {
      return const Center(child: Text('先绑定写/通知特征'));
    }
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.log.isEmpty) {
          return const Center(child: Text('等待收发…'));
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: session.clear,
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('清空'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: session.log.length,
                itemBuilder: (context, i) => _logTile(session.log[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _logTile(ProtocolLogEntry e) {
    final (color, icon) = switch (e.kind) {
      ProtocolLogKind.tx => (Colors.blue, Icons.north),
      ProtocolLogKind.rx => (Colors.green, Icons.south),
      ProtocolLogKind.error => (Colors.red, Icons.error_outline),
      ProtocolLogKind.info => (Colors.grey, Icons.info_outline),
    };
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 16, color: color),
      title: Text(e.text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
    );
  }
}
