enum UnifiedMediaType { all, movie, series, variety, animation, adult }

extension UnifiedMediaTypeLabel on UnifiedMediaType {
  String get label => switch (this) {
        UnifiedMediaType.all => '全部',
        UnifiedMediaType.movie => '电影',
        UnifiedMediaType.series => '剧集',
        UnifiedMediaType.variety => '综艺',
        UnifiedMediaType.animation => '动漫',
        UnifiedMediaType.adult => '成人资源',
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
    this.subcategories = const [],
  });

  final UnifiedMediaType type;
  final List<String> sourceCategoryIds;
  final String? displayName;
  final List<UnifiedSubcategory> subcategories;
}

/// A source-native leaf category displayed below a unified primary type.
///
/// The original IDs remain intact so browsing can request the source API with
/// `ac=videolist&t=<id>` rather than filtering a previously fetched page.
class UnifiedSubcategory {
  const UnifiedSubcategory({
    required this.id,
    required this.name,
    required this.sourceCategoryIds,
    this.matchText = '',
  });

  final String id;
  final String name;
  final List<String> sourceCategoryIds;

  /// The source category path, retained for fixed home-row matching.
  final String matchText;
}

/// Converts one-level and tree-shaped source categories into stable Cineo
/// browsing types while retaining original IDs for API requests.
class MediaCategoryAdapter {
  const MediaCategoryAdapter._();

  static List<UnifiedCategory> adapt(
    List<RemoteCategory> categories, {
    bool isAdult = false,
  }) {
    final byId = <String, RemoteCategory>{};
    for (final category in categories) {
      byId.putIfAbsent(category.id, () => category);
    }

    final childrenById = <String, Set<String>>{};
    for (final category in categories) {
      final parentId = category.parentId;
      if (parentId == null || parentId.isEmpty || !byId.containsKey(parentId)) {
        continue;
      }
      childrenById.putIfAbsent(parentId, () => <String>{}).add(category.id);
    }

    final cycleIds = _cycleIds(byId);
    final grouped = <UnifiedMediaType, List<String>>{};
    final groupedIds = <UnifiedMediaType, Set<String>>{};
    final subcategories = <UnifiedMediaType, List<UnifiedSubcategory>>{};
    final subcategoryIds = <UnifiedMediaType, Set<String>>{};
    for (final category in categories) {
      // Adult sources have source-native groups such as 无码、中文字幕 and
      // 素人. They must not be guessed as movie/series/animation based on
      // their names, otherwise the source's own grouping is lost.
      final type = isAdult ? UnifiedMediaType.adult : _typeFor(category, byId);
      if (type == null) continue;

      // A request should target the leaves of a source's category tree. The
      // parent category is still useful for resolving the unified type, but
      // requesting both parent and child IDs duplicates the same catalog.
      final children = childrenById[category.id] ?? const <String>{};
      final hasNonCycleChild =
          children.any((childId) => !cycleIds.contains(childId));
      final hasKnownChild = children.isNotEmpty;
      if (hasKnownChild &&
          (!cycleIds.contains(category.id) || hasNonCycleChild)) {
        continue;
      }

      final ids = grouped.putIfAbsent(type, () => []);
      final seen = groupedIds.putIfAbsent(type, () => <String>{});
      if (seen.add(category.id)) ids.add(category.id);

      final categoryGroups = subcategories.putIfAbsent(type, () => []);
      final seenGroups = subcategoryIds.putIfAbsent(type, () => <String>{});
      if (seenGroups.add(category.id)) {
        categoryGroups.add(
          UnifiedSubcategory(
            id: category.id,
            name: category.name,
            sourceCategoryIds: [category.id],
            matchText: _categoryPath(category, byId).join(' '),
          ),
        );
      }
    }
    final result = <UnifiedCategory>[
      const UnifiedCategory(
        type: UnifiedMediaType.all,
        sourceCategoryIds: [],
      ),
      for (final type in UnifiedMediaType.values.skip(1))
        if (grouped[type]?.isNotEmpty ?? false)
          UnifiedCategory(
            type: type,
            sourceCategoryIds: List.unmodifiable(grouped[type]!),
            subcategories: List.unmodifiable(subcategories[type]!),
          ),
    ];
    // Some adult APIs do not expose a class list. Keep an explicit adult tab
    // so the fallback can still browse the complete source catalog.
    if (isAdult && !result.any((item) => item.type == UnifiedMediaType.adult)) {
      result.add(const UnifiedCategory(
        type: UnifiedMediaType.adult,
        sourceCategoryIds: [],
      ));
    }
    return List.unmodifiable(result);
  }

  static Set<String> _cycleIds(Map<String, RemoteCategory> byId) {
    final cycleIds = <String>{};
    for (final startId in byId.keys) {
      final path = <String>[];
      final positions = <String, int>{};
      var currentId = startId;
      while (true) {
        final cycleStart = positions[currentId];
        if (cycleStart != null) {
          cycleIds.addAll(path.skip(cycleStart));
          break;
        }
        if (!byId.containsKey(currentId)) break;

        positions[currentId] = path.length;
        path.add(currentId);
        final parentId = byId[currentId]!.parentId;
        if (parentId == null || parentId.isEmpty) break;
        currentId = parentId;
      }
    }
    return cycleIds;
  }

  static UnifiedMediaType? _typeFor(
    RemoteCategory category,
    Map<String, RemoteCategory> byId,
  ) {
    final text = _categoryPath(category, byId).join(' ').toLowerCase();
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

  static List<String> _categoryPath(
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
    return names;
  }
}
