enum ItemType { executable, batScript, file, folder, system, command }

class LaunchItem {
  final String id;
  String name;
  String targetPath;
  ItemType type;
  int? hotkeyModifiers;
  int? hotkeyVirtualKey;
  bool runAsAdmin;
  DateTime createdAt;

  LaunchItem({
    required this.id,
    required this.name,
    required this.targetPath,
    required this.type,
    this.hotkeyModifiers,
    this.hotkeyVirtualKey,
    this.runAsAdmin = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

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
