# Windows 快速启动工具 — Flutter 技术设计文档 (精简版)

> **技术栈：** Flutter (Dart) + Windows Desktop  
> **版本：** V1.1 | **日期：** 2026-06-13

---

## 一、需求概述

一个简洁的 Windows 桌面启动器，核心功能：

1. **添加启动项** — 支持 `.bat` / `.exe` / 任意文件 / 文件夹
2. **自定义快捷键** — 每个启动项可绑定一个快捷键，一键启动
3. **内置系统命令** — 预置关机、重启、控制面板等系统功能

不需要复杂的分组管理、搜索、多视图、配置导入导出等高级功能。

---

## 二、技术选型

| 模块 | 选型 | 理由 |
|------|------|------|
| 框架 | Flutter 3.x (Windows) | 跨平台潜力，开发效率高 |
| 状态管理 | StatefulWidget + ValueNotifier | 功能简单，无需引入重型框架 |
| 数据持久化 | shared_preferences | 存储量小，无需数据库 |
| 窗口管理 | bitsdojo_window | 无边框窗口、置顶、尺寸控制 |
| 全局热键 | win32 (RegisterHotKey) | 直接调用 Win32 API |
| 窗口消息泵 | 原生 C++ WindowProc 子类化 | 拦截 WM_HOTKEY 消息传给 Dart |
| 系统托盘 | system_tray | 托盘图标 + 右键菜单 |
| 进程启动 | dart:io Process | 原生支持，零依赖 |

---

## 三、整体架构

```
┌──────────────────────────────────────────────────┐
│  Dart Layer                                       │
│  ┌────────────────────────────────────────────┐  │
│  │  QuickLaunchApp                             │  │
│  │  ├── AppBar (标题 + 系统命令菜单)            │  │
│  │  ├── ListView (启动项列表)                   │  │
│  │  └── FAB (添加)                             │  │
│  ├── HotkeyService ◄── MethodChannel ◄──┐      │  │
│  │                                        │      │  │
│  └── LaunchService ──→ dart:io Process    │      │  │
│                                           │      │  │
├───────────────────────────────────────────┼──────┤  │
│  Native C++ Layer                         │      │  │
│  ┌──────────────────────────────────────┐ │      │  │
│  │  WindowProc (子类化)                  ├─┘      │  │
│  │  ├── WM_HOTKEY → MethodChannel       │        │  │
│  │  └── 其他消息转发原 WindowProc         │        │  │
│  └──────────────────────────────────────┘        │  │
└──────────────────────────────────────────────────┘  │
                                                      │
  ┌──────────────────────────────────────────────────┐│
  │  Win32 API Layer                                  ││
  │  ├── RegisterHotKey / UnregisterHotKey            ││
  │  ├── ShellExecuteEx (runas 管理员)                 ││
  │  └── LockWorkStation / 系统命令                    ││
  └──────────────────────────────────────────────────┘│
```

---

## 四、项目结构

```
quick_launch/
├── lib/
│   ├── main.dart                    # 入口 + 初始化
│   ├── app.dart                     # MaterialApp + 主题
│   ├── models/
│   │   └── launch_item.dart         # 启动项数据模型 (含序列化)
│   ├── pages/
│   │   └── home_page.dart           # 主页面
│   ├── widgets/
│   │   ├── item_tile.dart           # 启动项卡片
│   │   └── add_item_dialog.dart     # 添加对话框
│   ├── services/
│   │   ├── item_service.dart        # 启动项增删改查 + 持久化
│   │   ├── hotkey_service.dart      # 全局热键注册/注销/调度
│   │   ├── launch_service.dart      # 启动执行器 (含管理员运行)
│   │   └── system_commands.dart     # 内置系统命令
│   └── utils/
│       └── path_util.dart           # 路径工具函数
├── windows/
│   └── runner/
│       ├── main.cpp                 # WinMain + WindowProc 子类化
│       └── flutter_window.cpp       # 注册热键消息通道
└── pubspec.yaml
```

---

## 五、数据模型

```dart
import 'dart:convert';

// 启动项模型
class LaunchItem {
  final String id;          // UUID
  String name;              // 显示名称
  String targetPath;        // 路径 / 系统命令标识
  ItemType type;            // exe / bat / file / folder / system
  int? hotkeyModifiers;     // 快捷键修饰键 (MOD_ALT=1, MOD_CONTROL=2, MOD_SHIFT=4, MOD_WIN=8)
  int? hotkeyVirtualKey;    // 快捷键虚拟键码
  bool runAsAdmin;          // 是否管理员运行
  DateTime createdAt;

  LaunchItem({...});        // 构造函数

  // shared_preferences 存储需要序列化
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'targetPath': targetPath,
    'type': type.name,
    'hotkeyModifiers': hotkeyModifiers,
    'hotkeyVirtualKey': hotkeyVirtualKey,
    'runAsAdmin': runAsAdmin,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LaunchItem.fromJson(Map<String, dynamic> json) => LaunchItem(
    id: json['id'] as String,
    name: json['name'] as String,
    targetPath: json['targetPath'] as String,
    type: ItemType.values.byName(json['type'] as String),
    hotkeyModifiers: json['hotkeyModifiers'] as int?,
    hotkeyVirtualKey: json['hotkeyVirtualKey'] as int?,
    runAsAdmin: json['runAsAdmin'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

enum ItemType { executable, batScript, file, folder, system }
```

**注意：** `id.hashCode.abs()` 用于生成热键 ID 而非直接使用 `hashCode`，避免负数。

---

## 六、核心功能实现

### 6.1 添加启动项

```dart
Future<void> _showAddDialog() async {
  final result = await showDialog<LaunchItem>(
    context: context,
    builder: (ctx) => AddItemDialog(),
  );
  if (result != null) {
    ItemService().addItem(result);
    if (result.hotkeyVirtualKey != null) {
      HotkeyService().registerItemHotkey(result);
    }
  }
}
```

**添加对话框包含：**
- 名称输入框
- 路径输入框 + "浏览"按钮（调用 file_picker）
- 类型自动识别（根据扩展名判断 exe/bat/文件夹等）
- 快捷键录制器（点击后按下组合键捕获）
- 管理员运行开关

### 6.2 快捷键系统（核心，需原生配合）

#### 6.2.1 原生层：子类化 WindowProc（`windows/runner/main.cpp`）

```cpp
// 全局变量保存原始 WindowProc
static WNDPROC originalWindowProc = nullptr;
static flutter::MethodChannel<flutter::EncodableValue>* hotkeyChannel = nullptr;

LRESULT CALLBACK HotkeyWindowProc(HWND hWnd, UINT message,
                                   WPARAM wParam, LPARAM lParam) {
  if (message == WM_HOTKEY) {
    // 通过 MethodChannel 将 hotkeyId 发给 Dart 层
    if (hotkeyChannel != nullptr) {
      hotkeyChannel->Invoke(
        "onHotkey",  // 方法名
        std::make_unique<flutter::EncodableValue>(
          flutter::EncodableValue(static_cast<int>(wParam))
        )
      );
    }
    return 0;  // 表示消息已处理
  }
  // 其他消息转发给原始窗口过程
  return CallWindowProc(originalWindowProc, hWnd, message, wParam, lParam);
}

// 在窗口创建后设置子类化：
// originalWindowProc = (WNDPROC)SetWindowLongPtr(hWnd, GWLP_WNDPROC,
//                                                (LONG_PTR)HotkeyWindowProc);
```

**说明：** Flutter Windows 应用不是控制台程序，`GetConsoleWindow()` 会返回 NULL。必须通过子类化 Flutter 窗口的 WindowProc 来拦截 `WM_HOTKEY` 消息，并通过 `MethodChannel` 将热键 ID 传递给 Dart 层。

#### 6.2.2 Dart 层：HotkeyService

```dart
class HotkeyService {
  static const int BASE_HOTKEY_ID = 100;

  // 热键 ID → LaunchItem 映射表
  final Map<int, LaunchItem> _hotkeyMap = {};

  // 从 bitsdojo_window 获取 Flutter 窗口 HWND
  // 注意：appWindow.handle 返回的是 HWND (int)
  int get _hWnd => appWindow.handle;

  /// 注册单个项目的快捷键
  void registerItemHotkey(LaunchItem item) {
    if (item.hotkeyVirtualKey == null || item.hotkeyModifiers == null) return;

    // hashCode 取绝对值确保 ID 为正数
    final hotkeyId = BASE_HOTKEY_ID + (item.id.hashCode.abs() % 9000);
    _hotkeyMap[hotkeyId] = item;

    final result = RegisterHotKey(
      _hWnd,
      hotkeyId,
      item.hotkeyModifiers!,
      item.hotkeyVirtualKey!,
    );
    if (result == 0) {
      // 注册失败（如快捷键冲突），记录日志
      print('RegisterHotKey failed for ${item.name}, error: ${GetLastError()}');
    }
  }

  /// 注销单个项目的快捷键
  void unregisterItemHotkey(LaunchItem item) {
    final hotkeyId = BASE_HOTKEY_ID + (item.id.hashCode.abs() % 9000);
    _hotkeyMap.remove(hotkeyId);
    UnregisterHotKey(_hWnd, hotkeyId);
  }

  /// 由 MethodChannel 回调触发，根据 hotkeyId 查找项目并启动
  void onHotkeyPressed(int hotkeyId) {
    final item = _hotkeyMap[hotkeyId];
    if (item != null) {
      LaunchService().launch(item);
    }
  }

  /// 清理所有热键（应用退出时调用）
  void dispose() {
    for (final id in _hotkeyMap.keys) {
      UnregisterHotKey(_hWnd, id);
    }
    _hotkeyMap.clear();
  }
}
```

### 6.3 启动执行器

```dart
class LaunchService {
  /// 启动一个项目，如有异常不崩溃而是打印错误
  Future<void> launch(LaunchItem item) async {
    try {
      if (item.runAsAdmin) {
        await _launchAsAdmin(item);
        return;
      }

      switch (item.type) {
        case ItemType.executable:
        case ItemType.batScript:
          await Process.start(
            item.targetPath, [],
            runInShell: true,
            workingDirectory: _parentDir(item.targetPath),
          );
        case ItemType.file:
          // 用关联程序打开文件
          await Process.start(
            'cmd', ['/c', 'start', '', item.targetPath],
            runInShell: true,
          );
        case ItemType.folder:
          // 文件夹用 explorer 打开
          await Process.start('explorer', [item.targetPath]);
        case ItemType.system:
          SystemCommands.execute(item.targetPath);
      }
    } catch (e) {
      print('Failed to launch ${item.name}: $e');
    }
  }

  /// 以管理员权限启动（需要使用 ShellExecuteEx + runas 动词）
  Future<void> _launchAsAdmin(LaunchItem item) async {
    // ShellExecuteExW 需要 win32 包的辅助
    // 关键参数: lpVerb = "runas", lpFile = item.targetPath
    // 实现略（详见 win32 文档 ShellExecute 相关 API）
  }

  /// 安全获取父目录，防止非文件类型崩溃
  String? _parentDir(String path) {
    try {
      return Directory(path).parent.path;
    } catch (_) {
      return null;
    }
  }
}
```

**说明：**
- 使用 `Process.start` 而非 `Process.run`：前者不等待子进程退出，适合"启动后即忘"的场景，且不会在关机/重启时阻塞。
- 添加了 try-catch 错误处理，避免静默失败。
- `runAsAdmin` 必须通过 Win32 `ShellExecuteEx` 传入 `runas` 动词实现，`Process.start` 无法提权。
- 系统命令类型 (`ItemType.system`) 不设置 `workingDirectory`，避免 `Directory()` 构造异常。

### 6.4 内置系统命令

```dart
class SystemCommands {
  static final List<LaunchItem> builtinCommands = [
    LaunchItem(id: 'sys_shutdown',  name: '关机',     targetPath: 'shutdown',    type: ItemType.system),
    LaunchItem(id: 'sys_restart',   name: '重启',     targetPath: 'restart',     type: ItemType.system),
    LaunchItem(id: 'sys_lock',      name: '锁屏',     targetPath: 'lock',        type: ItemType.system),
    LaunchItem(id: 'sys_control',   name: '控制面板', targetPath: 'control',     type: ItemType.system),
    LaunchItem(id: 'sys_recycle',   name: '回收站',   targetPath: 'recycle_bin', type: ItemType.system),
    LaunchItem(id: 'sys_this_pc',   name: '此电脑',   targetPath: 'this_pc',     type: ItemType.system),
    LaunchItem(id: 'sys_calc',      name: '计算器',   targetPath: 'calc',        type: ItemType.system),
    LaunchItem(id: 'sys_notepad',   name: '记事本',   targetPath: 'notepad',     type: ItemType.system),
    LaunchItem(id: 'sys_taskmgr',   name: '任务管理器', targetPath: 'taskmgr',   type: ItemType.system),
  ];

  static void execute(String command) {
    switch (command) {
      case 'shutdown':    Process.run('shutdown', ['/s', '/t', '0']);
      case 'restart':     Process.run('shutdown', ['/r', '/t', '0']);
      case 'lock':        Process.run('rundll32', ['user32.dll,LockWorkStation']);
      case 'control':     Process.run('control', []);
      case 'recycle_bin': Process.run('explorer', ['shell:RecycleBinFolder']);
      case 'this_pc':     Process.run('explorer', ['shell:MyComputerFolder']);
      case 'calc':        Process.run('calc', []);
      case 'notepad':     Process.run('notepad', []);
      case 'taskmgr':     Process.run('taskmgr', []);
    }
  }
}
```

> **注意：** 这里的 `Process.run` 可以保留（命令执行很快），也可统一为 `Process.start`。关机/重启命令如果使用 `Process.run` 会因为系统关闭而立即中断，不会造成阻塞问题。

### 6.5 主页面 UI

```dart
class HomePage extends StatefulWidget { ... }

class _HomePageState extends State<HomePage> {
  final items = ItemService().items;  // ValueNotifier<List<LaunchItem>>

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('快速启动'),
        actions: [
          PopupMenuButton<LaunchItem>(
            tooltip: '系统命令',
            icon: Icon(Icons.power_settings_new),
            onSelected: (item) => LaunchService().launch(item),
            itemBuilder: (_) => SystemCommands.builtinCommands.map((cmd) =>
              PopupMenuItem(value: cmd, child: Text(cmd.name))
            ).toList(),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: items,
        builder: (_, list, __) => list.isEmpty
          ? Center(child: Text('点击右下角 + 添加启动项'))
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => ItemTile(item: list[i]),
            ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
        child: Icon(Icons.add),
      ),
    );
  }
}
```

**改动说明：** `PopupMenuButton` 的泛型从 `String` 改为 `LaunchItem`，`onSelected` 直接调用 `LaunchService().launch(item)`，避免了原来调用不存在方法 `launchSystem(cmd)` 的问题。

### 6.6 初始化流程（main.dart）

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 初始化 bitsdojo_window（必须在 runApp 前）
  final app = await appWindow.waitForHandle();

  // 2. 加载持久化的启动项列表
  await ItemService().load();

  // 3. 注册所有已保存项目的快捷键
  for (final item in ItemService().items.value) {
    if (item.hotkeyVirtualKey != null) {
      HotkeyService().registerItemHotkey(item);
    }
  }

  // 4. 初始化系统托盘（设置图标、菜单、最小化回调）
  await SystemTrayManager().init();

  runApp(QuickLaunchApp());

  // 5. 设置 MethodChannel 监听原生层热键消息
  //    必须在 runApp 之后，确保 channel 已注册
  HotkeyService().setupChannel();
}
```

---

## 七、依赖清单 (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  bitsdojo_window: ^0.1.8        # 无边框窗口 + 获取 HWND
  win32: ^5.0.0                  # Win32 API (RegisterHotKey, ShellExecuteEx)
  system_tray: ^0.2.3            # 系统托盘 (注意：最新的稳定版本为 0.2.x 系列)
  file_picker: ^6.2.0            # 文件选择对话框 (当前稳定版 6.x)
  shared_preferences: ^2.2.0     # 存储启动项列表 JSON
  uuid: ^4.3.3                   # 生成唯一 ID
  path: ^1.9.0                   # 路径处理
```

---

## 八、关键功能一览

| 功能 | 实现方式 |
|------|---------|
| 添加 exe/bat/文件/文件夹 | 文件选择对话框 + 路径自动识别类型 |
| 设置快捷键 | 点击录制按钮 → 按下组合键 → 捕获键码 |
| 快捷键启动 | `RegisterHotKey` 注册，原生 `WindowProc` 拦截 `WM_HOTKEY`，`MethodChannel` 传递到 Dart |
| 系统命令 | 内置 10 个常用命令，`PopupMenuButton<LaunchItem>` 一键启动 |
| 启动项目 | `Process.start`（不阻塞）+ `ShellExecuteEx`（管理员提权） |
| 数据持久化 | `shared_preferences` 存 JSON 列表，`toJson`/`fromJson` 序列化 |
| 窗口置顶 | `bitsdojo_window` 设置 `alwaysOnTop` |
| 托盘运行 | `system_tray` 最小化到系统托盘，右键菜单退出/显示窗口 |

---

## 九、构建命令

```powershell
flutter build windows --release
# 产物: build/windows/runner/Release/quick_launch.exe
```

---

## 十、常见陷阱 & 注意事项

| 陷阱 | 说明 |
|------|------|
| ❌ `GetConsoleWindow()` 返回 NULL | Flutter GUI 应用不是控制台程序，必须通过 `bitsdojo_window` 的 `appWindow.handle` 或子类化 WindowProc 获取 HWND |
| ❌ 没有 WindowProc 子类化 | `RegisterHotKey` 注册成功也不会有回调，必须子类化窗口过程拦截 `WM_HOTKEY` |
| ❌ `hashCode` 可能为负数 | Dart `hashCode` 返回 `int`，模运算结果可能为负，必须用 `.abs()` 确保热键 ID 为正 |
| ❌ `Process.run` 阻塞等待 | 使用 `Process.start` 避免阻塞；特别是关机/重启等命令 |
| ❌ `Directory(path).parent` 对非路径崩溃 | 系统命令和特殊标识符不应调用 `Directory()`，需提前判断类型 |
| ❌ 普通进程无法提权 | `Process.start` 不支持 `runas`，必须用 `ShellExecuteEx` 传入 `runas` 动词实现管理员运行 |
| ⚠️ 包版本与实际不符 | 依赖版本应以 `flutter pub add` 实际解析为准，建议创建项目后逐一添加 |

---

> **文档结束 | V1.1 修订内容：** 修正热键 HWND 获取方式、补充 WindowProc 子类化、修正 hotkey ID 负数问题、补充序列化、修复启动执行器错误、修正依赖版本、补充初始化流程与注意事项。
