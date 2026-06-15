class ItemGroup {
  final String id;
  String name;
  int colorValue;
  int sortOrder;

  ItemGroup({
    required this.id,
    required this.name,
    this.colorValue = 0xFF42A5F5,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'sortOrder': sortOrder,
      };

  factory ItemGroup.fromJson(Map<String, dynamic> json) => ItemGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        colorValue: json['colorValue'] as int? ?? 0xFF42A5F5,
        sortOrder: json['sortOrder'] as int? ?? 0,
      );
}
