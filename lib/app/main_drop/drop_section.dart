import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:shakepin/app/main_drop/custom_drag_gesture.dart';
import 'package:shakepin/app/main_drop/dropped_item.dart';
import 'package:shakepin/state.dart';
import 'package:shakepin/utils/drop_channel.dart';
import 'package:shakepin/utils/logger.dart';
import 'package:shakepin/utils/utils.dart';
import 'package:shakepin/widgets/drop_target.dart';
import 'package:shakepin/widgets/file_image_widget.dart';
import 'package:shakepin/widgets/glass_button.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

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
  var _displayMode = DisplayMode.grid;
  String? draggedItem;

  /// Anchor index for Shift+click range selection (Finder-style).
  int? _selectionAnchorIndex;

  @override
  void initState() {
    dropChannel.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    super.initState();
  }

  /// Esc collapses details → stack. Stacked shelf only closes via the X button.
  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!_isExpanded) return true; // swallow Esc so it never dismisses the shelf
    _setExpanded(false);
    return true;
  }

  void _addPaths(List<String> paths) {
    if (paths.isEmpty) return;
    items.value = items().union(paths.toSet());
    selectedItems.value = selectedItems().union(paths.toSet());
  }

  /// Finder-style selection: click selects one item; Shift+click selects a range.
  void _selectItem(String filePath) {
    final itemList = items().toList();
    final index = itemList.indexOf(filePath);
    if (index < 0) return;

    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    setState(() {
      if (isShiftPressed && _selectionAnchorIndex != null) {
        final start =
            _selectionAnchorIndex! < index ? _selectionAnchorIndex! : index;
        final end =
            _selectionAnchorIndex! < index ? index : _selectionAnchorIndex!;
        selectedItems.value = itemList.sublist(start, end + 1).toSet();
      } else {
        selectedItems.value = {filePath};
        _selectionAnchorIndex = index;
      }
    });
  }

  Future<void> _setExpanded(bool expanded) async {
    if (_isExpanded == expanded) return;
    setState(() => _isExpanded = expanded);

    if (appMode() != AppMode.pin && appMode() != AppMode.panel) return;

    final size = expanded ? AppSizes.pinExpanded : AppSizes.pin;
    dropChannel.setMinimumSize(size);
    final center = await dropChannel.center();
    await dropChannel.setFrame(
      Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      ),
      animate: true,
    );
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
    keepEmptyShelfVisible = false;
    setState(() {
      selectedItems.clear();
      _selectionAnchorIndex = null;
      _isExpanded = false;
    });
    items.clear();
    resetFrameAndHide();
  }

  Widget _buildDroppedItem(String filePath) {
    return DroppedItem(
      displayMode: _displayMode,
      onDragStart: () {
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
      onSelect: () => _selectItem(filePath),
      isHoveredItem: _isHoveredItem,
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
    final shadowColor = Colors.black.withValues(alpha: 0.08);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CustomDragGesture(
          onDragStart: () {
            draggedItem = null;
            selectedItems.value = Set.from(paths);
            dropChannel.performDragSession(paths);
          },
          child: MouseRegion(
            onEnter: (_) => _isHoveredItem = true,
            onExit: (_) => _isHoveredItem = false,
            cursor: SystemMouseCursors.grab,
            child: SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (var i = 0; i < visibleCount; i++)
                    Transform.translate(
                      offset: Offset(
                        (i - (visibleCount - 1) / 2) * 6,
                        (i - (visibleCount - 1) / 2) * -5,
                      ),
                      child: Transform.rotate(
                        angle: (i - (visibleCount - 1) / 2) * 0.06,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: shadowColor,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: isUrl(paths[count - visibleCount + i])
                                ? MacosIcon(
                                    FluentIcons.link_16_regular,
                                    color: labelColor,
                                    size: 32,
                                  )
                                : FileImageWidget(
                                    path: paths[count - visibleCount + i],
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
        const SizedBox(height: 10),
        MouseRegion(
          onEnter: (_) => _isHoveredControl = true,
          onExit: (_) => _isHoveredControl = false,
          child: GestureDetector(
            onTap: () => _setExpanded(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      ],
    );
  }

  Widget _buildExpandedItems(BuildContext context, Color borderColor) {
    const maxRowItemLength = 3;
    return AnimatedSwitcher(
      duration: Durations.medium2,
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
    switch (operation) {
      case DropOperation.move:
        setState(() {
          if (draggedItem != null) {
            logger.log('Removing dragged item: $draggedItem');
            selectedItems.value = Set.from(selectedItems())
              ..remove(draggedItem!);
            items.remove(draggedItem!);
            draggedItem = null;
          } else {
            logger.log('Moving selected items: ${selectedItems().length}');
            items.value = items().difference(selectedItems());
            selectedItems.value = {};
          }
        });
        logger.log('Items after move: ${items().length}');
      default:
        break;
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
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerMove: (_) {
            // Window drag from empty areas; skip when over items/controls.
            if (!_isHoveredItem && !_isHoveredControl) {
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
                return Column(
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
                                  icon: FluentIcons.chevron_down_16_regular,
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
                          duration: Durations.medium2,
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
                          padding: const EdgeInsets.all(16).copyWith(top: 0),
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void onRemove(String path) {
    items.remove(path);
    selectedItems.value = Set.from(selectedItems())..remove(path);
    _selectionAnchorIndex = null;
    if (items().isEmpty && _isExpanded) {
      setState(() => _isExpanded = false);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    dropChannel.removeListener(this);
    super.dispose();
  }
}

enum DisplayMode {
  grid,
  list,
}
