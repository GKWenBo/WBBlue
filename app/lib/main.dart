import 'package:flutter/material.dart';

import 'features/scan/scan_page.dart';

void main() {
  runApp(const WbBleApp());
}

class WbBleApp extends StatelessWidget {
  const WbBleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WB BLE',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const ScanPage(),
    );
  }
}
