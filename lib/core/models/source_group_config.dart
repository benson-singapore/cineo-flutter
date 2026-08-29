/// Represents the enable/disable state of a media source's categories.
/// Stores hierarchical group configuration where each leaf category can be
/// enabled or disabled independently. Preserves the original category IDs and
/// parent relationships from the remote API.
class SourceGroupConfig {
  const SourceGroupConfig({
    required this.sourceId,
    required this.groupId,
    required this.parentGroupId,
    required this.groupName,
    required this.isEnabled,
    required this.isLeaf,
    required this.createdAt,
    required this.updatedAt,
  });

  /// The source this group belongs to.
  final String sourceId;

  /// The original category ID from the remote API.
  final String groupId;

  /// The parent group ID (from remote API), or empty string for root level.
  final String parentGroupId;

  /// Display name of the group.
  final String groupName;

  /// Whether this group is enabled (included in browsing/search results).
  final bool isEnabled;

  /// Whether this is a leaf category (has no children) or can contain children.
  final bool isLeaf;

  final DateTime createdAt;
  final DateTime updatedAt;

  SourceGroupConfig copyWith({
    String? sourceId,
    String? groupId,
    String? parentGroupId,
    String? groupName,
    bool? isEnabled,
    bool? isLeaf,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SourceGroupConfig(
      sourceId: sourceId ?? this.sourceId,
      groupId: groupId ?? this.groupId,
      parentGroupId: parentGroupId ?? this.parentGroupId,
      groupName: groupName ?? this.groupName,
      isEnabled: isEnabled ?? this.isEnabled,
      isLeaf: isLeaf ?? this.isLeaf,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'SourceGroupConfig(sourceId=$sourceId, groupId=$groupId, name=$groupName, enabled=$isEnabled, leaf=$isLeaf)';
}
