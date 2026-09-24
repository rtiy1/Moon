import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'session.dart';
import 'widgets.dart';
import 'search_screen.dart';
import 'browse_screen.dart';
import 'live_screen.dart';
import 'player_screen.dart';
import 'settings_sheet.dart';

/// 主框架：底部导航 [首页/电影/剧集/动漫/综艺/直播]
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;
  final _pageCtrl = PageController();

  static const _titles = ['首页', '电影', '剧集', '动漫', '综艺', '直播'];
  static const _icons = [
    Icons.home_outlined,
    Icons.movie_outlined,
    Icons.tv_outlined,
    Icons.animation_outlined,
    Icons.mic_external_on_outlined,
    Icons.live_tv_outlined,
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageCtrl,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _navIndex = i),
        children: const [
          HomeTab(),
          BrowseScreen(kind: 'movie'),
          BrowseScreen(kind: 'tv'),
          BrowseScreen(kind: 'anime'),
          BrowseScreen(kind: 'show'),
          LiveScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => _pageCtrl.jumpToPage(i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (var i = 0; i < _titles.length; i++)
            NavigationDestination(
                icon: Icon(_icons[i]), label: _titles[i]),
        ],
      ),
    );
  }
}

/// 首页页签：推荐 / 播放记录 / 收藏夹
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  int _tab = 0; // 0 推荐 / 1 播放记录 / 2 收藏夹
  String _siteName = 'Moon';

  List<PlayRecord> _records = [];
  List<FavoriteItem> _favorites = [];
  List<DoubanItem> _hotMovies = [];
  List<DoubanItem> _hotTv = [];
  List<DoubanItem> _hotShows = [];
  List<BangumiItem> _todayBangumi = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    final name = await Session.siteName;
    if (name != null) _siteName = name;

    final results = await Future.wait([
      Api.playRecords(),
      Api.favorites(),
      Api.douban(type: 'movie', tag: '热门', pageSize: 12),
      Api.douban(type: 'tv', tag: '热门', pageSize: 12),
      Api.douban(type: 'tv', tag: '综艺', pageSize: 12),
      Api.bangumiCalendar(),
    ]);
    if (!mounted) return;
    setState(() {
      _records = results[0] as List<PlayRecord>;
      _favorites = results[1] as List<FavoriteItem>;
      _hotMovies = results[2] as List<DoubanItem>;
      _hotTv = results[3] as List<DoubanItem>;
      _hotShows = results[4] as List<DoubanItem>;
      final cal = results[5] as Map<int, List<BangumiItem>>;
      _todayBangumi = cal[DateTime.now().weekday] ?? [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_siteName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const SettingsSheet(),
            ).then((_) => setState(() {})),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('推荐')),
                ButtonSegment(value: 1, label: Text('播放记录')),
                ButtonSegment(value: 2, label: Text('收藏夹')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) =>
                  setState(() => _tab = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: kAccent.withValues(alpha: 0.2),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: switch (_tab) {
          1 => _buildRecords(),
          2 => _buildFavorites(),
          _ => _buildRecommend(),
        },
      ),
    );
  }

  Widget _buildRecommend() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (_records.isNotEmpty)
          SectionRow(
            title: '继续观看',
            children: [
              for (final r in _records.take(15))
                VideoCard(
                  title: r.title,
                  poster: r.cover,
                  subtitle: '${r.sourceName} · 第${r.index}集',
                  progress: r.progress,
                  onTap: () => _openRecord(r),
                  onLongPress: () => _confirmDelete(
                    '删除该播放记录？',
                    () async {
                      await Api.deletePlayRecord(r.key);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        if (_todayBangumi.isNotEmpty)
          SectionRow(
            title: '每日放送',
            children: [
              for (final b in _todayBangumi.take(15))
                VideoCard(
                  title: b.displayName,
                  poster: b.image,
                  subtitle: b.score > 0 ? '评分 ${b.score}' : b.airDate,
                  onTap: () => _searchAndPlay(b.displayName),
                ),
            ],
          ),
        if (_hotMovies.isNotEmpty)
          SectionRow(
            title: '热门电影',
            children: [
              for (final d in _hotMovies)
                VideoCard(
                  title: d.title,
                  poster: d.poster,
                  subtitle: d.rate.isNotEmpty ? '评分 ${d.rate}' : d.year,
                  badge: d.rate,
                  onTap: () => _searchAndPlay(d.title),
                ),
            ],
          ),
        if (_hotTv.isNotEmpty)
          SectionRow(
            title: '热门剧集',
            children: [
              for (final d in _hotTv)
                VideoCard(
                  title: d.title,
                  poster: d.poster,
                  subtitle: d.rate.isNotEmpty ? '评分 ${d.rate}' : d.year,
                  badge: d.rate,
                  onTap: () => _searchAndPlay(d.title),
                ),
            ],
          ),
        if (_hotShows.isNotEmpty)
          SectionRow(
            title: '热门综艺',
            children: [
              for (final d in _hotShows)
                VideoCard(
                  title: d.title,
                  poster: d.poster,
                  subtitle: d.rate.isNotEmpty ? '评分 ${d.rate}' : d.year,
                  badge: d.rate,
                  onTap: () => _searchAndPlay(d.title),
                ),
            ],
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRecords() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_records.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(child: Text('暂无播放记录')),
        ],
      );
    }
    return PosterGrid(
      children: [
        for (final r in _records)
          VideoCard(
            title: r.title,
            poster: r.cover,
            subtitle: '看到第${r.index}集',
            progress: r.progress,
            onTap: () => _openRecord(r),
            onLongPress: () => _confirmDelete(
              '删除该播放记录？',
              () async {
                await Api.deletePlayRecord(r.key);
                _load();
              },
            ),
          ),
      ],
    );
  }

  Widget _buildFavorites() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_favorites.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(child: Text('暂无收藏')),
        ],
      );
    }
    return PosterGrid(
      children: [
        for (final f in _favorites)
          VideoCard(
            title: f.title,
            poster: f.cover,
            subtitle: '${f.sourceName} · 共${f.totalEpisodes}集',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlayerScreen(
                source: f.source,
                id: f.id,
                title: f.title,
                year: f.year,
                searchTitle: f.searchTitle.isNotEmpty
                    ? f.searchTitle
                    : f.title,
              ),
            )),
            onLongPress: () => _confirmDelete(
              '取消收藏该影片？',
              () async {
                await Api.removeFavorite(f.key);
                _load();
              },
            ),
          ),
      ],
    );
  }

  void _openRecord(PlayRecord r) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        source: r.source,
        id: r.id,
        title: r.title,
        year: r.year,
        searchTitle:
            r.searchTitle.isNotEmpty ? r.searchTitle : r.title,
        episodeIndex: r.index - 1,
        startAtSeconds: r.playTime,
      ),
    ));
  }

  void _searchAndPlay(String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchScreen(initialQuery: title),
    ));
  }

  Future<void> _confirmDelete(String msg, Future<void> Function() action) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await action();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
