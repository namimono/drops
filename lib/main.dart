import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:libcaesium_dart/libcaesium_dart.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:shakepin/app/main_drop_app.dart';
import 'package:shakepin/shelf/shelf_bootstrap.dart';
import 'package:shakepin/state.dart';
import 'package:shakepin/utils/cli.dart';
import 'package:shakepin/utils/drop_channel.dart';
import 'package:shakepin/utils/utils.dart';
import 'package:shakepin/services/settings_service.dart';
import 'package:shakepin/services/cli_tool_availability_service.dart';
import 'package:shakepin/widgets/native_dropdown_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await DropdownChannel.instance.initialize();

  prefs = await SharedPreferences.getInstance();

  if (Platform.isMacOS) {
    // Host engine: settings / tray / updater only. CLI probes belong on shelf engines.
    await SettingsService.initialize();
  } else {
    await cli.init();
    await cliToolAvailability.initialize();
  }

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await Window.initialize();

    trayManager.setIcon(
      'assets/images/tray_icon.ico',
    );

    windowManager.setAsFrameless();
    windowManager.setBackgroundColor(Colors.transparent);
    windowManager.setAlwaysOnTop(true);

    dropChannel.setMinimumSize(
      Size(
        AppSizes.pin.width,
        AppSizes.pin.height,
      ),
    );
    Window.hideWindowControls();
    windowManager.show();
  }

  if (Platform.isMacOS) {
    autoUpdater
      ..setFeedURL('https://skpn-dl.damywise.com/skpn-appcast.xml')
      ..addListener(_UpdaterListener())
      ..checkForUpdates(inBackground: true)
      ..setScheduledCheckInterval(86400);

    dropChannel.setTrayIcon(
      Uint8List.view(
          (await rootBundle.load('assets/images/tray_icon.png')).buffer),
    );

    // Host engine stays hidden; shelves are separate Flutter engines.
    runApp(const HostApp());
    return;
  }

  dropChannel.setFrame(
    Rect.fromCenter(
      center: await dropChannel.center(),
      width: AppSizes.pin.width,
      height: AppSizes.pin.height,
    ),
    animate: false,
  );

  runApp(const MainApp());
}

/// Secondary Flutter Engine entry for a collection shelf.
///
/// Must live in the same Dart library as [main]: macOS FlutterEngine.run
/// only resolves entrypoints from the root library (no libraryURI API).
@pragma('vm:entry-point')
void shelfMain(List<String> args) async {
  // macOS registers a few view-dependent plugins on the next native main-loop
  // turn. Let that registration settle before ShelfRootApp builds MacosApp,
  // which may access super_native_extensions during initialization.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  final shelfId = args.isNotEmpty ? args[0] : 'unknown';
  final source = args.length > 1 ? args[1] : 'hotkey';
  await shelfBootstrap(shelfId: shelfId, source: source);
}

class _UpdaterListener extends UpdaterListener {
  @override
  void onUpdaterCheckingForUpdate(appcast) {
    isCheckingForUpdate.value = true;
    updateError.value = null;
  }

  @override
  void onUpdaterUpdateAvailable(item) {
    isCheckingForUpdate.value = false;
    updateAvailable.value = true;
    updateVersion.value = item?.versionString;
  }

  @override
  void onUpdaterUpdateNotAvailable(error) {
    isCheckingForUpdate.value = false;
    updateAvailable.value = false;
  }

  @override
  void onUpdaterError(error) {
    isCheckingForUpdate.value = false;
    updateError.value = error?.message;
  }

  @override
  void onUpdaterUpdateDownloaded(item) {}

  @override
  void onUpdaterBeforeQuitForUpdate(item) {}
}

/// Minimal host UI for macOS — no collection shelf.
class HostApp extends StatelessWidget {
  const HostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MacosApp(
      debugShowCheckedModeBanner: false,
      home: SizedBox.shrink(),
    );
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  void initState() {
    if (Platform.isWindows) {
      windowManager.setOpacity(0);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      debugShowCheckedModeBanner: false,
      home: DragToResizeArea(
        enableResizeEdges: Platform.isMacOS
            ? []
            : const [
                ResizeEdge.topLeft,
                ResizeEdge.topRight,
                ResizeEdge.bottomLeft,
                ResizeEdge.bottomRight,
                ResizeEdge.left,
                ResizeEdge.bottom,
                ResizeEdge.right,
              ],
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(32)),
          child: MacosApp(
            debugShowCheckedModeBanner: false,
            home: DecoratedBox(
              decoration: BoxDecoration(
                color: Platform.isWindows ? MacosColors.gridColor : null,
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
      ),
    );
  }
}
