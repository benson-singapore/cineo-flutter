import 'package:flutter/material.dart';

import '../../core/models/media.dart';
import '../../core/theme/cineo_theme.dart';
import '../../data/remote/media_category_adapter.dart';
import 'category_browse_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.items,
    required this.history,
    required this.onSearch,
    required this.onOpenMedia,
    this.onRemoteSearch,
    this.onBrowseCategory,
    this.categories = const [],
    this.initialCategory,
  });

  final List<MediaItem> items;
  final List<String> history;
  final ValueChanged<String> onSearch;
  final ValueChanged<MediaItem> onOpenMedia;
  final Future<List<MediaItem>> Function(
      String query, List<String> categoryIds)? onRemoteSearch;
  final Future<List<MediaItem>> Function(List<String> categoryIds)?
      onBrowseCategory;
  final List<UnifiedCategory> categories;
  final UnifiedCategory? initialCategory;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();
  final _focusNode = FocusNode();
  final _localHistory = <String>[];
  String _query = '';
  String? _errorMessage;
  List<MediaItem>? _remoteResults;
  List<MediaItem>? _browseResults;
  bool _isSearching = false;
  bool _isBrowsing = false;
  int _browseRevision = 0;
  late UnifiedMediaType _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialCategory?.type ?? UnifiedMediaType.all;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadBrowse();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<UnifiedCategory> get _visibleCategories {
    if (widget.categories.isNotEmpty) return widget.categories;
    return const [
      UnifiedCategory(type: UnifiedMediaType.all, sourceCategoryIds: []),
      UnifiedCategory(type: UnifiedMediaType.movie, sourceCategoryIds: []),
      UnifiedCategory(type: UnifiedMediaType.series, sourceCategoryIds: []),
      UnifiedCategory(type: UnifiedMediaType.variety, sourceCategoryIds: []),
      UnifiedCategory(type: UnifiedMediaType.animation, sourceCategoryIds: []),
    ];
  }

  List<String> get _history {
    final values = <String>[..._localHistory, ...widget.history];
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value))
        .take(12)
        .toList(growable: false);
  }

  List<MediaItem> get _localResults {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return widget.items.where((media) {
      if (!_matchesType(media, _selectedType)) return false;
      final searchable = [media.title, media.description, ...media.genres]
          .join(' ')
          .toLowerCase();
      return searchable.contains(query);
    }).toList(growable: false);
  }

  List<MediaItem> _localBrowse(UnifiedMediaType type) {
    if (type == UnifiedMediaType.all) return widget.items;
    return widget.items.where((item) => _matchesType(item, type)).toList();
  }

  bool _matchesType(MediaItem media, UnifiedMediaType type) {
    if (type == UnifiedMediaType.all) return true;
    if (type == UnifiedMediaType.movie) return media.kind == MediaKind.movie;
    if (media.kind != MediaKind.series) return false;
    final text = [media.title, ...media.genres].join(' ').toLowerCase();
    if (type == UnifiedMediaType.variety) {
      return RegExp(r'综艺|真人秀|variety|show').hasMatch(text);
    }
    if (type == UnifiedMediaType.animation) {
      return RegExp(r'动漫|动画|番剧|cartoon|anime').hasMatch(text);
    }
    return !RegExp(r'综艺|真人秀|variety|show|动漫|动画|番剧|cartoon|anime')
        .hasMatch(text);
  }

  Future<void> _loadBrowse() async {
    final revision = ++_browseRevision;
    if (mounted) {
      setState(() {
        _isBrowsing = true;
        _errorMessage = null;
        _browseResults = null;
      });
    }
    try {
      final category = _categoryFor(_selectedType);
      final results = widget.onBrowseCategory == null
          ? _localBrowse(_selectedType)
          : await widget.onBrowseCategory!(category.sourceCategoryIds);
      if (!mounted || revision != _browseRevision || _query.trim().isNotEmpty) {
        return;
      }
      setState(() {
        _browseResults = results;
        _isBrowsing = false;
      });
    } catch (_) {
      if (!mounted || revision != _browseRevision) return;
      setState(() {
        _isBrowsing = false;
        _errorMessage = '资源库加载失败，请检查默认视频源后重试';
      });
    }
  }

  Future<void> _submit([String? value]) async {
    final query = (value ?? _queryController.text).trim();
    if (query.isEmpty) {
      _clearQuery();
      return;
    }
    setState(() {
      _query = query;
      _errorMessage = null;
      _remoteResults = null;
      _localHistory
        ..remove(query)
        ..insert(0, query);
    });
    _queryController
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    _focusNode.unfocus();

    try {
      widget.onSearch(query);
      final search = widget.onRemoteSearch;
      if (search == null) return;
      setState(() => _isSearching = true);
      final category = _categoryFor(_selectedType);
      final results = await search(query, category.sourceCategoryIds);
      if (!mounted || _query != query) return;
      setState(() {
        _remoteResults = results;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = '搜索暂时不可用，请稍后重试';
      });
    }
  }

  UnifiedCategory _categoryFor(UnifiedMediaType type) {
    return _visibleCategories.firstWhere(
      (category) => category.type == type,
      orElse: () => const UnifiedCategory(
        type: UnifiedMediaType.all,
        sourceCategoryIds: [],
      ),
    );
  }

  void _selectType(UnifiedMediaType type) {
    setState(() {
      _selectedType = type;
      _remoteResults = null;
      _errorMessage = null;
    });
    if (_query.trim().isNotEmpty) {
      _submit(_query);
    } else {
      _loadBrowse();
    }
  }

  void _clearQuery() {
    _queryController.clear();
    setState(() {
      _query = '';
      _errorMessage = null;
      _remoteResults = null;
    });
    _loadBrowse();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim();
    final showingSearch = query.isNotEmpty;
    return Scaffold(
      backgroundColor: CineoColors.background,
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('搜索'),
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              sliver: SliverToBoxAdapter(
                child: _SearchField(
                  controller: _queryController,
                  focusNode: _focusNode,
                  onSubmitted: _submit,
                  onChanged: (value) {
                    final leftSubmittedSearch =
                        _query.isNotEmpty && value != _query;
                    setState(() {
                      if (leftSubmittedSearch) {
                        _query = '';
                        _errorMessage = null;
                        _remoteResults = null;
                      }
                    });
                    if (leftSubmittedSearch) _loadBrowse();
                  },
                  onClear: _clearQuery,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _CategorySelector(
                categories: _visibleCategories,
                selectedType: _selectedType,
                onSelected: _selectType,
              ),
            ),
            if (_errorMessage != null)
              SliverToBoxAdapter(
                child: _ErrorState(
                  message: _errorMessage!,
                  onRetry: showingSearch ? () => _submit(query) : _loadBrowse,
                ),
              )
            else if (showingSearch)
              ..._buildResults(query)
            else
              ..._buildBrowse(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBrowse() {
    final history = _history;
    final browse = _browseResults;
    return [
      if (history.isNotEmpty) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Text('最近搜索', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _localHistory.clear()),
                  child: const Text('清除'),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) => ActionChip(
                label: Text(history[index]),
                avatar: const Icon(Icons.history_rounded, size: 16),
                onPressed: () => _submit(history[index]),
              ),
            ),
          ),
        ),
      ],
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Text(
                '${_selectedType.label}资源库',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (browse != null) ...[
                const SizedBox(width: 8),
                Text('${browse.length}',
                    style: const TextStyle(color: CineoColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
      if (_isBrowsing && browse == null)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 64),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (browse == null || browse.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyState(
            icon: Icons.video_library_outlined,
            title: '这个分类还没有内容',
            message: '换一个分类，或检查默认视频源是否可用',
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => BrowseMediaCard(
                media: browse[index],
                onTap: () => widget.onOpenMedia(browse[index]),
              ),
              childCount: browse.length,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 176,
              mainAxisSpacing: 18,
              crossAxisSpacing: 12,
              childAspectRatio: .62,
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildResults(String query) {
    if (_isSearching) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 64),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    final results = _remoteResults ?? _localResults;
    if (results.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyState(
            icon: Icons.search_off_rounded,
            title: '没有找到相关内容',
            message: '换个关键词试试，或检查搜索源是否已开启',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        sliver: SliverToBoxAdapter(
          child: Text(
            '“$query”的搜索结果 · ${results.length}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        sliver: SliverList.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, index) => _SearchResultTile(
            media: results[index],
            onTap: () => widget.onOpenMedia(results[index]),
          ),
        ),
      ),
    ];
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.categories,
    required this.selectedType,
    required this.onSelected,
  });

  final List<UnifiedCategory> categories;
  final UnifiedMediaType selectedType;
  final ValueChanged<UnifiedMediaType> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final category = categories[index];
          return ChoiceChip(
            label: Text(category.type.label),
            selected: category.type == selectedType,
            onSelected: (_) => onSelected(category.type),
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: '搜索电影、剧集、类型',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                tooltip: '清除搜索',
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.media, required this.onTap});

  final MediaItem media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '打开${media.title}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 116),
          decoration: BoxDecoration(
            color: CineoColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              _Poster(url: media.posterUrl),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(media.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 7),
                      Text(
                        '${media.year}  ·  ${media.kind == MediaKind.series ? '剧集' : '电影'}  ·  ${media.rating.toStringAsFixed(1)} 分',
                        style: const TextStyle(
                          color: CineoColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(media.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: CineoColors.textSecondary, height: 1.3)),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 14),
                child: Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 82,
      height: 116,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: CineoColors.surfaceElevated,
          child: Icon(Icons.movie_outlined, color: CineoColors.textSecondary),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: CineoColors.textSecondary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: CineoColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 44, color: CineoColors.textSecondary),
            const SizedBox(height: 12),
            Text(message),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
