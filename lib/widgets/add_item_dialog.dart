import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/launch_item.dart';
import '../services/hotkey_service.dart';
import '../utils/path_util.dart';

class AddItemDialog extends StatefulWidget {
  final LaunchItem? item;

  const AddItemDialog({super.key, this.item});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _pathController;
  late bool _runAsAdmin;
  int? _hotkeyModifiers;
  int? _hotkeyVirtualKey;
  late String _hotkeyLabel;
  late ItemType _detectedType;
  late bool _isCommandMode;

  bool get _isEditing => widget.item != null;
  String? _conflictHint; // 快捷键冲突提示

  @override
  void initState() {
    super.initState();
    final existing = widget.item;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _pathController = TextEditingController(text: existing?.targetPath ?? '');
    _runAsAdmin = existing?.runAsAdmin ?? false;
    _hotkeyModifiers = existing?.hotkeyModifiers;
    _hotkeyVirtualKey = existing?.hotkeyVirtualKey;
    _detectedType = existing?.type ?? ItemType.file;
    _isCommandMode = existing?.type == ItemType.command;

    if (existing?.hotkeyVirtualKey != null) {
      final mods = <String>[];
      if (existing!.hotkeyModifiers! & 0x01 != 0) mods.add('Alt');
      if (existing.hotkeyModifiers! & 0x02 != 0) mods.add('Ctrl');
      if (existing.hotkeyModifiers! & 0x04 != 0) mods.add('Shift');
      if (existing.hotkeyModifiers! & 0x08 != 0) mods.add('Win');
      final keyName = _virtualKeyName(existing.hotkeyVirtualKey!);
      _hotkeyLabel = '${mods.join('+')}+$keyName';
    } else {
      _hotkeyLabel = '点击录制';
    }
  }

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
      if (!_isEditing && _nameController.text.isEmpty) {
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
      if (!_isEditing && _nameController.text.isEmpty) {
        _nameController.text = PathUtil.getFileName(result);
      }
      setState(() {});
    }
  }

  void _startHotkeyRecording() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置快捷键'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('输入快捷键组合，例如：'),
            const SizedBox(height: 8),
            Text('  Ctrl+Alt+A\n  Ctrl+Shift+F5\n  Win+E\n  Alt+Space',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '快捷键',
                hintText: 'Ctrl+Alt+A',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;

              final result = _parseHotkeyText(text);
              if (result == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('无效的快捷键格式，请使用 Ctrl+Alt+A 格式')),
                );
                return;
              }

              final (modifiers, virtualKey) = result;

              // 冲突检测
              final conflict = HotkeyService().findConflict(
                modifiers, virtualKey,
                excludeId: widget.item?.id,
              );
              if (conflict != null) {
                showDialog(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    title: const Text('快捷键冲突'),
                    content: Text('"$conflict" 已使用该快捷键，请换一个。'),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.of(c).pop(),
                        child: const Text('知道了'),
                      ),
                    ],
                  ),
                );
                return;
              }

              _hotkeyModifiers = modifiers;
              _hotkeyVirtualKey = virtualKey;

              final modParts = <String>[];
              if (modifiers & 0x01 != 0) modParts.add('Alt');
              if (modifiers & 0x02 != 0) modParts.add('Ctrl');
              if (modifiers & 0x04 != 0) modParts.add('Shift');
              if (modifiers & 0x08 != 0) modParts.add('Win');
              final keyName = _virtualKeyName(virtualKey);
              _hotkeyLabel = '${modParts.join('+')}+$keyName';
              _conflictHint = null;

              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  (int, int)? _parseHotkeyText(String text) {
    final parts = text.split('+').map((s) => s.trim()).toList();
    if (parts.length < 2) return null;

    int modifiers = 0;
    String? keyPart;
    final modSet = <String>{'ctrl', 'control', 'alt', 'shift', 'win', 'windows', 'meta'};

    for (int i = 0; i < parts.length; i++) {
      final lower = parts[i].toLowerCase();
      if (modSet.contains(lower)) {
        switch (lower) {
          case 'ctrl':
          case 'control':
            modifiers |= 0x02;
            break;
          case 'alt':
            modifiers |= 0x01;
            break;
          case 'shift':
            modifiers |= 0x04;
            break;
          case 'win':
          case 'windows':
          case 'meta':
            modifiers |= 0x08;
            break;
        }
      } else {
        if (i != parts.length - 1) return null;
        keyPart = parts[i];
      }
    }

    if (modifiers == 0 || keyPart == null || keyPart.isEmpty) return null;
    final vk = _textToVk(keyPart);
    if (vk == null) return null;

    return (modifiers, vk);
  }

  int? _textToVk(String key) {
    final upper = key.toUpperCase();
    if (upper.length == 1 && upper.codeUnitAt(0) >= 0x41 && upper.codeUnitAt(0) <= 0x5A) {
      return upper.codeUnitAt(0);
    }
    if (upper.length == 1 && upper.codeUnitAt(0) >= 0x30 && upper.codeUnitAt(0) <= 0x39) {
      return upper.codeUnitAt(0);
    }
    const map = <String, int>{
      'F1': 0x70, 'F2': 0x71, 'F3': 0x72, 'F4': 0x73,
      'F5': 0x74, 'F6': 0x75, 'F7': 0x76, 'F8': 0x77,
      'F9': 0x78, 'F10': 0x79, 'F11': 0x7A, 'F12': 0x7B,
      'SPACE': 0x20, 'ENTER': 0x0D, 'RETURN': 0x0D, 'TAB': 0x09,
      'ESC': 0x1B, 'ESCAPE': 0x1B,
      'BACKSPACE': 0x08, 'DELETE': 0x2E, 'DEL': 0x2E, 'INSERT': 0x2D, 'INS': 0x2D,
      'HOME': 0x24, 'END': 0x23,
      'PAGEUP': 0x21, 'PGUP': 0x21, 'PAGEDOWN': 0x22, 'PGDN': 0x22,
      'LEFT': 0x25, 'RIGHT': 0x27, 'UP': 0x26, 'DOWN': 0x28,
      'MINUS': 0xBD, '-': 0xBD, 'EQUALS': 0xBB, '=': 0xBB,
      'LBRACKET': 0xDB, '[': 0xDB, 'RBRACKET': 0xDD, ']': 0xDD,
      'BACKSLASH': 0xDC, '\\': 0xDC,
      'SEMICOLON': 0xBA, ';': 0xBA, 'QUOTE': 0xDE, "'": 0xDE,
      'BACKTICK': 0xC0, '`': 0xC0,
      'COMMA': 0xBC, ',': 0xBC, 'PERIOD': 0xBE, '.': 0xBE, 'SLASH': 0xBF, '/': 0xBF,
    };
    return map[upper];
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

    // 最终提交时再次检查冲突（防止冲突检测后用户改了其他项）
    if (_hotkeyVirtualKey != null) {
      final conflict = HotkeyService().findConflict(
        _hotkeyModifiers, _hotkeyVirtualKey,
        excludeId: widget.item?.id,
      );
      if (conflict != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('快捷键与 "$conflict" 冲突，请修改后再保存')),
        );
        return;
      }
    }

    final item = LaunchItem(
      id: _isEditing ? widget.item!.id : const Uuid().v4(),
      name: _nameController.text.trim(),
      targetPath: _pathController.text.trim(),
      type: _isCommandMode ? ItemType.command : _detectedType,
      hotkeyModifiers: _hotkeyModifiers,
      hotkeyVirtualKey: _hotkeyVirtualKey,
      runAsAdmin: _runAsAdmin,
    );

    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (_isCommandMode ? ItemType.command : _detectedType) {
      ItemType.executable => '应用程序',
      ItemType.batScript => '脚本',
      ItemType.file => '文件',
      ItemType.folder => '文件夹',
      ItemType.system => '系统命令',
      ItemType.command => '命令',
    };

    return AlertDialog(
      title: Text(_isEditing ? '编辑启动项' : '添加启动项'),
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
                labelText: _isCommandMode ? '命令' : '路径',
                hintText: _isCommandMode ? '输入命令 (如: ipconfig /all)' : '选择文件、文件夹或输入命令',
                border: const OutlineInputBorder(),
                suffixIcon: !_isCommandMode
                    ? Row(
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
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('文件/文件夹'),
                  selected: !_isCommandMode,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _isCommandMode = false;
                        _detectedType = PathUtil.detectType(_pathController.text);
                      });
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('命令'),
                  selected: _isCommandMode,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _isCommandMode = true;
                        _detectedType = ItemType.command;
                      });
                    }
                  },
                ),
              ],
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
                        _conflictHint = null;
                      });
                    },
                  ),
              ],
            ),
            if (_conflictHint != null) ...[
              const SizedBox(height: 4),
              Text(_conflictHint!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
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
          child: Text(_isEditing ? '保存' : '添加'),
        ),
      ],
    );
  }
}
