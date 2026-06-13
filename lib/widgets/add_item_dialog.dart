import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/launch_item.dart';
import '../utils/path_util.dart';

class AddItemDialog extends StatefulWidget {
  const AddItemDialog({super.key});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final _nameController = TextEditingController();
  final _pathController = TextEditingController();
  bool _runAsAdmin = false;
  int? _hotkeyModifiers;
  int? _hotkeyVirtualKey;
  String _hotkeyLabel = '点击录制';
  ItemType _detectedType = ItemType.file;

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _pickFile() async {
    final result = await FilePicker.pickFiles();
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      _pathController.text = path;
      _detectedType = PathUtil.detectType(path);
      if (_nameController.text.isEmpty) {
        _nameController.text = PathUtil.getFileName(path);
        final dotIndex = _nameController.text.lastIndexOf('.');
        if (dotIndex > 0) {
          _nameController.text = _nameController.text.substring(0, dotIndex);
        }
      }
      setState(() {});
    }
  }

  void _pickFolder() async {
    final result = await FilePicker.getDirectoryPath();
    if (result != null) {
      _pathController.text = result;
      _detectedType = ItemType.folder;
      if (_nameController.text.isEmpty) {
        _nameController.text = PathUtil.getFileName(result);
      }
      setState(() {});
    }
  }

  void _startHotkeyRecording() {
    showDialog(
      context: context,
      builder: (ctx) => _HotkeyRecorderDialog(
        onHotkeySet: (modifiers, virtualKey) {
          _hotkeyModifiers = modifiers;
          _hotkeyVirtualKey = virtualKey;
          final modParts = <String>[];
          if (modifiers & 0x01 != 0) modParts.add('Alt');
          if (modifiers & 0x02 != 0) modParts.add('Ctrl');
          if (modifiers & 0x04 != 0) modParts.add('Shift');
          if (modifiers & 0x08 != 0) modParts.add('Win');
          final keyName = _virtualKeyName(virtualKey);
          _hotkeyLabel = '${modParts.join('+')}+$keyName';
          setState(() {});
        },
      ),
    );
  }

  String _virtualKeyName(int key) {
    const keys = {
      0x08: 'Backspace',
      0x09: 'Tab',
      0x0D: 'Enter',
      0x1B: 'Esc',
      0x20: 'Space',
      0x21: 'PageUp',
      0x22: 'PageDown',
      0x23: 'End',
      0x24: 'Home',
      0x25: 'Left',
      0x26: 'Up',
      0x27: 'Right',
      0x28: 'Down',
      0x2D: 'Insert',
      0x2E: 'Delete',
      0x30: '0',
      0x31: '1',
      0x32: '2',
      0x33: '3',
      0x34: '4',
      0x35: '5',
      0x36: '6',
      0x37: '7',
      0x38: '8',
      0x39: '9',
      0x41: 'A',
      0x42: 'B',
      0x43: 'C',
      0x44: 'D',
      0x45: 'E',
      0x46: 'F',
      0x47: 'G',
      0x48: 'H',
      0x49: 'I',
      0x4A: 'J',
      0x4B: 'K',
      0x4C: 'L',
      0x4D: 'M',
      0x4E: 'N',
      0x4F: 'O',
      0x50: 'P',
      0x51: 'Q',
      0x52: 'R',
      0x53: 'S',
      0x54: 'T',
      0x55: 'U',
      0x56: 'V',
      0x57: 'W',
      0x58: 'X',
      0x59: 'Y',
      0x5A: 'Z',
      0x70: 'F1',
      0x71: 'F2',
      0x72: 'F3',
      0x73: 'F4',
      0x74: 'F5',
      0x75: 'F6',
      0x76: 'F7',
      0x77: 'F8',
      0x78: 'F9',
      0x79: 'F10',
      0x7A: 'F11',
      0x7B: 'F12',
    };
    return keys[key] ?? '0x${key.toRadixString(16).toUpperCase()}';
  }

  void _submit() {
    if (_nameController.text.isEmpty || _pathController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入名称和路径')),
      );
      return;
    }

    final item = LaunchItem(
      id: const Uuid().v4(),
      name: _nameController.text.trim(),
      targetPath: _pathController.text.trim(),
      type: _detectedType,
      hotkeyModifiers: _hotkeyModifiers,
      hotkeyVirtualKey: _hotkeyVirtualKey,
      runAsAdmin: _runAsAdmin,
    );

    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (_detectedType) {
      ItemType.executable => '应用程序',
      ItemType.batScript => '脚本',
      ItemType.file => '文件',
      ItemType.folder => '文件夹',
      ItemType.system => '系统命令',
    };

    return AlertDialog(
      title: const Text('添加启动项'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '显示名称',
                hintText: '输入启动项名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathController,
              decoration: InputDecoration(
                labelText: '路径',
                hintText: '选择文件或文件夹',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.insert_drive_file),
                      tooltip: '选择文件',
                      onPressed: _pickFile,
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      tooltip: '选择文件夹',
                      onPressed: _pickFolder,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '检测类型: $typeLabel',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('快捷键: '),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _startHotkeyRecording,
                  icon: const Icon(Icons.keyboard, size: 18),
                  label: Text(_hotkeyLabel),
                ),
                if (_hotkeyVirtualKey != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      setState(() {
                        _hotkeyModifiers = null;
                        _hotkeyVirtualKey = null;
                        _hotkeyLabel = '点击录制';
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('管理员运行'),
                const SizedBox(width: 8),
                Switch(
                  value: _runAsAdmin,
                  onChanged: (v) => setState(() => _runAsAdmin = v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('添加'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 热键录制对话框
// 使用 Focus.onKeyEvent 替代 KeyboardListener，解决 Dialog 内焦点不可靠的问题
// ---------------------------------------------------------------------------
class _HotkeyRecorderDialog extends StatefulWidget {
  final void Function(int modifiers, int virtualKey) onHotkeySet;

  const _HotkeyRecorderDialog({required this.onHotkeySet});

  @override
  State<_HotkeyRecorderDialog> createState() => _HotkeyRecorderDialogState();
}

class _HotkeyRecorderDialogState extends State<_HotkeyRecorderDialog> {
  final FocusNode _focusNode = FocusNode();
  String _currentLabel = '请按下组合键 (如 Ctrl+Alt+A)';

  @override
  void initState() {
    super.initState();
    // Focus 在 Dialog 内需要构建完成后强制获取焦点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('录制快捷键'),
      content: SizedBox(
        width: 320,
        height: 120,
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            child: Text(
              _currentLabel,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;

    // 忽略纯修饰键按下
    if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      return KeyEventResult.handled;
    }

    // 必须至少有一个修饰键
    if (!isAlt && !isCtrl && !isShift && !isMeta) return KeyEventResult.ignored;

    int modifiers = 0;
    final parts = <String>[];
    if (isAlt) {
      modifiers |= 0x01;
      parts.add('Alt');
    }
    if (isCtrl) {
      modifiers |= 0x02;
      parts.add('Ctrl');
    }
    if (isShift) {
      modifiers |= 0x04;
      parts.add('Shift');
    }
    if (isMeta) {
      modifiers |= 0x08;
      parts.add('Win');
    }

    // 转换到 Windows 虚拟键码
    final virtualKey = _physicalToVk(event.physicalKey);
    if (virtualKey == null) return KeyEventResult.ignored;

    parts.add(_keyLabel(key));
    _currentLabel = parts.join('+');

    // 通知父对话框并关闭
    widget.onHotkeySet(modifiers, virtualKey);
    Navigator.of(context).pop();

    return KeyEventResult.handled;
  }

  String _keyLabel(LogicalKeyboardKey key) {
    if (key.keyLabel.isNotEmpty && key.keyLabel.length == 1) {
      return key.keyLabel.toUpperCase();
    }
    // NOT const — LogicalKeyboardKey overrides ==/hashCode
    final labels = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.tab: 'Tab',
      LogicalKeyboardKey.escape: 'Esc',
      LogicalKeyboardKey.backspace: 'Backspace',
      LogicalKeyboardKey.delete: 'Delete',
      LogicalKeyboardKey.insert: 'Insert',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      LogicalKeyboardKey.pageUp: 'PageUp',
      LogicalKeyboardKey.pageDown: 'PageDown',
      LogicalKeyboardKey.arrowLeft: 'Left',
      LogicalKeyboardKey.arrowRight: 'Right',
      LogicalKeyboardKey.arrowUp: 'Up',
      LogicalKeyboardKey.arrowDown: 'Down',
    };
    return labels[key] ?? key.debugName ?? '?';
  }

  /// Flutter PhysicalKeyboardKey (USB HID) → Windows VK 码
  int? _physicalToVk(PhysicalKeyboardKey physical) {
    final hid = physical.usbHidUsage;

    // A-Z: HID 0x04-0x1D → VK 0x41-0x5A
    if (hid >= 0x04 && hid <= 0x1D) return 0x41 + (hid - 0x04);
    // 0-9: HID 0x1E-0x27 → VK 0x30-0x39
    if (hid >= 0x1E && hid <= 0x27) return 0x30 + (hid - 0x1E);
    // F1-F12: HID 0x3A-0x45 → VK 0x70-0x7B
    if (hid >= 0x3A && hid <= 0x45) return 0x70 + (hid - 0x3A);

    const special = <int, int>{
      0x2C: 0x20, 0x2D: 0x2D, 0x2E: 0x3D, 0x2F: 0x5B, 0x30: 0x5D,
      0x31: 0x5C, 0x33: 0x3B, 0x34: 0x27, 0x35: 0x60, 0x36: 0x2C,
      0x37: 0x2E, 0x38: 0x2F,
      0x4C: 0x2E, 0x4D: 0x2D, 0x4E: 0x24, 0x4F: 0x23, 0x50: 0x21,
      0x51: 0x22, 0x52: 0x25, 0x53: 0x27, 0x54: 0x26, 0x55: 0x28,
      0x62: 0x0D, 0x63: 0x09, 0x64: 0x20, 0x65: 0x2D, 0x66: 0x2E,
      0x67: 0x25, 0x68: 0x26, 0x69: 0x27, 0x6A: 0x28,
    };
    return special[hid];
  }
}
