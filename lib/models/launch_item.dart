enum ItemType { executable, batScript, file, folder, system, command, link }

class LaunchItem {
  final String id;
  String name;
  String targetPath;
  ItemType type;
  int? hotkeyModifiers;
  int? hotkeyVirtualKey;
  bool runAsAdmin;
  DateTime createdAt;
  String? groupId;
  int launchCount;
  DateTime? lastLaunchAt;
  List<String> aliases;

  LaunchItem({
    required this.id,
    required this.name,
    required this.targetPath,
    required this.type,
    this.hotkeyModifiers,
    this.hotkeyVirtualKey,
    this.runAsAdmin = false,
    DateTime? createdAt,
    this.groupId,
    this.launchCount = 0,
    this.lastLaunchAt,
    List<String>? aliases,
  })  : createdAt = createdAt ?? DateTime.now(),
      aliases = aliases ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'targetPath': targetPath,
        'type': type.name,
        'hotkeyModifiers': hotkeyModifiers,
        'hotkeyVirtualKey': hotkeyVirtualKey,
        'runAsAdmin': runAsAdmin,
        'createdAt': createdAt.toIso8601String(),
        'groupId': groupId,
        'launchCount': launchCount,
        'lastLaunchAt': lastLaunchAt?.toIso8601String(),
        'aliases': aliases,
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
        groupId: json['groupId'] as String?,
        launchCount: json['launchCount'] as int? ?? 0,
        lastLaunchAt: json['lastLaunchAt'] != null
            ? DateTime.parse(json['lastLaunchAt'] as String)
            : null,
        aliases: json['aliases'] != null
            ? List<String>.from(json['aliases'] as List)
            : null,
      );
}
