import 'package:flutter/material.dart';
import 'package:shakepin/app/about_app.dart';
import 'package:shakepin/app/crop_app.dart';

import 'package:shakepin/app/sections/archive_section/archive_section.dart';
import 'package:shakepin/app/main_drop/drop_section.dart';
import 'package:shakepin/app/main_drop/main_sidebar.dart';
import 'package:shakepin/app/sections/minify_section/minify_section.dart';
import 'package:shakepin/app/sections/misc_section/misc_section.dart';
import 'package:shakepin/app/setup_app.dart';
import 'package:shakepin/utils/drop_channel.dart';
import 'package:shakepin/utils/logger.dart';
import 'package:shakepin/utils/utils.dart';

import '../state.dart';

final dropSectionKey = GlobalKey();

class MainDropApp extends StatefulWidget {
  const MainDropApp({super.key});

  @override
  State<MainDropApp> createState() {
    return _MainDropAppState();
  }
}

class _MainDropAppState extends State<MainDropApp> with DragDropListener {
  var isShakeDetected = false;

  bool get _showSidebar => switch (appMode()) {
        AppMode.pin || AppMode.panel => false,
        _ => true,
      };

  @override
  void initState() {
    logger.log('_MainDropAppState: initState');
    dropChannel.addListener(this);

    items.addListener(itemListener);

    super.initState();
  }

  @override
  void dispose() {
    logger.log('Disposing _MainDropAppState');
    dropChannel.removeListener(this);
    items.removeListener(itemListener);
    super.dispose();
  }

  void itemListener() {
    logger.log('Items changed: ${items().length} items');
    if (items().isNotEmpty) {
      keepEmptyShelfVisible = false;
      return;
    }
    // Empty after user cleared items: hide. Keep visible if shelf was just invoked.
    if (keepEmptyShelfVisible) {
      logger.log('Items empty but shelf invoked empty — keeping visible');
      return;
    }
    logger.log('Items empty, resetting frame and hiding');
    // Do not call handleDefaultMode here: it starts a competing 200×200
    // window animation while resetFrameAndHide is shrinking to 200×48.
    appMode.value = AppMode.pin;
    resetFrameAndHide();
  }

  @override
  void shakeDetected(Offset position) async {
    logger.log('Shake detected at position: $position');
    if (isShakeDetected) return;
    isShakeDetected = true;
    await _invokeShelfAt(position);
    super.shakeDetected(position);
  }

  @override
  void shelfInvoked(Offset position) async {
    logger.log('Global shortcut invoked shelf at position: $position');
    await _invokeShelfAt(position);
    super.shelfInvoked(position);
  }

  Future<void> _invokeShelfAt(Offset position) async {
    cancelPendingWindowHide();
    keepEmptyShelfVisible = items().isEmpty;

    // Dropover-style: always show the pin content box on invoke.
    if (appMode() != AppMode.pin) {
      await handleModeChanged(AppMode.pin, force: true);
    }
    const appSize = AppSizes.pin;

    await dropChannel.setFrame(
      Rect.fromCenter(
        center: position + Offset(0, appSize.height / 2),
        width: appSize.width,
        height: appSize.height,
      ),
      animate: false,
    );
    await dropChannel.setVisible(true);
  }

  @override
  void onDragConclude() async {
    // logger.log('Drag concluded');
    isShakeDetected = false;

    Future.delayed(const Duration(milliseconds: 100), () {
      logger.log('Post-frame callback: checking items');
      if (items().isEmpty && !keepEmptyShelfVisible) {
        logger.log('No items, resetting frame');
        resetFrameAndHide();
      }
    });

    // Forces addPostFrameCallback to run
    setState(() {});
    super.onDragConclude();
  }

  void _handleShowTooltip(String tooltip) {
    // logger.log('Showing tooltip: $tooltip');

    // setState(() {
    //   _isShowingTooltip = true;
    // });
    // // dropChannel.showPopover(tooltip, edge: PopoverEdge.right);
  }

  void _handleHideTooltip() {
    // logger.log('Hiding tooltip');
    // _isShowingTooltip = false;
    // Future.delayed(const Duration(milliseconds: 700), () {
    //   if (!_isShowingTooltip) {
    //     logger.log('Tooltip still not showing, hiding popover');
    //     // dropChannel.hidePopover();
    //   } else {
    //     logger.log('Tooltip is showing again, not hiding popover');
    //   }
    // });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        isAboutApp,
        isSetupApp,
        isCropApp,
      ]),
      builder: (context, _) {
        return Stack(
          children: [
            Offstage(
              offstage: isAboutApp() || isSetupApp(),
              // Removed nested SingleChildScrollView wrappers to avoid giving descendants unbounded constraints.
              // Use a bounded SizedBox with MediaQuery sizes and a MouseRegion to preserve hover behavior.
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width,
                height: MediaQuery.sizeOf(context).height,
                child: ListenableBuilder(
                  listenable: appMode,
                  builder: (context, _) {
                    final dropSection = DropSection(
                      key: dropSectionKey,
                    );
                    final showSidebar = _showSidebar;
                    final contentWidth = showSidebar
                        ? MediaQuery.sizeOf(context).width - 48 - 8
                        : MediaQuery.sizeOf(context).width;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Expanded(
                          child: switch (appMode()) {
                            AppMode.pin || AppMode.panel => SizedBox(
                                width: contentWidth,
                                height: MediaQuery.sizeOf(context).height,
                                // Edge-to-edge: padding here looked like a thick gray border
                                // against the native visual-effect backdrop.
                                child: dropSection,
                              ),
                            AppMode.minify => SizedBox(
                                width: contentWidth,
                                height: MediaQuery.sizeOf(context).height,
                                child: MinifySection(
                                  dropSection: dropSection,
                                ),
                              ),
                            AppMode.archive => SizedBox(
                                width: contentWidth,
                                height: MediaQuery.sizeOf(context).height,
                                child: ArchiveSection(
                                  dropSection: dropSection,
                                ),
                              ),
                            _ => SizedBox(
                                width: contentWidth,
                                height: MediaQuery.sizeOf(context).height,
                                child: MiscSection(
                                  dropSection: dropSection,
                                ),
                              ),
                          },
                        ),
                        if (showSidebar)
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height - 8,
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: MainSidebar(
                                selectedMode: appMode(),
                                onModeChanged: handleModeChanged,
                                onShowTooltip: _handleShowTooltip,
                                onHideTooltip: _handleHideTooltip,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Offstage(
              offstage: !isAboutApp(),
              child: const AboutApp(),
            ),
            Offstage(
              offstage: !isSetupApp(),
              child: const SetupApp(),
            ),
            Offstage(
              offstage: !isCropApp(),
              child: const CropApp(),
            ),
          ],
        );
      },
    );
  }
}
