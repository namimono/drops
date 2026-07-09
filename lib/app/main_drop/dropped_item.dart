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

  @override
  State<DroppedItem> createState() => _DroppedItemState();
}

class _DroppedItemState extends State<DroppedItem> {
  @override
  void initState() {
    appMode.addListener(appModeListener);
    super.initState();
  }

  @override
  void dispose() {
    appMode.removeListener(appModeListener);
    super.dispose();
  }

  void appModeListener() {
    setState(() {});
  }

  bool get isDisabled => !appMode().isFileCompatible(widget.path);

  Color _selectionFill(BuildContext context) {
    if (!widget.isSelected) return Colors.transparent;
    final isDark = MacosTheme.brightnessOf(context).isDark;
    // Light gray selection only — no hover background.
    return isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFE5E5E5);
  }

  @override
  Widget build(BuildContext context) {
    menuProvider(request) => Menu(
          children: [
            MenuAction(
              title: 'Show in Finder',
              callback: () async {
                try {
                  final result = await cli.run('open', ['-R', widget.path]);
                  if (result.exitCode != 0) {
                    throw Exception(result.stderr);
                  }
                } catch (e) {
                  logger.log('Error opening file: $e');
                }
              },
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
      final file = File(widget.path);
      final fileName =
          isUrl(widget.path) ? widget.path : path.basename(widget.path);
      final fileSize =
          file.existsSync() ? formatFileSize(file.lengthSync()) : '';

      child = GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          decoration: BoxDecoration(
            color: _selectionFill(context),
            borderRadius: BorderRadius.circular(8),
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
                fileSize,
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
      final fileName = isUrl(widget.path)
          ? widget.path
          : path.basename(widget.path);

      child = GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: _selectionFill(context),
            borderRadius: BorderRadius.circular(10),
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

    return CustomDragGesture(
      onDragStart: widget.onDragStart,
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
          child: child,
        ),
      ),
    );
  }
}
