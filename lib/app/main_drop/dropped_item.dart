import 'dart:io';

import 'package:extended_text/extended_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:shakepin/app/main_drop/custom_drag_gesture.dart';
import 'package:shakepin/app/main_drop/drop_section.dart';
import 'package:shakepin/state.dart';
import 'package:shakepin/utils/cli.dart';
import 'package:shakepin/utils/drop_channel.dart';
import 'package:shakepin/utils/logger.dart';
import 'package:shakepin/utils/utils.dart';
import 'package:shakepin/widgets/file_image_widget.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

class DroppedItem extends StatefulWidget {
  const DroppedItem({
    super.key,
    required this.path,
    required this.onDragStart,
    required this.onSelect,
    required this.onRemove,
    required this.isSelected,
    required this.isHoveredItem,
    required this.onEnter,
    required this.onExit,
    required this.displayMode,
    this.isBeingDragged = false,
    this.canMergeSelected = false,
    this.onMergeSelected,
    this.onInternalDragStart,
    this.onInternalDragUpdate,
    this.onInternalDragEnd,
    this.onInternalDragCancel,
    this.shouldStartExternalDrag,
    this.isMergeDragging = false,
    this.isMergeTarget = false,
    this.isMergeArmed = false,
    this.mergeItemCount = 0,
  });

  final String path;
  final VoidCallback onDragStart;
  final VoidCallback onSelect;
  final VoidCallback onRemove;
  final bool isSelected;
  final bool isHoveredItem;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final DisplayMode displayMode;
  final bool isBeingDragged;
  final bool canMergeSelected;
  final VoidCallback? onMergeSelected;
  final VoidCallback? onInternalDragStart;
  final ValueChanged<Offset>? onInternalDragUpdate;
  final ValueChanged<Offset>? onInternalDragEnd;
  final VoidCallback? onInternalDragCancel;
  final bool Function(Offset globalPosition)? shouldStartExternalDrag;
  final bool isMergeDragging;
  final bool isMergeTarget;
  final bool isMergeArmed;
  final int mergeItemCount;

  @override
  State<DroppedItem> createState() => _DroppedItemState();
}

class _DroppedItemState extends State<DroppedItem> {
  DateTime? _lastTapAt;
  String _fileSize = '';

  @override
  void initState() {
    appMode.addListener(appModeListener);
    super.initState();
    _loadFileSize();
  }

  @override
  void didUpdateWidget(covariant DroppedItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.displayMode != widget.displayMode) {
      _fileSize = '';
      _loadFileSize();
    }
  }

  @override
  void dispose() {
    appMode.removeListener(appModeListener);
    super.dispose();
  }

  void appModeListener() {
    setState(() {});
  }

  Future<void> _loadFileSize() async {
    if (widget.displayMode != DisplayMode.list || isUrl(widget.path)) return;

    final requestedPath = widget.path;
    try {
      final size = await File(requestedPath).length();
      if (!mounted || widget.path != requestedPath) return;
      setState(() => _fileSize = formatFileSize(size));
    } on FileSystemException {
      if (!mounted || widget.path != requestedPath) return;
      setState(() => _fileSize = '');
    }
  }

  bool get isDisabled => !appMode().isFileCompatible(widget.path);

  bool get _isLifted => widget.isBeingDragged || widget.isMergeDragging;

  Color _selectionFill(BuildContext context) {
    final isDark = MacosTheme.brightnessOf(context).isDark;
    // Keep the same RGB channels at both ends of the animation. Tweening from
    // Colors.transparent would interpolate from transparent black and create
    // a dark-gray flash in the middle frames.
    if (isDark) {
      return Colors.white.withValues(alpha: widget.isSelected ? 0.14 : 0);
    }
    return widget.isSelected
        ? const Color(0xFFE5E5E5)
        : const Color(0x00E5E5E5);
  }

  /// Opens with the default app (files) or the system browser (URLs).
  Future<void> _openWithDefaultApp() async {
    try {
      if (isUrl(widget.path)) {
        final uri = Uri.parse(widget.path);
        if (!await launchUrl(uri)) {
          throw Exception('launchUrl returned false for ${widget.path}');
        }
        return;
      }
      final result = await cli.run('open', [widget.path]);
      if (result.exitCode != 0) {
        throw Exception(result.stderr);
      }
    } catch (e) {
      logger.log('Error opening item: $e');
    }
  }

  /// Select immediately on tap; open on a second tap within the double-click
  /// window. Avoids Flutter's onTap/onDoubleTap gesture arena delay (~300ms).
  void _handleTap() {
    final now = DateTime.now();
    final last = _lastTapAt;
    _lastTapAt = now;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 300)) {
      _lastTapAt = null;
      _openWithDefaultApp();
      return;
    }
    widget.onSelect();
  }

  @override
  Widget build(BuildContext context) {
    menuProvider(request) => Menu(
          children: [
            MenuAction(
              title: 'Open',
              callback: () {
                _openWithDefaultApp();
              },
            ),
            MenuAction(
              title: 'Show in Finder',
              callback: () async {
                try {
                  final result = await cli.run('open', ['-R', widget.path]);
                  if (result.exitCode != 0) {
                    throw Exception(result.stderr);
                  }
                } catch (e) {
                  logger.log('Error revealing file: $e');
                }
              },
            ),
            if (widget.canMergeSelected && widget.onMergeSelected != null)
              MenuAction(
                title: '合并文本',
                callback: widget.onMergeSelected!,
              ),
            MenuAction(
              title: 'Remove',
              callback: () {
                widget.onRemove();
              },
            ),
          ],
        );

    final labelColor = MacosColors.labelColor.resolveFrom(context);
    final secondaryColor =
        MacosColors.secondaryLabelColor.resolvedColor(context);

    Widget child;
    final iconSize = widget.displayMode == DisplayMode.list ? 20.0 : 48.0;
    final icon = isUrl(widget.path)
        ? SizedBox(
            width: iconSize,
            height: iconSize,
            child: MacosIcon(
              CupertinoIcons.link,
              color: labelColor,
              size: widget.displayMode == DisplayMode.list ? 16 : 40,
            ),
          )
        : FileImageWidget(path: widget.path, size: iconSize);

    if (widget.displayMode == DisplayMode.list) {
      final fileName =
          isUrl(widget.path) ? widget.path : path.basename(widget.path);

      child = GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _selectionFill(context),
            borderRadius: BorderRadius.circular(8),
            border: widget.isMergeArmed
                ? Border.all(
                    color: MacosColors.controlAccentColor,
                    width: 2,
                  )
                : widget.isMergeTarget
                    ? Border.all(
                        color: MacosColors.controlAccentColor
                            .withValues(alpha: 0.55),
                      )
                    : null,
            boxShadow: (_isLifted || widget.isMergeArmed)
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 20,
                child: icon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 12,
                    color: labelColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _fileSize,
                style: TextStyle(
                  fontSize: 11,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final fileName =
          isUrl(widget.path) ? widget.path : path.basename(widget.path);

      child = GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 88,
          decoration: BoxDecoration(
            color: _selectionFill(context),
            borderRadius: BorderRadius.circular(10),
            border: widget.isMergeArmed
                ? Border.all(
                    color: MacosColors.controlAccentColor,
                    width: 2,
                  )
                : widget.isMergeTarget
                    ? Border.all(
                        color: MacosColors.controlAccentColor
                            .withValues(alpha: 0.55),
                      )
                    : null,
            boxShadow: (_isLifted || widget.isMergeArmed)
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Stack(
            children: [
              Opacity(
                opacity: isDisabled ? 0.2 : 1,
                child: Column(
                  children: [
                    Expanded(
                      child: Center(child: icon),
                    ),
                    SizedBox(
                      height: 16,
                      width: double.infinity,
                      child: ExtendedText(
                        fileName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: labelColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        overflowWidget: TextOverflowWidget(
                          position: TextOverflowPosition.middle,
                          align: TextOverflowAlign.center,
                          child: Text(
                            '…',
                            style: TextStyle(
                              fontSize: 11,
                              color: labelColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isDisabled)
                Positioned.fill(
                  child: MacosIcon(
                    CupertinoIcons.eye_slash,
                    color: MacosColors.systemRedColor.resolveFrom(context),
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (widget.isMergeArmed) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: MacosColors.controlAccentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              widget.mergeItemCount > 1
                  ? '合并 ${widget.mergeItemCount} 段文本'
                  : '合并文本',
              style: const TextStyle(
                fontSize: 10,
                color: MacosColors.controlAccentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return CustomDragGesture(
      onDragStart: widget.onDragStart,
      onInternalDragStart: widget.onInternalDragStart,
      onInternalDragUpdate: widget.onInternalDragUpdate,
      onInternalDragEnd: widget.onInternalDragEnd,
      onInternalDragCancel: widget.onInternalDragCancel,
      shouldStartExternalDrag: widget.shouldStartExternalDrag,
      child: ContextMenuWidget(
        menuProvider: menuProvider,
        child: MouseRegion(
          onEnter: (_) => widget.onEnter(),
          onExit: (_) {
            widget.onExit();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!widget.isHoveredItem) {
                dropChannel.hidePopover();
              }
            });
          },
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            // Ghost silhouette while the OS drag preview follows the cursor.
            opacity: widget.isBeingDragged
                ? 0.28
                : widget.isMergeDragging
                    ? 0.45
                    : 1,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              scale: _isLifted
                  ? 1.06
                  : widget.isMergeArmed
                      ? 1.04
                      : 1,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                offset: _isLifted ? const Offset(0, -0.04) : Offset.zero,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
