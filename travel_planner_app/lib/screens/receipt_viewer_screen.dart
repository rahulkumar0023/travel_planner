import 'dart:io';
import 'package:flutter/material.dart';

class ReceiptViewerScreen extends StatelessWidget {
  const ReceiptViewerScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final f = File(path);
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      backgroundColor: Colors.black,
      body: f.existsSync()
          ? Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.file(f),
              ),
            )
          : const Center(child: Text('File not found', style: TextStyle(color: Colors.white70))),
    );
  }
}
