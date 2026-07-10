import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:shakepin/app/main_drop/custom_drag_gesture.dart';
import 'package:shakepin/app/main_drop/dropped_item.dart';
import 'package:shakepin/state.dart';
import 'package:shakepin/utils/drop_channel.dart';
import 'package:shakepin/utils/logger.dart';
import 'package:shakepin/utils/shelf_text_merge.dart';
import 'package:shakepin/utils/utils.dart';
import 'package:shakepin/widgets/drop_target.dart';
import 'package:shakepin/widgets/file_image_widget.dart';
import 'package:shakepin/widgets/glass_button.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:url_launcher/url_launcher.dart';

class DropSection extends StatefulWidget {
  const DropSection({super.key});

  @override
  State<DropSection> createState() => _DropSectionState();
}

class _DropSectionState extends State<DropSection> with DragDropListener {
  bool _isDraggingItemIn = false;
  bool _isHoveredItem = false;
  bool _isHoveredControl = false;

  /// Dropover-style: collapsed stack by default; expand to browse items.
  bool _isExpanded = false;
  bool _isWindowTransitioning = false;
  int _windowTransitionRevision = 0;
  var _displayMode = DisplayMode.grid;
  String? draggedItem;

  /// True while a native drag-out session is active (shows a ghost silhouette).
  bool _isDraggingOut = false;

  /// Anchor index for Shift+click range selection (Finder-style).
  int? _selectionAnchorIndex;

  final Map<String, GlobalKey> _itemKeys = {};
  Timer? _mergeHoverTimer;
  String? _mergeDragSource;
  String? _mergeHoverTarget;
  Offset? _mergeDragPosition;
  bool _isMergeArmed = false;

  @override
  void initState() {
    dropChannel.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    super.initState();
  }

  /// Esc collapses details → stack. Space toggles Quick Look for selection.
  /// Stacked shelf only closes via the X button.
  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (!_isExpanded) {
        return true; // swallow Esc so it never dismisses the shelf
      }
      _setExpanded(false);
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (selectedItems().isEmpty) {
        return false;
      }
      _previewSelectedItems();
      return true;
    }

    return false;
  }

  /// Finder-style Space: Quick Look local files; open URLs in the browser.
  Future<void> _previewSelectedItems() async {
    final selected = selectedItems();
    if (selected.isEmpty) return;

    final itemList = items().toList();
    // Preserve shelf order so multi-select preview matches visual order.
    final ordered = itemList.where(selected.contains).toList();
    if (ordered.isEmpty) return;

    final urls = ordered.where(isUrl).toList();
    final files = ordered.where((p) => !isUrl(p)).toList();

    if (files.isNotEmpty) {
      await dropChannel.quickLook(files);
      return;
    }

    // Selection is URL-only — open the first one (Quick Look can't preview them).
    if (urls.isNotEmpty) {
      try {
        await launchUrl(Uri.parse(urls.first));
      } catch (e) {
        logger.log('Error opening URL preview: $e');
      }
    }
  }

  void _addPaths(List<String> paths) {
    if (paths.isEmpty) return;
    items.value = itemsWithNewestFirst(paths);
    selectedItems.value = selectedItems().union(paths.toSet());
  }

  /// Finder-style selection: click selects one item; Shift+click selects a range.
  void _selectItem(String filePath) {
    final itemList = items().toList();
    final index = itemList.indexOf(filePath);
    if (index < 0) return;

    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    final isTogglePressed = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    if (isShiftPressed && _selectionAnchorIndex != null) {
      final start =
          _selectionAnchorIndex! < index ? _selectionAnchorIndex! : index;
      final end =
          _selectionAnchorIndex! < index ? index : _selectionAnchorIndex!;
      selectedItems.value = itemList.sublist(start, end + 1).toSet();
    } else if (isTogglePressed) {
      final updatedSelection = Set<String>.from(selectedItems());
      if (!updatedSelection.add(filePath)) {
        updatedSelection.remove(filePath);
      }
      selectedItems.value = updatedSelection;
      _selectionAnchorIndex ??= index;
    } else {
      selectedItems.value = {filePath};
      _selectionAnchorIndex = index;
    }
  }

  List<String> get _orderedSelectedItems =>
      items().where(selectedItems().contains).toList();

  bool get _canMergeSelected =>
      _orderedSelectedItems.length >= 2 &&
      _orderedSelectedItems.every(isPlainTextShelfItem);

  Future<void> _mergeSelectedItems(String targetPath) async {
    final orderedSelection = _orderedSelectedItems;
    if (!orderedSelection.contains(targetPath) ||
        orderedSelection.length < 2 ||
        !orderedSelection.every(isPlainTextShelfItem)) {
      return;
    }

    try {
      final mergedPath = await mergeTextFiles(orderedSelection);
      if (!mounted) return;
      _replaceShelfItems(
        mergedPath: mergedPath,
        removedPaths: orderedSelection.toSet(),
        anchorPath: targetPath,
      );
    } catch (error) {
      logger.log('Unable to merge selected text items: $error');
    }
  }

  Future<void> _appendDraggedTextItems(String targetPath) async {
    final sources = _orderedSelectedItems
        .where((path) => path != targetPath && isPlainTextShelfItem(path))
        .toList();
    if (!isPlainTextShelfItem(targetPath) || sources.isEmpty) return;

    try {
      final mergedPath = await appendTextFilesToTarget(
        targetPath: targetPath,
        sourcePaths: sources,
      );
      if (!mounted) return;
      _replaceShelfItems(
        mergedPath: mergedPath,
        removedPaths: {...sources, targetPath},
        anchorPath: targetPath,
      );
    } catch (error) {
      logger.log('Unable to append dragged text items: $error');
    }
  }

  void _replaceShelfItems({
    required String mergedPath,
    required Set<String> removedPaths,
    required String anchorPath,
  }) {
    final nextItems = <String>[];
    var inserted = false;
    for (final itemPath in items()) {
      if (itemPath == anchorPath) {
        nextItems.add(mergedPath);
        inserted = true;
      }
      if (!removedPaths.contains(itemPath)) {
        nextItems.add(itemPath);
      }
    }
    if (!inserted) {
      nextItems.insert(0, mergedPath);
    }

    items.value = nextItems.toSet();
    selectedItems.value = {mergedPath};
    _selectionAnchorIndex = nextItems.indexOf(mergedPath);
    _itemKeys.removeWhere((path, _) => removedPaths.contains(path));
  }

  void _startMergeDrag(String sourcePath) {
    final selection = selectedItems();
    if (!selection.contains(sourcePath) ||
        !selection.every(isPlainTextShelfItem)) {
      selectedItems.value = {sourcePath};
      _selectionAnchorIndex = items().toList().indexOf(sourcePath);
    }
    setState(() {
      _mergeDragSource = sourcePath;
      _mergeHoverTarget = null;
      _mergeDragPosition = null;
      _isMergeArmed = false;
    });
  }

  void _updateMergeDrag(Offset globalPosition) {
    final sourcePath = _mergeDragSource;
    if (sourcePath == null) return;
    final renderObject = context.findRenderObject();
    final localPosition = renderObject is RenderBox && renderObject.attached
        ? renderObject.globalToLocal(globalPosition)
        : globalPosition;

    String? targetPath;
    for (final entry in _itemKeys.entries) {
      if (entry.key == sourcePath || !isPlainTextShelfItem(entry.key)) {
        continue;
      }
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final targetBounds =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (targetBounds.contains(globalPosition)) {
        targetPath = entry.key;
        break;
      }
    }

    final hasSource = _orderedSelectedItems
        .any((path) => path != targetPath && isPlainTextShelfItem(path));
    if (!hasSource) targetPath = null;
    if (targetPath == _mergeHoverTarget) {
      setState(() => _mergeDragPosition = localPosition);
      return;
    }

    _mergeHoverTimer?.cancel();
    setState(() {
      _mergeHoverTarget = targetPath;
      _mergeDragPosition = localPosition;
      _isMergeArmed = false;
    });

    if (targetPath == null) return;
    _mergeHoverTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || _mergeHoverTarget != targetPath) return;
      setState(() => _isMergeArmed = true);
    });
  }

  bool _shouldStartExternalDrag(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return true;
    final shelfBounds =
        renderObject.localToGlobal(Offset.zero) & renderObject.size;
    return !shelfBounds.contains(globalPosition);
  }

  void _finishMergeDrag(Offset globalPosition) {
    _updateMergeDrag(globalPosition);
    final targetPath = _isMergeArmed ? _mergeHoverTarget : null;
    _cancelMergeDrag();
    if (targetPath != null) {
      unawaited(_appendDraggedTextItems(targetPath));
    }
  }

  void _cancelMergeDrag() {
    _mergeHoverTimer?.cancel();
    _mergeHoverTimer = null;
    if (!mounted) return;
    setState(() {
      _mergeDragSource = null;
      _mergeHoverTarget = null;
      _mergeDragPosition = null;
      _isMergeArmed = false;
    });
  }

  Future<void> _setExpanded(bool expanded) async {
    if (_isExpanded == expanded || _isWindowTransitioning) return;

    if (appMode() != AppMode.pin && appMode() != AppMode.panel) {
      setState(() => _isExpanded = expanded);
      return;
    }

    final revision = ++_windowTransitionRevision;
    setState(() => _isWindowTransitioning = true);
    final size = expanded ? AppSizes.pinExpanded : AppSizes.pin;
    try {
      if (!expanded) {
        // Switch content and shrink the native window in the same 180 ms
        // interval, so the stack never sits inside the expanded frame.
        setState(() => _isExpanded = false);
      }

      if (!mounted || revision != _windowTransitionRevision) return;
      await dropChannel.setMinimumSize(size);
      final center = await dropChannel.center();
      await dropChannel.setFrame(
        Rect.fromCenter(
          center: center,
          width: size.width,
          height: size.height,
        ),
        animate: true,
      );

      if (!mounted || revision != _windowTransitionRevision) return;
      if (expanded) {
        // Let AppKit finish resizing before building icons and the detail list.
        setState(() {
          _isExpanded = true;
          _isWindowTransitioning = false;
        });
      }
    } finally {
      if (revision == _windowTransitionRevision) {
        if (mounted && _isWindowTransitioning) {
          setState(() => _isWindowTransitioning = false);
        } else {
          _isWindowTransitioning = false;
        }
      }
    }
  }

  Widget _buildViewToggle(BuildContext context) {
    final controlColor = MacosColors.controlColor.resolvedColor(context);
    final labelColor = MacosColors.labelColor.resolvedColor(context);

    Widget segment({
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
      required BorderRadius borderRadius,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Durations.short4,
          curve: Curves.easeOut,
          width: 28,
          height: 22,
          decoration: BoxDecoration(
            color: selected ? controlColor.withValues(alpha: 0.35) : null,
            borderRadius: borderRadius,
          ),
          child: Center(
            child: MacosIcon(
              icon,
              size: 13,
              color: labelColor.withValues(alpha: selected ? 0.9 : 0.55),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => _isHoveredControl = true,
      onExit: (_) => _isHoveredControl = false,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: controlColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              icon: FluentIcons.grid_16_regular,
              selected: _displayMode == DisplayMode.grid,
              onTap: () => setState(() => _displayMode = DisplayMode.grid),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(6),
              ),
            ),
            segment(
              icon: FluentIcons.text_bullet_list_ltr_16_regular,
              selected: _displayMode == DisplayMode.list,
              onTap: () => setState(() => _displayMode = DisplayMode.list),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      onEnter: (_) => _isHoveredControl = true,
      onExit: (_) => _isHoveredControl = false,
      child: SizedBox(
        width: 22,
        height: 22,
        child: GlassButton(
          secondary: true,
          padding: EdgeInsets.zero,
          radius: 11,
          onTap: onTap,
          child: MacosIcon(
            icon,
            color: MacosColors.labelColor
                .resolvedColor(context)
                .withValues(alpha: 0.75),
            size: 12,
          ),
        ),
      ),
    );
  }

  void _closeShelf() {
    _windowTransitionRevision++;
    _isWindowTransitioning = false;
    keepEmptyShelfVisible = false;
    setState(() {
      selectedItems.clear();
      _selectionAnchorIndex = null;
      _isExpanded = false;
      _isDraggingOut = false;
      _itemKeys.clear();
    });
    _cancelMergeDrag();
    // Clearing items synchronously invokes MainDropApp.itemListener, which is
    // the single owner of the window hide sequence.
    items.clear();
  }

  bool _isItemBeingDragged(String filePath) {
    if (!_isDraggingOut) return false;
    if (draggedItem != null) return draggedItem == filePath;
    return selectedItems().contains(filePath);
  }

  Widget _buildDroppedItem(String filePath) {
    final itemKey = _itemKeys.putIfAbsent(filePath, () => GlobalKey());
    final isMergeEnabled = _isExpanded && isPlainTextShelfItem(filePath);
    final isMergeSource = _mergeDragSource != null &&
        selectedItems().contains(filePath) &&
        filePath != _mergeHoverTarget &&
        isPlainTextShelfItem(filePath);
    final mergeItemCount = _mergeDragSource == null
        ? 0
        : selectedItems()
            .where(
              (path) => path != _mergeHoverTarget && isPlainTextShelfItem(path),
            )
            .length;
    return RepaintBoundary(
      key: itemKey,
      child: DroppedItem(
        key: ValueKey(filePath),
        displayMode: _displayMode,
        onDragStart: () {
          setState(() => _isDraggingOut = true);
          if (!selectedItems().contains(filePath)) {
            draggedItem = filePath;
            dropChannel.performDragSession([filePath]);
          } else {
            dropChannel.performDragSession(selectedItems().toList());
          }
        },
        onEnter: () {
          // No setState — avoids rebuild flicker while hovering icons.
          _isHoveredItem = true;
        },
        onExit: () {
          _isHoveredItem = false;
        },
        onRemove: () {
          onRemove(filePath);
        },
        path: filePath,
        isSelected: selectedItems().contains(filePath),
        isBeingDragged: _isItemBeingDragged(filePath),
        onSelect: () => _selectItem(filePath),
        isHoveredItem: _isHoveredItem,
        canMergeSelected:
            _canMergeSelected && selectedItems().contains(filePath),
        onMergeSelected: _canMergeSelected && selectedItems().contains(filePath)
            ? () => _mergeSelectedItems(filePath)
            : null,
        onInternalDragStart:
            isMergeEnabled ? () => _startMergeDrag(filePath) : null,
        onInternalDragUpdate: isMergeEnabled ? _updateMergeDrag : null,
        onInternalDragEnd: isMergeEnabled ? _finishMergeDrag : null,
        onInternalDragCancel: isMergeEnabled ? _cancelMergeDrag : null,
        shouldStartExternalDrag:
            isMergeEnabled ? _shouldStartExternalDrag : null,
        isMergeDragging: isMergeSource,
        isMergeTarget: _mergeHoverTarget == filePath,
        isMergeArmed: _isMergeArmed && _mergeHoverTarget == filePath,
        mergeItemCount: mergeItemCount,
      ),
    );
  }

  /// Dropover-style stacked pile: icons overlap; drag moves the whole bundle.
  Widget _buildStackedBundle(BuildContext context) {
    final paths = items().toList();
    final count = paths.length;
    final visibleCount = count.clamp(0, 3);
    final labelColor = MacosColors.labelColor.resolvedColor(context);
    final cardColor = MacosTheme.brightnessOf(context).isDark
        ? MacosColors.controlBackgroundColor.resolvedColor(context)
        : Colors.white;
    final isLifted = _isDraggingOut;
    final shadowColor = Colors.black.withValues(
      alpha: isLifted ? 0.22 : 0.08,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CustomDragGesture(
          onDragStart: () {
            setState(() {
              _isDraggingOut = true;
              draggedItem = null;
            });
            selectedItems.value = Set.from(paths);
            dropChannel.performDragSession(paths);
          },
          child: MouseRegion(
            onEnter: (_) => _isHoveredItem = true,
            onExit: (_) => _isHoveredItem = false,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              // Leave a faint silhouette while the OS drag preview follows the cursor.
              opacity: _isDraggingOut ? 0.28 : 1,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                scale: isLifted ? 1.08 : 1,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  offset: isLifted ? const Offset(0, -0.06) : Offset.zero,
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Newest-first list: draw older cards first so the newest sits on top.
                        for (var i = 0; i < visibleCount; i++)
                          Transform.translate(
                            offset: Offset(
                              (i - (visibleCount - 1) / 2) * 6,
                              (i - (visibleCount - 1) / 2) * -5,
                            ),
                            child: Transform.rotate(
                              angle: (i - (visibleCount - 1) / 2) * 0.06 +
                                  (isLifted ? 0.02 : 0),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: shadowColor,
                                      blurRadius: isLifted ? 22 : 8,
                                      spreadRadius: isLifted ? 1 : 0,
                                      offset: Offset(0, isLifted ? 10 : 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: isUrl(paths[visibleCount - 1 - i])
                                      ? MacosIcon(
                                          FluentIcons.link_16_regular,
                                          color: labelColor,
                                          size: 32,
                                        )
                                      : FileImageWidget(
                                          path: paths[visibleCount - 1 - i],
                                          size: 40,
                                        ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        MouseRegion(
          onEnter: (_) => _isHoveredControl = true,
          onExit: (_) => _isHoveredControl = false,
          child: GestureDetector(
            onTap: () => _setExpanded(true),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: _isDraggingOut ? 0.35 : 1,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: MacosColors.controlColor
                      .resolvedColor(context)
                      .withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count 档 ›',
                  style: TextStyle(
                    fontSize: 12,
                    color: labelColor.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedItems(BuildContext context, Color borderColor) {
    const maxRowItemLength = 3;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      child: switch (_displayMode) {
        DisplayMode.list => SuperListView.separated(
            key: const ValueKey('list'),
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            itemCount: items().length,
            separatorBuilder: (context, index) => Divider(
              indent: 8,
              endIndent: 8,
              height: 1,
              color: borderColor,
            ),
            itemBuilder: (context, index) {
              final filePath = items().elementAt(index);
              return _buildDroppedItem(filePath);
            },
          ),
        _ => SuperListView.builder(
            key: const ValueKey('grid'),
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            itemCount: (items().length / maxRowItemLength).ceil(),
            itemBuilder: (context, rowIndex) {
              final startIndex = rowIndex * maxRowItemLength;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  spacing: 4,
                  children: List.generate(maxRowItemLength, (index) {
                    final itemIndex = startIndex + index;
                    if (itemIndex < items().length) {
                      final filePath = items().elementAt(itemIndex);
                      return Expanded(
                        child: _buildDroppedItem(filePath),
                      );
                    }
                    return const Expanded(
                      child: SizedBox.shrink(),
                    );
                  }),
                ),
              );
            },
          ),
      },
    );
  }

  @override
  void onDragSessionEnded(DropOperation operation) {
    // Always clear lift/ghost state first so a cancelled drag never sticks.
    if (operation == DropOperation.move) {
      setState(() {
        _isDraggingOut = false;
        if (draggedItem != null) {
          logger.log('Removing dragged item: $draggedItem');
          selectedItems.value = Set.from(selectedItems())..remove(draggedItem!);
          items.remove(draggedItem!);
          draggedItem = null;
        } else {
          logger.log('Moving selected items: ${selectedItems().length}');
          items.value = items().difference(selectedItems());
          selectedItems.value = {};
        }
      });
      logger.log('Items after move: ${items().length}');
    } else {
      setState(() {
        _isDraggingOut = false;
        draggedItem = null;
      });
    }
    super.onDragSessionEnded(operation);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MacosTheme.brightnessOf(context).isDark;
    // Match native window fill so no gray “frame” shows around the panel.
    final surfaceColor = isDark
        ? MacosColors.controlBackgroundColor.resolvedColor(context)
        : const Color(0xFFF2F2F2);
    final borderColor = MacosColors.systemGrayColor
        .resolvedColor(context)
        .withValues(alpha: isDark ? 0.35 : 0.2);
    final cornerRadius = appMode() == AppMode.pin ? 32.0 : 12.0;
    final mergeDragSource = _mergeDragSource;
    final mergeDragPosition = _mergeDragPosition;
    final mergeDragCount = mergeDragSource == null
        ? 0
        : selectedItems().where(isPlainTextShelfItem).length;

    return DropTarget(
      label: 'main-drop-app',
      onDragEnter: (details) {
        setState(() {
          _isDraggingItemIn = true;
        });
      },
      onDragExited: () {
        setState(() {
          _isDraggingItemIn = false;
        });
      },
      onDragConclude: () {
        dropChannel.hidePopover();
        setState(() {
          _isDraggingItemIn = false;
        });
      },
      onDragPerform: (paths) async {
        _addPaths(paths);
      },
      child: SizedBox(
        width: switch (appMode()) {
          AppMode.pin || AppMode.panel => MediaQuery.sizeOf(context).width,
          _ => MediaQuery.sizeOf(context).width - 64,
        },
        height: switch (appMode()) {
          AppMode.minify => null,
          AppMode.pin || AppMode.panel => MediaQuery.sizeOf(context).height,
          _ => MediaQuery.sizeOf(context).height - 16,
        },
        child: IgnorePointer(
          ignoring: _isWindowTransitioning,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              // Start a native window drag once per primary-button gesture.
              if (event.buttons == kPrimaryMouseButton &&
                  !_isHoveredItem &&
                  !_isHoveredControl) {
                dropChannel.startDragging();
              }
            },
            child: AnimatedContainer(
              clipBehavior: Clip.hardEdge,
              duration: Durations.long2,
              curve: Curves.fastEaseInToSlowEaseOut,
              // No border — drag-in only tints the surface.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(cornerRadius),
                color: _isDraggingItemIn
                    ? MacosColors.controlAccentColor.withValues(alpha: 0.08)
                    : surfaceColor,
              ),
              child: ListenableBuilder(
                listenable: Listenable.merge([items, selectedItems]),
                builder: (context, child) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        children: [
                          SizedBox(
                            // Keep controls clear of the 32px corner curve so the
                            // top-left radius isn't visually "bitten" by the button.
                            height: 40,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 14, 0),
                              child: Row(
                                children: [
                                  if (_isExpanded && items().isNotEmpty)
                                    _buildHeaderButton(
                                      icon: FluentIcons.chevron_up_16_regular,
                                      onTap: () => _setExpanded(false),
                                    )
                                  else
                                    _buildHeaderButton(
                                      icon: FluentIcons.dismiss_16_regular,
                                      onTap: _closeShelf,
                                    ),
                                  const Spacer(),
                                  if (items().isNotEmpty) ...[
                                    if (_isExpanded)
                                      _buildViewToggle(context)
                                    else
                                      _buildHeaderButton(
                                        icon:
                                            FluentIcons.chevron_down_16_regular,
                                        onTap: () => _setExpanded(true),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (items().isNotEmpty)
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: _isExpanded
                                    ? KeyedSubtree(
                                        key: const ValueKey('expanded'),
                                        child: _buildExpandedItems(
                                          context,
                                          borderColor,
                                        ),
                                      )
                                    : KeyedSubtree(
                                        key: const ValueKey('stacked'),
                                        child: _buildStackedBundle(context),
                                      ),
                              ),
                            )
                          else
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.all(16).copyWith(top: 0),
                                child: Center(
                                  child: AnimatedDefaultTextStyle(
                                    duration: Durations.long2,
                                    curve: Curves.fastEaseInToSlowEaseOut,
                                    style: TextStyle(
                                      color: _isDraggingItemIn
                                          ? MacosColors.controlAccentColor
                                          : MacosColors.secondaryLabelColor
                                              .resolvedColor(context),
                                      fontSize: 13,
                                    ),
                                    child: const Text('放置或粘贴你的内容项'),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (mergeDragSource != null && mergeDragPosition != null)
                        Positioned(
                          left: mergeDragPosition.dx - 22,
                          top: mergeDragPosition.dy - 22,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 0.78,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: MacosColors.controlBackgroundColor
                                          .resolvedColor(context)
                                          .withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(9),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.22),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: FileImageWidget(
                                      path: mergeDragSource,
                                      size: 34,
                                    ),
                                  ),
                                  if (mergeDragCount > 1)
                                    Positioned(
                                      right: -6,
                                      top: -6,
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '$mergeDragCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void onRemove(String path) {
    items.remove(path);
    selectedItems.value = Set.from(selectedItems())..remove(path);
    _itemKeys.remove(path);
    _selectionAnchorIndex = null;
    if (items().isEmpty && _isExpanded) {
      setState(() => _isExpanded = false);
    }
  }

  @override
  void dispose() {
    _mergeHoverTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    dropChannel.removeListener(this);
    super.dispose();
  }
}

enum DisplayMode {
  grid,
  list,
}
