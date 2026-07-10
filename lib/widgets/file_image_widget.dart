import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:shakepin/utils/drop_channel.dart';
import 'package:shakepin/utils/logger.dart';

class FileImageWidget extends StatefulWidget {
  const FileImageWidget({
    super.key,
    required this.path,
    this.size = 62,
  });

  final String path;
  final double size;

  @override
  State<FileImageWidget> createState() => _FileImageWidgetState();
}

class _FileImageWidgetState extends State<FileImageWidget> {
  Uint8List? _iconData;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(covariant FileImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _iconData = null;
      _loadIcon();
    }
  }

  Future<void> _loadIcon() async {
    final requestedPath = widget.path;
    try {
      final iconData = await dropChannel.getFileIcon(requestedPath);
      if (mounted && widget.path == requestedPath) {
        setState(() {
          _iconData = iconData;
        });
      }
    } catch (e) {
      logger.log('Error loading file icon: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_iconData == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(child: ProgressCircle()),
      );
    }

    final cacheSize =
        (widget.size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return RepaintBoundary(
      child: Image.memory(
        _iconData!,
        width: widget.size,
        height: widget.size,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return const ProgressCircle();
        },
      ),
    );
  }
}
