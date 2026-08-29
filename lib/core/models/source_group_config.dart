/// Represents the enable/disable state of a single category for a media source.
/// For adult sources: stores per-category visibility state (enabled/disabled).
/// Categories are independent - no hierarchical relationships.
class SourceGroupConfig {
  const SourceGroupConfig({
    required this.sourceId,
    required this.categoryId,
    required this.categoryName,
    required this.isEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  /// The source this category belongs to.
  final String sourceId;

  /// The original category ID from the remote API (e.g., type_id).
  final String categoryId;

  /// Display name of the category.
  final String categoryName;

  /// Whether this category is enabled (visible in home/search results).
  final bool isEnabled;

  final DateTime createdAt;
  final DateTime updatedAt;

  SourceGroupConfig copyWith({
    String? sourceId,
    String? categoryId,
    String? categoryName,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SourceGroupConfig(
      sourceId: sourceId ?? this.sourceId,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'SourceGroupConfig(sourceId=$sourceId, categoryId=$categoryId, name=$categoryName, enabled=$isEnabled)';
}
