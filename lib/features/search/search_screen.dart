import 'package:flutter/material.dart';

import '../../core/models/media.dart';
import '../../core/theme/cineo_theme.dart';
import '../../data/remote/media_category_adapter.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.items,
    required this.history,
    required this.onSearch,
    required this.onOpenMedia,
    this.onRemoteSearch,
    this.categories = const [],
  });

  final List<MediaItem> items;
  final List<String> history;
  final ValueChanged<String> onSearch;
  final ValueChanged<MediaItem> onOpenMedia;
  final Future<List<MediaItem>> Function(String query, List<String> categoryIds)?
      onRemoteSearch;
  final List<UnifiedCategory> categories;

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
  bool _isSearching = false;
  UnifiedMediaType _selectedType = UnifiedMediaType.all;

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
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
      if (_selectedType == UnifiedMediaType.movie && media.kind != MediaKind.movie) return false;
      if ((_selectedType == UnifiedMediaType.series ||
              _selectedType == UnifiedMediaType.variety ||
              _selectedType == UnifiedMediaType.animation) &&
          media.kind != MediaKind.series) {
        return false;
      }
      final searchable = [
        media.title,
        media.description,
        ...media.genres,
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList(growable: false);
  }

  Future<void> _submit([String? value]) async {
    final query = (value ?? _queryController.text).trim();
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _errorMessage = null;
        _remoteResults = null;
      });
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
      if (widget.onRemoteSearch != null) {
        setState(() => _isSearching = true);
        final category = _categoryFor(_selectedType);
        final results = await widget.onRemoteSearch!(query, category.sourceCategoryIds);
        if (!mounted || _query != query) return;
        setState(() {
          _remoteResults = results;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = '搜索暂时不可用，请稍后重试';
      });
    }
  }

  UnifiedCategory _categoryFor(UnifiedMediaType type) {
    return widget.categories.firstWhere(
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
    });
    if (_query.trim().isNotEmpty) {
      _submit(_query);
    }
  }

  void _clearQuery() {
    _queryController.clear();
    setState(() {
      _query = '';
      _errorMessage = null;
      _remoteResults = null;
    });
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
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                  setState(() => _query = value);
                },
                onClear: _clearQuery,
              )),
            ),
            if (widget.categories.length > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final category = widget.categories[index];
                      return ChoiceChip(
                        label: Text(category.type.label),
                        selected: category.type == _selectedType,
                        onSelected: (_) => _selectType(category.type),
                      );
                    },
                  ),
                ),
              ),
            if (_errorMessage != null)
              SliverToBoxAdapter(
                  child: _ErrorState(
                message: _errorMessage!,
                onRetry: () => _submit(query),
              ))
            else if (showingSearch)
              ..._buildResults(query)
            else
              ..._buildHistory(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildResults(String query) {
    if (_isSearching) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final results = _remoteResults ?? _localResults;
    if (results.isEmpty) {
      return [
        const SliverFillRemaining(
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

  List<Widget> _buildHistory() {
    final history = _history;
    if (history.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyState(
            icon: Icons.movie_filter_outlined,
            title: '开始探索',
            message: '搜索电影、剧集或类型，发现下一部想看的内容',
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Text('最近搜索', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _localHistory.clear()),
                child: const Text('清除本次'),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        sliver: SliverList.builder(
          itemCount: history.length,
          itemBuilder: (_, index) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_rounded,
                color: CineoColors.textSecondary),
            title: Text(history[index]),
            trailing: const Icon(Icons.north_west_rounded, size: 18),
            onTap: () => _submit(history[index]),
          ),
        ),
      ),
    ];
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
  const _EmptyState(
      {required this.icon, required this.title, required this.message});

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
