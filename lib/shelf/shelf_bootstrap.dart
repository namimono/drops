import 'dart:async';

import 'package:flutter/material.dart';
import 'package:libcaesium_dart/libcaesium_dart.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:shakepin/app/main_drop_app.dart';
import 'package:shakepin/services/cli_tool_availability_service.dart';
import 'package:shakepin/services/settings_service.dart';
import 'package:shakepin/shelf/shelf_context.dart';
import 'package:shakepin/state.dart';
import 'package:shakepin/utils/cli.dart';
import 'package:shakepin/utils/drop_channel.dart';
import 'package:shakepin/utils/logger.dart';
import 'package:shakepin/widgets/native_dropdown_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controlled bootstrap for a collection-shelf Flutter Engine.
/// Does not initialize auto-updater, tray, or host settings ownership.
Future<void> shelfBootstrap({
  required String shelfId,
  required String source,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  ShelfContext.instance.configure(
    id: shelfId,
    openSource: shelfOpenSourceFromString(source),
  );

  // Channel handlers are cheap and must exist before the first widgets build.
  await DropdownChannel.instance.initialize();
  await SettingsService.initialize();

  runApp(const ShelfRootApp());

  // Do not expose the native window until Flutter has painted a clipped frame.
  // This also prevents the transparent AppKit host from flashing as a square.
  await WidgetsBinding.instance.endOfFrame;
  await dropChannel.shelfReady(shelfId);

  // CLI discovery performs several process launches and used to block the first
  // frame for roughly two seconds. Shelf actions are not available before the
  // UI is visible, so finish these services in the background.
  unawaited(_initializeShelfServices());
}

Future<void> _initializeShelfServices() async {
  try {
    prefs = await SharedPreferences.getInstance();
    await RustLib.init();
    await cli.init();
    await cliToolAvailability.initialize();
  } catch (error, stackTrace) {
    logger.log('Shelf background initialization failed: $error\n$stackTrace');
  }
}

class ShelfRootApp extends StatelessWidget {
  const ShelfRootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      debugShowCheckedModeBanner: false,
      home: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(32)),
        child: MacosApp(
          debugShowCheckedModeBanner: false,
          home: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: MacosTheme.brightnessOf(context).isDark
                    ? Colors.white.withValues(alpha: .2)
                    : Colors.black.withValues(alpha: .05),
                width: 1,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(32)),
            ),
            child: const MainDropApp(),
          ),
        ),
      ),
    );
  }
}
