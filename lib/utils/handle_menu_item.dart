import 'dart:io';

import 'package:shakepin/state.dart';
import 'package:shakepin/utils/drop_channel.dart';
import 'package:shakepin/utils/utils.dart';

void handleMenuItemClicked(int tag) async {
  switch (tag) {
    case 1: // show / new shelf (Windows only — macOS handled natively)
      if (!Platform.isMacOS) {
        await showApp();
      }
    case 2: // hide (Windows)
      if (!Platform.isMacOS) {
        await hideApp();
      }
    case 3: // about
      isAboutApp.value = true;
      isLicenseApp.value = false;
      if (Platform.isMacOS) {
        await dropChannel.setVisible(true);
        await handleModeChanged(AppMode.pin, force: true);
        // Expand to about size via existing about UI path
        isAboutApp.value = true;
      } else {
        showApp();
      }
    case 4: // reset shared preferences
      await prefs.clear();
    default:
      break;
  }
}
