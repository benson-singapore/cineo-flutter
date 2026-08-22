import 'package:flutter/material.dart';

import '../../core/platform/adaptive_navigation.dart';
import '../../core/models/media.dart';
import '../../core/models/paged_media.dart';
import '../../core/theme/cineo_theme.dart';
import '../../data/remote/media_category_adapter.dart';
import '../../shared/widgets/media_poster_card.dart';
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
    this.libraryMode = false,
    this.onOpenSearch,
  });

  final List<MediaItem> items;
  final List<String> history;
  final ValueChanged<String> onSearch;
  final ValueChanged<MediaItem> onOpenMedia;
  final Future<PagedMedia> Function(
      String query, List<String> categoryIds, int page)? onRemoteSearch;
  final Future<PagedMedia> Function(List<String> categoryIds, int page)?
      onBrowseCategory;
  final List<UnifiedCategory> categories;
  final UnifiedCategory? initialCategory;
  final bool libraryMode;
  final VoidCallback? onOpenSearch;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _queryController = TextEditingController();
  final _focusNode = FocusNode();
  final _localHistory = <String>[];
  final _scrollController = ScrollController();
  String _query = '';
  String? _errorMessage;
  String? _paginationError;
  List<MediaItem> _remoteResults = const [];
  List<MediaItem> _browseResults = const [];
  bool _isSearching = false;
  bool _isBrowsing = false;
  bool _isLoadingMore = false;
  bool _hasMoreSearch = false;
  bool _hasMoreBrowse = false;
  int _searchPage = 0;
  int _browsePage = 0;
  int _revision = 0;
  bool _showScrollToTop = false;
  final Map<String, _SubcategoryBrowseState> _subcategoryBrowse = {};
  late UnifiedMediaType _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialCategory?.type ?? UnifiedMediaType.all;
    _scrollController
      ..addListener(_onScroll)
      ..addListener(_updateScrollToTopVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCurrentBrowse();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 360 ||
        _isLoadingMore) {
      return;
    }
    if (_query.trim().isEmpty &&
        !_usesSecondaryBrowse &&
        _hasMoreBrowse &&
        !_isBrowsing) {
      _loadBrowsePage(_browsePage + 1);
    } else if (_query.trim().isNotEmpty && _hasMoreSearch && !_isSearching) {
      _loadSearchPage(_searchPage + 1, _query.trim());
    }
  }

  void _updateScrollToTopVisibility() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > 24;
    if (shouldShow != _showScrollToTop && mounted) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  void _refreshScrollToTopVisibilityAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollToTopVisibility();
    });
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients || _scrollController.offset <= 0) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
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

  Future<PagedMedia> _browsePageRequest(
      List<String> categoryIds, int page) async {
    final callback = widget.onBrowseCategory;
    if (callback == null) {
      final items = _localBrowse(_selectedType);
      return _localPage(items, page);
    }
    return callback(categoryIds, page);
  }

  Future<PagedMedia> _searchPageRequest(
      String query, List<String> categoryIds, int page) async {
    final callback = widget.onRemoteSearch;
    if (callback == null) {
      return _localPage(_localResults, page);
    }
    return callback(query, categoryIds, page);
  }

  PagedMedia _localPage(List<MediaItem> items, int page) {
    return PagedMedia(
      items: page == 1 ? items : const [],
      page: page,
      pageCount: 1,
      total: items.length,
      limit: items.length,
      hasMore: false,
    );
  }

  List<MediaItem> _appendUnique(List<MediaItem> current, List<MediaItem> next) {
    final seen = current.map((item) => item.id).toSet();
    return [
      ...current,
      ...next.where((item) => seen.add(item.id)),
    ];
  }

  Future<void> _loadBrowse({bool preserveResults = false}) async {
    final revision = ++_revision;
    if (mounted) {
      setState(() {
        _isBrowsing = true;
        _errorMessage = null;
        _paginationError = null;
        if (!preserveResults) {
          _browseResults = const [];
          _browsePage = 0;
          _hasMoreBrowse = false;
        }
      });
    }
    await _loadBrowsePage(1, revision: revision);
  }

  UnifiedCategory get _selectedCategory => _categoryFor(_selectedType);

  bool get _usesSecondaryBrowse =>
      _query.trim().isEmpty && _selectedCategory.subcategories.length > 1;

  String _subcategoryKey(UnifiedSubcategory category) =>
      '${_selectedType.name}:${category.id}';

  Future<void> _loadCurrentBrowse({bool force = false}) {
    return _usesSecondaryBrowse
        ? _loadSubcategoryBrowse(force: force)
        : _loadBrowse(preserveResults: !force);
  }

  Future<void> _loadSubcategoryBrowse({bool force = false}) async {
    final category = _selectedCategory;
    final pending = category.subcategories.where((subcategory) {
      return force ||
          !_subcategoryBrowse.containsKey(_subcategoryKey(subcategory));
    }).toList(growable: false);
    if (pending.isEmpty) return;

    final revision = ++_revision;
    setState(() {
      for (final subcategory in pending) {
        final key = _subcategoryKey(subcategory);
        final previous = _subcategoryBrowse[key];
        _subcategoryBrowse[key] = _SubcategoryBrowseState(
          items: previous?.items ?? const [],
          loading: true,
        );
      }
      _errorMessage = null;
      _paginationError = null;
    });

    final results =
        await Future.wait<(UnifiedSubcategory, PagedMedia?, Object?)>(
      pending.map((subcategory) async {
        try {
          final page = await _browsePageRequest(
            subcategory.sourceCategoryIds,
            1,
          );
          return (subcategory, page, null);
        } catch (error) {
          return (subcategory, null, error);
        }
      }),
    );
    if (!mounted || revision != _revision || !_usesSecondaryBrowse) return;
    setState(() {
      for (final result in results) {
        final subcategory = result.$1;
        final page = result.$2;
        final error = result.$3;
        final key = _subcategoryKey(subcategory);
        final previous = _subcategoryBrowse[key];
        _subcategoryBrowse[key] = _SubcategoryBrowseState(
          items: page?.items ?? previous?.items ?? const [],
          loading: false,
          error: error,
        );
      }
    });
  }

  Future<void> _loadBrowsePage(int page, {int? revision}) async {
    final activeRevision = revision ?? _revision;
    if (page == 1 && !_isBrowsing) {
      setState(() => _isBrowsing = true);
    }
    if (page > 1) {
      if (_isLoadingMore || !_hasMoreBrowse) return;
      setState(() {
        _isLoadingMore = true;
        _paginationError = null;
      });
    }
    try {
      final category = _categoryFor(_selectedType);
      final result = await _browsePageRequest(category.sourceCategoryIds, page);
      if (!mounted || activeRevision != _revision || _query.trim().isNotEmpty) {
        return;
      }
      setState(() {
        _browseResults = page == 1
            ? _appendUnique(const [], result.items)
            : _appendUnique(_browseResults, result.items);
        _browsePage = result.page;
        _hasMoreBrowse = result.hasMore;
        _isBrowsing = false;
        _isLoadingMore = false;
        _paginationError = null;
      });
      _refreshScrollToTopVisibilityAfterLayout();
    } catch (_) {
      if (!mounted || activeRevision != _revision) return;
      setState(() {
        if (page == 1) {
          _isBrowsing = false;
          if (_browseResults.isEmpty) {
            _errorMessage = '资源库加载失败，请检查默认视频源后重试';
          }
        } else {
          _isLoadingMore = false;
          _paginationError = '下一页加载失败';
        }
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
      _paginationError = null;
      _remoteResults = const [];
      _searchPage = 0;
      _hasMoreSearch = false;
      _revision++;
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
      setState(() => _isSearching = true);
      await _loadSearchPage(1, query, revision: _revision);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = '搜索暂时不可用，请稍后重试';
      });
    }
  }

  Future<void> _loadSearchPage(int page, String query, {int? revision}) async {
    final activeRevision = revision ?? _revision;
    if (page > 1) {
      if (_isLoadingMore || !_hasMoreSearch) return;
      setState(() {
        _isLoadingMore = true;
        _paginationError = null;
      });
    }
    try {
      final category = _categoryFor(_selectedType);
      final result =
          await _searchPageRequest(query, category.sourceCategoryIds, page);
      if (!mounted ||
          activeRevision != _revision ||
          _query.trim() != query.trim()) return;
      setState(() {
        _remoteResults = page == 1
            ? _appendUnique(const [], result.items)
            : _appendUnique(_remoteResults, result.items);
        _searchPage = result.page;
        _hasMoreSearch = result.hasMore;
        _isSearching = false;
        _isLoadingMore = false;
        _paginationError = null;
      });
      _refreshScrollToTopVisibilityAfterLayout();
    } catch (_) {
      if (!mounted || activeRevision != _revision) return;
      setState(() {
        if (page == 1) {
          _isSearching = false;
          if (_remoteResults.isEmpty) {
            _errorMessage = '搜索暂时不可用，请稍后重试';
          }
        } else {
          _isLoadingMore = false;
          _paginationError = '下一页加载失败';
        }
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
      _remoteResults = const [];
      _errorMessage = null;
      _paginationError = null;
      _revision++;
    });
    if (_query.trim().isNotEmpty) {
      _submit(_query);
    } else {
      _loadCurrentBrowse();
    }
  }

  void _clearQuery() {
    _queryController.clear();
    setState(() {
      _query = '';
      _errorMessage = null;
      _paginationError = null;
      _remoteResults = const [];
      _revision++;
    });
    _loadCurrentBrowse();
    _focusNode.requestFocus();
  }

  Future<void> _refreshCurrent() {
    final query = _query.trim();
    if (query.isNotEmpty) {
      return _loadSearchPage(1, query, revision: _revision);
    }
    return _loadCurrentBrowse(force: true);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = _query.trim();
    final showingSearch = query.isNotEmpty;
    return Scaffold(
      backgroundColor: CineoColors.background,
      appBar: AppBar(
        titleSpacing: 20,
        title: Text(widget.libraryMode ? '片库' : '搜索'),
        actions: widget.libraryMode
            ? [
                IconButton(
                  onPressed: widget.onOpenSearch,
                  tooltip: '搜索',
                  icon: const Icon(Icons.search_rounded),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RefreshIndicator(
              onRefresh: _refreshCurrent,
              child: CustomScrollView(
                key: PageStorageKey(
                  widget.libraryMode
                      ? 'cineo-library-scroll'
                      : 'cineo-search-scroll',
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  if (!widget.libraryMode)
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
                                _remoteResults = const [];
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
                        onRetry:
                            showingSearch ? () => _submit(query) : _loadBrowse,
                      ),
                    )
                  else if (showingSearch)
                    ..._buildResults(query)
                  else
                    ..._buildBrowse(),
                  const SliverToBoxAdapter(child: SizedBox(height: 92)),
                ],
              ),
            ),
            if (widget.libraryMode && _showScrollToTop)
              Positioned(
                right: 16,
                // The shell's glass navigation occupies its own bottom area.
                // Keep the action just above it without leaving a large gap.
                bottom: 24,
                child: FloatingActionButton.small(
                  onPressed: _scrollToTop,
                  tooltip: '回到顶部',
                  child: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: !widget.libraryMode && _showScrollToTop
          ? FloatingActionButton.small(
              onPressed: _scrollToTop,
              tooltip: '回到顶部',
              child: const Icon(Icons.keyboard_arrow_up_rounded),
            )
          : null,
    );
  }

  List<Widget> _buildBrowse() {
    if (_usesSecondaryBrowse) return _buildSubcategoryBrowse();
    final history = widget.libraryMode ? const <String>[] : _history;
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
              ...[
                const SizedBox(width: 8),
                Text('${browse.length}',
                    style: const TextStyle(color: CineoColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
      if (_isBrowsing && browse.isNotEmpty)
        const SliverToBoxAdapter(
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (_isBrowsing && browse.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 64),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (browse.isEmpty)
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
      if (_isLoadingMore || _paginationError != null)
        SliverToBoxAdapter(
            child: _PaginationFooter(
          loading: _isLoadingMore,
          error: _paginationError,
          onRetry: () => _loadBrowsePage(_browsePage + 1),
        )),
    ];
  }

  List<Widget> _buildResults(String query) {
    if (_isSearching && _remoteResults.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 64),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    final results = _remoteResults.isNotEmpty || widget.onRemoteSearch != null
        ? _remoteResults
        : _localResults;
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
      if (_isSearching)
        const SliverToBoxAdapter(
          child: LinearProgressIndicator(minHeight: 2),
        ),
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
      if (_isLoadingMore || _paginationError != null)
        SliverToBoxAdapter(
            child: _PaginationFooter(
          loading: _isLoadingMore,
          error: _paginationError,
          onRetry: () => _loadSearchPage(_searchPage + 1, query),
        )),
    ];
  }

  List<Widget> _buildSubcategoryBrowse() {
    final category = _selectedCategory;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
        sliver: SliverToBoxAdapter(
          child: Text(
            '${category.type.label}分类',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
      for (final subcategory in category.subcategories)
        SliverToBoxAdapter(
          child: _SubcategoryRail(
            category: subcategory,
            state: _subcategoryBrowse[_subcategoryKey(subcategory)] ??
                const _SubcategoryBrowseState(loading: true),
            onOpenMedia: widget.onOpenMedia,
            onSeeAll: () => _openSubcategory(subcategory),
            onRetry: () => _loadSubcategoryBrowse(force: true),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 28)),
    ];
  }

  void _openSubcategory(UnifiedSubcategory category) {
    final state = _subcategoryBrowse[_subcategoryKey(category)];
    Navigator.of(context).push<void>(
      adaptivePageRoute(
        context,
        builder: (_) => CategoryBrowseScreen(
          title: category.name,
          initialItems: state?.items ?? const [],
          onOpenMedia: widget.onOpenMedia,
          onLoad: (page) =>
              _browsePageRequest(category.sourceCategoryIds, page),
        ),
      ),
    );
  }
}

class _SubcategoryBrowseState {
  const _SubcategoryBrowseState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final List<MediaItem> items;
  final bool loading;
  final Object? error;
}

class _SubcategoryRail extends StatelessWidget {
  const _SubcategoryRail({
    required this.category,
    required this.state,
    required this.onOpenMedia,
    required this.onSeeAll,
    required this.onRetry,
  });

  final UnifiedSubcategory category;
  final _SubcategoryBrowseState state;
  final ValueChanged<MediaItem> onOpenMedia;
  final VoidCallback onSeeAll;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final items = state.items;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  key: ValueKey('subcategory-see-all-${category.id}'),
                  tooltip: '查看全部${category.name}',
                  onPressed: onSeeAll,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (state.loading && items.isEmpty)
            const SizedBox(
              height: 236,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.error != null && items.isEmpty)
            SizedBox(
              height: 116,
              child: Center(
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('${category.name}加载失败，重试'),
                ),
              ),
            )
          else if (items.isEmpty)
            SizedBox(
              height: 88,
              child: Center(
                child: Text(
                  '${category.name}暂无内容',
                  style: const TextStyle(color: CineoColors.textSecondary),
                ),
              ),
            )
          else
            SizedBox(
              height: 268,
              child: Stack(
                children: [
                  ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, index) => MediaPosterCard(
                      media: items[index],
                      onTap: () => onOpenMedia(items[index]),
                    ),
                  ),
                  if (state.loading)
                    const Positioned(
                      top: 0,
                      left: 20,
                      right: 20,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
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

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(error!),
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
