enum UnifiedMediaType { all, movie, series, variety, animation }

extension UnifiedMediaTypeLabel on UnifiedMediaType {
  String get label => switch (this) {
        UnifiedMediaType.all => '全部',
        UnifiedMediaType.movie => '电影',
        UnifiedMediaType.series => '剧集',
        UnifiedMediaType.variety => '综艺',
        UnifiedMediaType.animation => '动漫',
      };
}

/// A source-native category kept intact so requests can use its original ID.
class RemoteCategory {
  const RemoteCategory({
    required this.id,
    required this.name,
    this.parentId,
  });

  final String id;
  final String name;
  final String? parentId;
}

class UnifiedCategory {
  const UnifiedCategory({
    required this.type,
    required this.sourceCategoryIds,
    this.displayName,
  });

  final UnifiedMediaType type;
  final List<String> sourceCategoryIds;
  final String? displayName;
}

/// Converts one-level and tree-shaped source categories into stable Cineo
/// browsing types while retaining original IDs for API requests.
class MediaCategoryAdapter {
  const MediaCategoryAdapter._();

  static List<UnifiedCategory> adapt(List<RemoteCategory> categories) {
    final byId = {for (final category in categories) category.id: category};
    final grouped = <UnifiedMediaType, List<String>>{};
    for (final category in categories) {
      final type = _typeFor(category, byId);
      if (type == null) continue;
      grouped.putIfAbsent(type, () => []).add(category.id);
    }
    return [
      const UnifiedCategory(
        type: UnifiedMediaType.all,
        sourceCategoryIds: [],
      ),
      for (final type in UnifiedMediaType.values.skip(1))
        if (grouped[type]?.isNotEmpty ?? false)
          UnifiedCategory(
            type: type,
            sourceCategoryIds: List.unmodifiable(grouped[type]!),
          ),
    ];
  }

  static UnifiedMediaType? _typeFor(
    RemoteCategory category,
    Map<String, RemoteCategory> byId,
  ) {
    final names = <String>[category.name];
    var parentId = category.parentId;
    final visited = <String>{category.id};
    while (parentId != null && parentId.isNotEmpty && visited.add(parentId)) {
      final parent = byId[parentId];
      if (parent == null) break;
      names.add(parent.name);
      parentId = parent.parentId;
    }
    final text = names.join(' ').toLowerCase();
    if (RegExp(r'动漫|动画|番剧|cartoon|anime').hasMatch(text)) {
      return UnifiedMediaType.animation;
    }
    if (RegExp(r'综艺|真人秀|variety|show').hasMatch(text)) {
      return UnifiedMediaType.variety;
    }
    if (RegExp(r'电视剧|剧集|连续剧|短剧|台剧|韩剧|美剧|日剧|series|tv').hasMatch(text)) {
      return UnifiedMediaType.series;
    }
    if (RegExp(r'电影|影片|片库|movie|film').hasMatch(text)) {
      return UnifiedMediaType.movie;
    }
    return null;
  }
}
