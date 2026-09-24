/// 数据模型 —— 与 LunaTV/MoonTV 后端 API 返回结构对应。

/// 搜索结果 / 详情（/api/search、/api/detail、/api/search/one）
class VodItem {
  final String id;
  final String title;
  final String poster;
  final List<String> episodes;
  final List<String> episodeTitles;
  final String source;
  final String sourceName;
  final String year;
  final String desc;
  final String typeName;
  final String className;
  final int doubanId;

  const VodItem({
    required this.id,
    required this.title,
    this.poster = '',
    this.episodes = const [],
    this.episodeTitles = const [],
    this.source = '',
    this.sourceName = '',
    this.year = '',
    this.desc = '',
    this.typeName = '',
    this.className = '',
    this.doubanId = 0,
  });

  factory VodItem.fromJson(Map<String, dynamic> j) {
    return VodItem(
      id: '${j['id'] ?? ''}',
      title: j['title'] ?? '',
      poster: j['poster'] ?? '',
      episodes: (j['episodes'] as List?)?.map((e) => '$e').toList() ?? [],
      episodeTitles:
          (j['episodes_titles'] as List?)?.map((e) => '$e').toList() ?? [],
      source: j['source'] ?? '',
      sourceName: j['source_name'] ?? '',
      year: '${j['year'] ?? ''}',
      desc: j['desc'] ?? '',
      typeName: j['type_name'] ?? '',
      className: j['class'] ?? '',
      doubanId: (j['douban_id'] as num?)?.toInt() ?? 0,
    );
  }

  String get key => '$source+$id';
  int get episodeCount => episodes.length;
}

/// 搜索结果按标题聚合（同名不同源合并）
class AggregatedItem {
  final String title;
  final String poster;
  final String year;
  final String typeName;
  final String desc;
  final int doubanId;
  final List<VodItem> sources;

  AggregatedItem({
    required this.title,
    required this.poster,
    required this.year,
    required this.typeName,
    required this.desc,
    required this.doubanId,
    required this.sources,
  });

  static String groupKey(VodItem v) => '${v.title}|${v.year}|${v.typeName}';

  static List<AggregatedItem> aggregate(List<VodItem> items) {
    final map = <String, AggregatedItem>{};
    for (final v in items) {
      final k = groupKey(v);
      final existing = map[k];
      if (existing == null) {
        map[k] = AggregatedItem(
          title: v.title,
          poster: v.poster,
          year: v.year,
          typeName: v.typeName,
          desc: v.desc,
          doubanId: v.doubanId,
          sources: [v],
        );
      } else {
        existing.sources.add(v);
      }
    }
    return map.values.toList();
  }
}

/// 豆瓣条目（/api/douban、/api/douban/categories、/api/douban/recommends）
class DoubanItem {
  final String id;
  final String title;
  final String poster;
  final String rate;
  final String year;

  const DoubanItem({
    required this.id,
    required this.title,
    this.poster = '',
    this.rate = '',
    this.year = '',
  });

  factory DoubanItem.fromJson(Map<String, dynamic> j) {
    return DoubanItem(
      id: '${j['id'] ?? ''}',
      title: j['title'] ?? '',
      poster: j['poster'] ?? '',
      rate: '${j['rate'] ?? ''}',
      year: '${j['year'] ?? ''}',
    );
  }
}

/// 番组（bangumi calendar）
class BangumiItem {
  final int id;
  final String name;
  final String nameCn;
  final String airDate;
  final double score;
  final String image;

  const BangumiItem({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.airDate,
    required this.score,
    required this.image,
  });

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  factory BangumiItem.fromJson(Map<String, dynamic> j) {
    final images = j['images'] as Map<String, dynamic>?;
    return BangumiItem(
      id: (j['id'] as num?)?.toInt() ?? 0,
      name: j['name'] ?? '',
      nameCn: j['name_cn'] ?? '',
      airDate: j['air_date'] ?? '',
      score: (j['rating']?['score'] as num?)?.toDouble() ?? 0,
      image: images?['large'] ?? images?['common'] ?? images?['medium'] ?? '',
    );
  }
}

/// 播放记录（/api/playrecords）
class PlayRecord {
  final String source;
  final String id;
  final String title;
  final String sourceName;
  final String cover;
  final String year;
  final int index; // 第几集（从 1 开始）
  final int totalEpisodes;
  final int playTime; // 秒
  final int totalTime; // 秒
  final int saveTime;
  final String searchTitle;

  const PlayRecord({
    required this.source,
    required this.id,
    required this.title,
    required this.sourceName,
    this.cover = '',
    this.year = '',
    this.index = 1,
    this.totalEpisodes = 0,
    this.playTime = 0,
    this.totalTime = 0,
    this.saveTime = 0,
    this.searchTitle = '',
  });

  String get key => '$source+$id';
  double get progress => totalTime > 0 ? playTime / totalTime : 0;

  factory PlayRecord.fromJson(String key, Map<String, dynamic> j) {
    final parts = key.split('+');
    return PlayRecord(
      source: parts.isNotEmpty ? parts[0] : '',
      id: parts.length > 1 ? parts.sublist(1).join('+') : key,
      title: j['title'] ?? '',
      sourceName: j['source_name'] ?? '',
      cover: j['cover'] ?? '',
      year: '${j['year'] ?? ''}',
      index: (j['index'] as num?)?.toInt() ?? 1,
      totalEpisodes: (j['total_episodes'] as num?)?.toInt() ?? 0,
      playTime: (j['play_time'] as num?)?.toInt() ?? 0,
      totalTime: (j['total_time'] as num?)?.toInt() ?? 0,
      saveTime: (j['save_time'] as num?)?.toInt() ?? 0,
      searchTitle: j['search_title'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'source_name': sourceName,
        'cover': cover,
        'year': year,
        'index': index,
        'total_episodes': totalEpisodes,
        'play_time': playTime,
        'total_time': totalTime,
        'save_time': saveTime,
        'search_title': searchTitle,
      };
}

/// 收藏项（/api/favorites）
class FavoriteItem {
  final String source;
  final String id;
  final String title;
  final String sourceName;
  final String year;
  final String cover;
  final int totalEpisodes;
  final int saveTime;
  final String searchTitle;

  const FavoriteItem({
    required this.source,
    required this.id,
    required this.title,
    required this.sourceName,
    this.year = '',
    this.cover = '',
    this.totalEpisodes = 0,
    this.saveTime = 0,
    this.searchTitle = '',
  });

  String get key => '$source+$id';

  factory FavoriteItem.fromJson(String key, Map<String, dynamic> j) {
    final parts = key.split('+');
    return FavoriteItem(
      source: parts.isNotEmpty ? parts[0] : '',
      id: parts.length > 1 ? parts.sublist(1).join('+') : key,
      title: j['title'] ?? '',
      sourceName: j['source_name'] ?? '',
      year: '${j['year'] ?? ''}',
      cover: j['cover'] ?? '',
      totalEpisodes: (j['total_episodes'] as num?)?.toInt() ?? 0,
      saveTime: (j['save_time'] as num?)?.toInt() ?? 0,
      searchTitle: j['search_title'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'source_name': sourceName,
        'year': year,
        'cover': cover,
        'total_episodes': totalEpisodes,
        'save_time': saveTime,
        'search_title': searchTitle,
      };
}

/// 跳过片头片尾配置（/api/skipconfigs）
/// introTime：片头结束点（正数秒）；outroTime：片尾相对结尾秒数（负数）
class SkipConfig {
  final bool enable;
  final double introTime;
  final double outroTime;

  const SkipConfig({
    this.enable = false,
    this.introTime = 0,
    this.outroTime = 0,
  });

  bool get isEmpty => !enable && introTime == 0 && outroTime == 0;

  factory SkipConfig.fromJson(Map<String, dynamic> j) => SkipConfig(
        enable: j['enable'] == true,
        introTime: (j['intro_time'] as num?)?.toDouble() ?? 0,
        outroTime: (j['outro_time'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'enable': enable,
        'intro_time': introTime,
        'outro_time': outroTime,
      };

  SkipConfig copyWith({bool? enable, double? introTime, double? outroTime}) =>
      SkipConfig(
        enable: enable ?? this.enable,
        introTime: introTime ?? this.introTime,
        outroTime: outroTime ?? this.outroTime,
      );
}

/// 搜索源（/api/search/resources）
class SearchResource {
  final String key;
  final String name;
  final String api;
  final String? detail;

  const SearchResource({
    required this.key,
    required this.name,
    required this.api,
    this.detail,
  });

  factory SearchResource.fromJson(Map<String, dynamic> j) => SearchResource(
        key: j['key'] ?? '',
        name: j['name'] ?? '',
        api: j['api'] ?? '',
        detail: j['detail'],
      );
}

/// 直播源（/api/live/sources）
class LiveSource {
  final String key;
  final String name;
  final String url;
  final String? ua;
  final String? epg;
  final int channelNumber;

  const LiveSource({
    required this.key,
    required this.name,
    required this.url,
    this.ua,
    this.epg,
    this.channelNumber = 0,
  });

  factory LiveSource.fromJson(Map<String, dynamic> j) => LiveSource(
        key: j['key'] ?? '',
        name: j['name'] ?? '',
        url: j['url'] ?? '',
        ua: j['ua'],
        epg: j['epg'],
        channelNumber: (j['channelNumber'] as num?)?.toInt() ?? 0,
      );
}

/// 直播频道（/api/live/channels）
class LiveChannel {
  final String id;
  final String tvgId;
  final String name;
  final String logo;
  final String group;
  final String url;

  const LiveChannel({
    required this.id,
    this.tvgId = '',
    required this.name,
    this.logo = '',
    this.group = '',
    required this.url,
  });

  factory LiveChannel.fromJson(Map<String, dynamic> j) => LiveChannel(
        id: '${j['id'] ?? ''}',
        tvgId: j['tvgId'] ?? '',
        name: j['name'] ?? '',
        logo: j['logo'] ?? '',
        group: j['group'] ?? '',
        url: j['url'] ?? '',
      );
}

/// EPG 节目单（/api/live/epg）
class EpgProgram {
  final String start;
  final String end;
  final String title;

  const EpgProgram({required this.start, required this.end, required this.title});

  factory EpgProgram.fromJson(Map<String, dynamic> j) => EpgProgram(
        start: j['start'] ?? '',
        end: j['end'] ?? '',
        title: j['title'] ?? '',
      );
}

/// 服务端配置（/api/server-config）
class ServerConfig {
  final String siteName;
  final String storageType;
  final String version;

  const ServerConfig({
    required this.siteName,
    required this.storageType,
    required this.version,
  });

  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig(
        siteName: j['SiteName'] ?? 'LunaTV',
        storageType: j['StorageType'] ?? 'localstorage',
        version: j['Version'] ?? '',
      );

  bool get hasUserAccounts => storageType != 'localstorage';
}

/// SSE 搜索流事件（/api/search/ws）
sealed class SearchEvent {
  const SearchEvent();
}

class SearchStartEvent extends SearchEvent {
  final String query;
  final int totalSources;
  const SearchStartEvent({required this.query, required this.totalSources});
}

class SearchSourceResultEvent extends SearchEvent {
  final String source;
  final String sourceName;
  final List<VodItem> results;
  const SearchSourceResultEvent({
    required this.source,
    required this.sourceName,
    required this.results,
  });
}

class SearchSourceErrorEvent extends SearchEvent {
  final String source;
  final String sourceName;
  final String error;
  const SearchSourceErrorEvent({
    required this.source,
    required this.sourceName,
    required this.error,
  });
}

class SearchCompleteEvent extends SearchEvent {
  final int totalResults;
  final int completedSources;
  const SearchCompleteEvent({
    required this.totalResults,
    required this.completedSources,
  });
}
