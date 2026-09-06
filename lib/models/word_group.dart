import 'package:unorm_dart/unorm_dart.dart' as unicode;

class WordGroup {
  const WordGroup(this.id, this.name);
  final int id;
  final String name;
}

String cleanGroupName(String name) => unicode.nfc(name.trim());
String groupNameKey(String name) => cleanGroupName(name).toLowerCase();

class GroupSelection {
  GroupSelection({Set<int> ids = const {}, this.ungrouped = false})
    : ids = Set.unmodifiable(ids);
  final Set<int> ids;
  final bool ungrouped;
  bool get all => ids.isEmpty && !ungrouped;
}

class ImportGroupChoice {
  const ImportGroupChoice({this.id, this.name});
  final int? id;
  final String? name;
}
