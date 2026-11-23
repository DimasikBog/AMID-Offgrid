import 'package:flutter/material.dart';

class OfflineTiles extends StatelessWidget {
  const OfflineTiles({
    super.key,
    required this.path,
    this.minZoom = 0,
    this.maxZoom = 20,
  });
  final String path;
  final double minZoom, maxZoom;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
