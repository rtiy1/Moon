import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'widgets.dart';
import 'search_screen.dart';

/// 分类浏览页（电影/剧集/动漫/综艺），参数语义与 LunaTV 网页端一致：
/// - 非"全部"一级分类 → /api/douban/categories
/// - 一级"全部" → /api/douban/recommends + 多层级筛选
/// - 动漫"每日放送" → /api/bangumi/calendar
class BrowseScreen extends StatefulWidget {
  /// movie | tv | anime | show
  final String kind;
  const BrowseScreen({super.key, required this.kind});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen>
    with AutomaticKeepAliveClientMixin {
  static const _primaryOptions = {
    'movie': ['全部', '热门', '最新', '豆瓣高分', '冷门佳片'],
    'tv': ['最近热门', '全部'],
    'show': ['最近热门', '全部'],
    'anime': ['每日放送', '番剧', '剧场版'],
  };

  static const _secondaryOptions = {
    'movie': ['全部', '华语', '欧美', '韩国', '日本'],
    'tv': ['全部', '国产剧', '欧美剧', '日剧', '韩剧', '动画', '纪录片'],
    'show': ['全部', '国内', '国外'],
    'anime': <String>[],
  };

  // secondary 显示名 → API 值（tv/show 需要映射，movie 直接用中文）
  static const _secondaryApi = {
    'tv': {
      '全部': 'tv', '国产剧': 'tv_domestic', '欧美剧': 'tv_american',
      '日剧': 'tv_japanese', '韩剧': 'tv_korean', '动画': 'tv_animation',
      '纪录片': 'tv_documentary',
    },
    'show': {'全部': 'show', '国内': 'show_domestic', '国外': 'show_foreign'},
  };

  static const _genreOptions = {
    'movie': [
      '全部', '喜剧', '爱情', '动作', '科幻', '悬疑', '犯罪', '惊悚', '冒险',
      '音乐', '历史', '奇幻', '恐怖', '战争', '传记', '歌舞', '武侠', '情色',
      '灾难', '西部', '纪录片', '短片',
    ],
    'tv': [
      '全部', '喜剧', '爱情', '悬疑', '武侠', '古装', '家庭', '犯罪', '科幻',
      '恐怖', '历史', '战争', '动作', '冒险', '传记', '剧情', '奇幻', '惊悚',
      '灾难', '歌舞', '音乐',
    ],
    'show': ['全部', '真人秀', '脱口秀', '音乐', '歌舞'],
    'anime-tv': [
      '全部', '黑色幽默', '历史', '歌舞', '励志', '恶搞', '治愈', '运动',
      '后宫', '情色', '国漫', '人性', '悬疑', '恋爱', '魔幻', '科幻',
    ],
    'anime-movie': [
      '全部', '定格动画', '传记', '美国动画', '爱情', '黑色幽默', '歌舞',
      '儿童', '二次元', '动物', '青春', '历史', '励志', '恶搞', '治愈',
      '运动', '后宫', '情色', '人性', '悬疑', '恋爱', '魔幻', '科幻',
    ],
  };

  static const _regionOptions = [
    '全部', '华语', '欧美', '韩国', '日本', '中国大陆', '美国', '中国香港',
    '中国台湾', '英国', '法国', '德国', '意大利', '西班牙', '印度', '泰国',
    '俄罗斯', '加拿大', '澳大利亚', '爱尔兰', '瑞典', '巴西', '丹麦',
  ];

  static const _yearOptions = [
    '全部', '2025', '2024', '2023', '2022', '2021', '2020', '2019',
    '2010年代', '2000年代', '90年代', '80年代', '70年代', '60年代', '更早',
  ];

  static const _platformOptions = [
    '全部', '腾讯视频', '爱奇艺', '优酷', '湖南卫视', 'Netflix', 'HBO', 'BBC',
    'NHK', 'CBS', 'NBC', 'tvN',
  ];

  static const _sortOptions = ['综合排序', '近期热度', '首播时间', '高分优先'];
  static const _sortValues = {
    '综合排序': 'T',
    '近期热度': 'U',
    '首播时间': 'R',
    '高分优先': 'S',
  };

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  String _primary = '';
  String _secondary = '全部';
  // 多层级筛选（传中文 label 给 API）
  String _genre = '全部';
  String _region = '全部';
  String _year = '全部';
  String _platform = '全部';
  String _sort = '综合排序';
  int _weekday = DateTime.now().weekday; // 1-7

  List<DoubanItem> _items = [];
  List<BangumiItem> _bangumi = [];
  bool _loading = false;
  bool _hasMore = true;
  int _pageStart = 0;
  final _scroll = ScrollController();

  bool get _isRecommendMode =>
      _primary == '全部' ||
      (widget.kind == 'anime' && _primary != '每日放送');

  bool get _isCalendarMode =>
      widget.kind == 'anime' && _primary == '每日放送';

  /// 当前内容类型，决定类型/平台筛选选项
  String get _contentType {
    if (widget.kind == 'anime') {
      return _primary == '番剧' ? 'anime-tv' : 'anime-movie';
    }
    return widget.kind;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _primary =
        _primaryOptions[widget.kind]![widget.kind == 'movie' ? 1 : 0];
    _secondary = _secondaryOptions[widget.kind]?.first ?? '全部';
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >
            _scroll.position.maxScrollExtent - 300 &&
        !_loading &&
        _hasMore &&
        !_isCalendarMode) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _pageStart = 0;
      _hasMore = true;
      _items = [];
      _bangumi = [];
    }
    if (!_hasMore && !reset) return;
    setState(() => _loading = true);

    if (_isCalendarMode) {
      final cal = await Api.bangumiCalendar();
      if (!mounted) return;
      setState(() {
        _bangumi = cal[_weekday] ?? [];
        _loading = false;
        _hasMore = false;
      });
      return;
    }

    List<DoubanItem> list;
    if (_isRecommendMode) {
      list = await Api.doubanRecommends(
        kind: _recommendKind,
        start: _pageStart,
        limit: 25,
        category: _recommendCategory,
        format: _recommendFormat,
        region: _region == '全部' ? null : _region,
        year: _year == '全部' ? null : _year,
        platform: _platform == '全部' ? null : _platform,
        sort: _sortValues[_sort],
        label: _recommendLabel,
      );
    } else {
      list = await Api.doubanCategories(
        kind: _categoryKind,
        category: _categoryValue,
        type: _secondaryApiValue,
        start: _pageStart,
        limit: 25,
      );
    }

    if (!mounted) return;
    setState(() {
      _items = reset ? list : [..._items, ...list];
      _pageStart += list.length;
      _hasMore = list.length >= 25;
      _loading = false;
    });
  }

  // categories 接口参数
  String get _categoryKind => widget.kind == 'movie' ? 'movie' : 'tv';

  /// tv→'tv', show→'show', movie→选中的一级分类
  String get _categoryValue =>
      widget.kind == 'movie' ? _primary : widget.kind;

  String get _secondaryApiValue =>
      _secondaryApi[widget.kind]?[_secondary] ?? _secondary;

  // recommends 接口参数
  String get _recommendKind {
    if (widget.kind == 'anime') {
      return _primary == '番剧' ? 'tv' : 'movie';
    }
    if (widget.kind == 'movie') return 'movie';
    return 'tv'; // tv / show 都走 kind=tv
  }

  String? get _recommendFormat {
    if (widget.kind == 'show') return '综艺';
    if (widget.kind == 'tv') return '电视剧';
    if (widget.kind == 'anime' && _primary == '番剧') return '电视剧';
    return null;
  }

  String? get _recommendCategory {
    if (widget.kind == 'anime') return '动画';
    return _genre == '全部' ? null : _genre;
  }

  String? get _recommendLabel {
    // 动漫的类型筛选走 label 字段
    if (widget.kind == 'anime') {
      return _genre == '全部' ? null : _genre;
    }
    return null;
  }

  bool get _showPlatform =>
      _isRecommendMode &&
      (widget.kind == 'tv' ||
          widget.kind == 'show' ||
          _contentType == 'anime-tv');

  void _openItem(String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchScreen(initialQuery: title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final titles = {
      'movie': '电影',
      'tv': '剧集',
      'anime': '动漫',
      'show': '综艺'
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[widget.kind] ?? '',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPrimaryChips(),
          if ((_secondaryOptions[widget.kind] ?? []).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ChipRow(
                label: '分类',
                options: _secondaryOptions[widget.kind]!,
                selected: _secondary,
                onSelect: (v) {
                  setState(() => _secondary = v);
                  _load(reset: true);
                },
              ),
            ),
          if (_isRecommendMode) _buildFilterChips(),
          if (_isCalendarMode) _buildWeekdayChips(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildPrimaryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _primaryOptions[widget.kind]!.length,
        separatorBuilder: (_, i) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final o = _primaryOptions[widget.kind]![i];
          final sel = o == _primary;
          return GestureDetector(
            onTap: () {
              setState(() => _primary = o);
              _load(reset: true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel
                    ? kAccent
                    : Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(o,
                  style: TextStyle(
                      fontSize: 13,
                      color: sel ? Colors.white : null,
                      fontWeight:
                          sel ? FontWeight.w600 : FontWeight.normal)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          ChipRow(
            label: '类型',
            options: _genreOptions[_contentType]!,
            selected: _genre,
            onSelect: (v) {
              setState(() => _genre = v);
              _load(reset: true);
            },
          ),
          ChipRow(
            label: '地区',
            options: _regionOptions,
            selected: _region,
            onSelect: (v) {
              setState(() => _region = v);
              _load(reset: true);
            },
          ),
          ChipRow(
            label: '年代',
            options: _yearOptions,
            selected: _year,
            onSelect: (v) {
              setState(() => _year = v);
              _load(reset: true);
            },
          ),
          if (_showPlatform)
            ChipRow(
              label: '平台',
              options: _platformOptions,
              selected: _platform,
              onSelect: (v) {
                setState(() => _platform = v);
                _load(reset: true);
              },
            ),
          ChipRow(
            label: '排序',
            options: _sortOptions,
            selected: _sort,
            onSelect: (v) {
              setState(() => _sort = v);
              _load(reset: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ChipRow(
        label: '星期',
        options: _weekdays,
        selected: _weekdays[_weekday - 1],
        onSelect: (v) {
          setState(() => _weekday = _weekdays.indexOf(v) + 1);
          _load(reset: true);
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isCalendarMode) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_bangumi.isEmpty) {
        return const Center(child: Text('今日暂无放送'));
      }
      return PosterGrid(
        children: [
          for (final b in _bangumi)
            VideoCard(
              title: b.displayName,
              poster: b.image,
              subtitle: b.score > 0 ? '评分 ${b.score}' : b.airDate,
              onTap: () => _openItem(b.displayName),
            ),
        ],
      );
    }

    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:
            (MediaQuery.of(context).size.width ~/ 120).clamp(3, 6),
        childAspectRatio: 0.58,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _items.length) {
          return const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final d = _items[i];
        return VideoCard(
          title: d.title,
          poster: d.poster,
          subtitle: d.rate.isNotEmpty ? '评分 ${d.rate}' : d.year,
          badge: d.rate,
          onTap: () => _openItem(d.title),
        );
      },
    );
  }
}
