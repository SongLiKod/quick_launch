import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'app.dart';
import 'services/item_service.dart';
import 'services/hotkey_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved items from storage
  await ItemService().load();

  // Run the app
  runApp(const QuickLaunchApp());

  // Wait for the first frame so the window is fully ready
  await WidgetsBinding.instance.endOfFrame;

  // Set the native window handle for hotkey registration
  final hWnd = appWindow.handle;
  if (hWnd != null) {
    HotkeyService().setWindowHandle(hWnd);
  }

  // Register all previously saved hotkeys
  for (final item in ItemService().items.value) {
    if (item.hotkeyVirtualKey != null) {
      HotkeyService().registerItemHotkey(item);
    }
  }

  // Setup MethodChannel to receive WM_HOTKEY notifications from native C++ side
  const channel = MethodChannel('quick_launch/hotkey');
  channel.setMethodCallHandler((call) async {
    if (call.method == 'onHotkey') {
      final hotkeyId = call.arguments as int;
      HotkeyService().onHotkeyPressed(hotkeyId);
    }
    return null;
  });
}
