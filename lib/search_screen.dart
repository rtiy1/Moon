import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'widgets.dart';
import 'player_screen.dart';

/// 搜索页：SSE 流式搜索（按源逐步出结果）+ 聚合视图 + 历史记录 + 搜索建议。
class SearchScreen extends StatefulWidget {
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  List<String> _history = [];
  List<String> _suggestions = [];

  /// key=source，按源分组的结果
  final Map<String, _SourceResults> _bySource = {};
  int _totalSources = 0;
  int _doneSources = 0;
  bool _searching = false;
  bool _aggregated = true; // 聚合视图开关
  StreamSubscription<SearchEvent>? _sub;
  Timer? _suggestTimer;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _ctrl.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _sub?.cancel();
    _suggestTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h = await Api.searchHistory();
    if (mounted) setState(() => _history = h);
  }

  void _onQueryChanged(String q) {
    _suggestTimer?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 300), () async {
      final s = await Api.searchSuggestions(q);
      if (mounted && _ctrl.text == q) {
        setState(() => _suggestions = s);
      }
    });
  }

  void _runSearch() {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    _focus.unfocus();
    Api.addSearchHistory(q);
    setState(() {
      _bySource.clear();
      _totalSources = 0;
      _doneSources = 0;
      _searching = true;
      _suggestions = [];
    });
    _sub?.cancel();
    _sub = Api.searchStream(q).listen(
      (e) {
        if (!mounted) return;
        setState(() {
          switch (e) {
            case SearchStartEvent():
              _totalSources = e.totalSources;
            case SearchSourceResultEvent():
              _bySource[e.source] = _SourceResults(e.sourceName, e.results);
              _doneSources++;
            case SearchSourceErrorEvent():
              _doneSources++;
            case SearchCompleteEvent():
              _searching = false;
          }
        });
      },
      onDone: () {
        if (mounted) setState(() => _searching = false);
      },
      onError: (_) {
        if (mounted) setState(() => _searching = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          focusNode: _focus,
          autofocus: widget.initialQuery == null,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索影片、剧集、综艺...',
            border: InputBorder.none,
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() {
                        _bySource.clear();
                        _suggestions = [];
                        _searching = false;
                      });
                      _sub?.cancel();
                    },
                  )
                : null,
          ),
          onChanged: _onQueryChanged,
          onSubmitted: (_) => _runSearch(),
        ),
        actions: [
          if (_bySource.isNotEmpty)
            IconButton(
              tooltip: _aggregated ? '按源显示' : '聚合显示',
              icon: Icon(
                  _aggregated ? Icons.grid_view : Icons.view_list),
              onPressed: () =>
                  setState(() => _aggregated = !_aggregated),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_suggestions.isNotEmpty && !_searching) {
      return _buildSuggestions();
    }
    if (_bySource.isEmpty && !_searching) {
      return _buildHistory();
    }
    return _buildResults();
  }

  Widget _buildSuggestions() {
    return ListView.builder(
      itemCount: _suggestions.length,
      itemBuilder: (_, i) => ListTile(
        leading: const Icon(Icons.search, size: 18),
        title: Text(_suggestions[i]),
        dense: true,
        onTap: () {
          _ctrl.text = _suggestions[i];
          _runSearch();
        },
      ),
    );
  }

  Widget _buildHistory() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_history.isNotEmpty) ...[
          Row(
            children: [
              Text('搜索历史',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  await Api.clearSearchHistory();
                  _loadHistory();
                },
                child: Text('清空',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey[500])),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in _history)
                GestureDetector(
                  onTap: () {
                    _ctrl.text = h;
                    _runSearch();
                  },
                  onLongPress: () async {
                    await Api.deleteSearchHistory(h);
                    _loadHistory();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(h, style: const TextStyle(fontSize: 13)),
                  ),
                ),
            ],
          ),
        ],
        if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 120),
            child: Center(child: Text('输入关键词开始搜索')),
          ),
      ],
    );
  }

  Widget _buildResults() {
    final all = [
      for (final s in _bySource.values) ...s.items,
    ];
    return Column(
      children: [
        if (_searching || _doneSources < _totalSources)
          LinearProgressIndicator(
            value: _totalSources > 0 ? _doneSources / _totalSources : null,
            minHeight: 2,
            color: kAccent,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          child: _aggregated
              ? _buildAggregated(all)
              : _buildBySource(all),
        ),
      ],
    );
  }

  Widget _buildAggregated(List<VodItem> all) {
    final agg = AggregatedItem.aggregate(all);
    if (agg.isEmpty && !_searching) {
      return const Center(child: Text('未找到相关资源'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:
            (MediaQuery.of(context).size.width ~/ 120).clamp(3, 6),
        childAspectRatio: 0.58,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: agg.length,
      itemBuilder: (_, i) {
        final a = agg[i];
        return VideoCard(
          title: a.title,
          poster: a.poster,
          subtitle: '${a.year} · ${a.sources.length}个源',
          badge: a.typeName,
          onTap: () => _openDetail(a),
        );
      },
    );
  }

  Widget _buildBySource(List<VodItem> all) {
    if (all.isEmpty && !_searching) {
      return const Center(child: Text('未找到相关资源'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _bySource.length,
      itemBuilder: (_, i) {
        final src = _bySource.values.elementAt(i);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('${src.name} · ${src.items.length}个结果',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: src.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, j) {
                  final v = src.items[j];
                  return SizedBox(
                    width: 112,
                    child: VideoCard(
                      title: v.title,
                      poster: v.poster,
                      subtitle: '${v.year} · ${v.episodeCount}集',
                      onTap: () => _openPlayer(v),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 聚合条目 → 选源底部弹窗 → 播放
  void _openDetail(AggregatedItem a) {
    if (a.sources.length == 1) {
      _openPlayer(a.sources.first);
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${a.title} · 选择播放源',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: a.sources.length,
                itemBuilder: (_, i) {
                  final v = a.sources[i];
                  return ListTile(
                    title: Text(v.sourceName),
                    subtitle: Text('共${v.episodeCount}集'),
                    trailing: const Icon(Icons.play_circle_outline),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openPlayer(v);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPlayer(VodItem v) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        source: v.source,
        id: v.id,
        title: v.title,
        year: v.year,
        searchTitle: _ctrl.text.trim(),
      ),
    ));
  }
}

class _SourceResults {
  final String name;
  final List<VodItem> items;
  _SourceResults(this.name, this.items);
}
