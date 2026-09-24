import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'session.dart';

/// API 请求结果
class ApiResult<T> {
  final bool ok;
  final T? data;
  final String? error;
  final int status;

  const ApiResult._(this.ok, this.data, this.error, this.status);

  factory ApiResult.success(T data, [int status = 200]) =>
      ApiResult._(true, data, null, status);
  factory ApiResult.fail(String error, [int status = 0]) =>
      ApiResult._(false, null, error, status);
}

/// LunaTV 后端 API 客户端。
/// 认证方式：登录后保存 `auth` Cookie，之后所有请求带 Cookie 头。
class Api {
  static const _timeout = Duration(seconds: 30);

  /// 当前会话 Cookie（内存缓存，启动时由 Session 恢复）
  static String? _cookie;
  static String? _baseUrl;

  /// 初始化：恢复已保存的会话
  static Future<void> restore() async {
    _baseUrl = await Session.serverUrl;
    _cookie = await Session.cookie;
  }

  static bool get isLoggedIn => _cookie != null && _cookie!.isNotEmpty;

  static String? get baseUrl => _baseUrl;

  // ---------- 基础请求 ----------

  static Uri _u(String path, [Map<String, String>? query]) {
    final base = _baseUrl ?? '';
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$p');
    if (query != null && query.isNotEmpty) {
      return uri.replace(queryParameters: query);
    }
    return uri;
  }

  static Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_cookie != null && _cookie!.isNotEmpty) 'Cookie': _cookie!,
      };

  static Future<ApiResult<dynamic>> get(String path,
      {Map<String, String>? query}) async {
    try {
      final r = await http.get(_u(path, query), headers: _headers)
          .timeout(_timeout);
      return _wrap(r);
    } catch (e) {
      return ApiResult.fail('网络异常: $e');
    }
  }

  static Future<ApiResult<dynamic>> post(String path,
      {Object? body, Map<String, String>? query}) async {
    try {
      final r = await http
          .post(_u(path, query), headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);
      return _wrap(r);
    } catch (e) {
      return ApiResult.fail('网络异常: $e');
    }
  }

  static Future<ApiResult<dynamic>> delete(String path,
      {Map<String, String>? query}) async {
    try {
      final r = await http.delete(_u(path, query), headers: _headers)
          .timeout(_timeout);
      return _wrap(r);
    } catch (e) {
      return ApiResult.fail('网络异常: $e');
    }
  }

  static ApiResult<dynamic> _wrap(http.Response r) {
    if (r.statusCode == 401) {
      return ApiResult.fail('登录已过期', 401);
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      String msg = '请求失败 (${r.statusCode})';
      try {
        final j = jsonDecode(r.body);
        msg = j['error'] ?? j['message'] ?? msg;
      } catch (_) {}
      return ApiResult.fail(msg, r.statusCode);
    }
    try {
      return ApiResult.success(jsonDecode(r.body), r.statusCode);
    } catch (_) {
      return ApiResult.success(r.body, r.statusCode);
    }
  }

  // ---------- 认证 ----------

  /// 探测服务器配置（公开接口）：站点名 / 存储类型 / 版本
  static Future<ApiResult<ServerConfig>> probeServer(String serverUrl) async {
    var base = serverUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (!base.startsWith('http')) base = 'https://$base';
    try {
      final r = await http
          .get(Uri.parse('$base/api/server-config'),
              headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        return ApiResult.success(
            ServerConfig.fromJson(jsonDecode(r.body)), 200);
      }
      return ApiResult.fail('服务器响应 ${r.statusCode}', r.statusCode);
    } catch (e) {
      return ApiResult.fail('无法连接服务器: $e');
    }
  }

  /// 登录：localstorage 模式只校验 password；DB 模式校验 username+password
  static Future<ApiResult<void>> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    var base = serverUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (!base.startsWith('http')) base = 'https://$base';
    try {
      final r = await http
          .post(Uri.parse('$base/api/login'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({'username': username, 'password': password}))
          .timeout(_timeout);
      if (r.statusCode == 200) {
        final setCookie = r.headers['set-cookie'] ?? '';
        // 只取第一个键值对（auth=...）
        final cookie = setCookie.split(';').first.trim();
        if (cookie.isEmpty || !cookie.contains('=')) {
          return ApiResult.fail('服务器未返回认证信息', 500);
        }
        _baseUrl = base;
        _cookie = cookie;
        await Session.save(
          serverUrl: base,
          username: username,
          password: password,
          cookie: cookie,
        );
        return ApiResult.success(null, 200);
      }
      String msg = '登录失败 (${r.statusCode})';
      try {
        msg = jsonDecode(r.body)['error'] ?? msg;
      } catch (_) {}
      return ApiResult.fail(msg, r.statusCode);
    } catch (e) {
      return ApiResult.fail('网络异常: $e');
    }
  }

  /// 自动登录（启动时重新换取 Cookie）
  static Future<bool> autoLogin() async {
    final url = await Session.serverUrl;
    final user = await Session.username;
    final pass = await Session.password;
    if (url == null || pass == null || pass.isEmpty) return false;
    final r = await login(
        serverUrl: url, username: user ?? '', password: pass);
    return r.ok;
  }

  /// 修改密码（DB 存储模式）
  static Future<ApiResult<void>> changePassword(
      String oldPassword, String newPassword) async {
    final r = await post('/api/change-password',
        body: {'oldPassword': oldPassword, 'newPassword': newPassword});
    if (r.ok) {
      await Session.updatePassword(newPassword);
      return ApiResult.success(null);
    }
    return ApiResult.fail(r.error ?? '修改失败', r.status);
  }

  // ---------- 搜索 ----------

  /// 一次性聚合搜索
  static Future<List<VodItem>> search(String query) async {
    final r = await get('/api/search', query: {'q': query.trim()});
    if (!r.ok) return [];
    final list = (r.data?['results'] as List?) ?? [];
    return list
        .map((e) => VodItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 流式搜索（SSE）：/api/search/ws
  static Stream<SearchEvent> searchStream(String query) async* {
    final base = _baseUrl;
    if (base == null) return;
    final uri = Uri.parse('$base/api/search/ws?q=${Uri.encodeComponent(query)}');
    final req = http.Request('GET', uri)
      ..headers.addAll({
        'Accept': 'text/event-stream',
        if (_cookie != null) 'Cookie': _cookie!,
      });
    http.Client? client;
    try {
      client = http.Client();
      final resp = await client.send(req).timeout(_timeout);
      final stream = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final buffer = StringBuffer();
      await for (final line in stream) {
        if (line.startsWith('data:')) {
          buffer.write(line.substring(5).trim());
        } else if (line.isEmpty && buffer.isNotEmpty) {
          final event = _parseSseEvent(buffer.toString());
          buffer.clear();
          if (event != null) yield event;
        }
      }
      if (buffer.isNotEmpty) {
        final event = _parseSseEvent(buffer.toString());
        if (event != null) yield event;
      }
    } catch (_) {
      // 网络中断时结束流
    } finally {
      client?.close();
    }
  }

  static SearchEvent? _parseSseEvent(String data) {
    try {
      final j = jsonDecode(data) as Map<String, dynamic>;
      switch (j['type']) {
        case 'start':
          return SearchStartEvent(
            query: j['query'] ?? '',
            totalSources: (j['totalSources'] as num?)?.toInt() ?? 0,
          );
        case 'source_result':
          final list = (j['results'] as List?) ?? [];
          return SearchSourceResultEvent(
            source: j['source'] ?? '',
            sourceName: j['sourceName'] ?? '',
            results: list
                .map((e) => VodItem.fromJson(e as Map<String, dynamic>))
                .toList(),
          );
        case 'source_error':
          return SearchSourceErrorEvent(
            source: j['source'] ?? '',
            sourceName: j['sourceName'] ?? '',
            error: j['error'] ?? '',
          );
        case 'complete':
          return SearchCompleteEvent(
            totalResults: (j['totalResults'] as num?)?.toInt() ?? 0,
            completedSources: (j['completedSources'] as num?)?.toInt() ?? 0,
          );
      }
    } catch (_) {}
    return null;
  }

  /// 搜索建议
  static Future<List<String>> searchSuggestions(String query) async {
    final r =
        await get('/api/search/suggestions', query: {'q': query.trim()});
    if (!r.ok) return [];
    final list = (r.data?['suggestions'] as List?) ?? [];
    return list.map((e) => '${e['text'] ?? ''}').toList();
  }

  /// 搜索源列表
  static Future<List<SearchResource>> searchResources() async {
    final r = await get('/api/search/resources');
    if (!r.ok || r.data is! List) return [];
    return (r.data as List)
        .map((e) => SearchResource.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 单源精确搜索（按标题匹配）
  static Future<List<VodItem>> searchOne(String query, String resourceId) async {
    final r = await get('/api/search/one',
        query: {'q': query, 'resourceId': resourceId});
    if (!r.ok) return [];
    final list = (r.data?['results'] as List?) ?? [];
    return list
        .map((e) => VodItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 详情
  static Future<VodItem?> detail(String source, String id) async {
    final r = await get('/api/detail', query: {'source': source, 'id': id});
    if (!r.ok || r.data is! Map) return null;
    return VodItem.fromJson(r.data as Map<String, dynamic>);
  }

  // ---------- 豆瓣 ----------

  /// 豆瓣榜单：type = tv|movie；tag 如 热门/top250
  static Future<List<DoubanItem>> douban({
    required String type,
    required String tag,
    int pageStart = 0,
    int pageSize = 16,
  }) async {
    final r = await get('/api/douban', query: {
      'type': type,
      'tag': tag,
      'pageStart': '$pageStart',
      'pageSize': '$pageSize',
    });
    if (!r.ok) return [];
    final list = (r.data?['list'] as List?) ?? [];
    return list
        .map((e) => DoubanItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 豆瓣分类
  static Future<List<DoubanItem>> doubanCategories({
    String kind = 'movie',
    String category = '',
    String type = '',
    int start = 0,
    int limit = 20,
  }) async {
    final r = await get('/api/douban/categories', query: {
      'kind': kind,
      'category': category,
      'type': type,
      'start': '$start',
      'limit': '$limit',
    });
    if (!r.ok) return [];
    final list = (r.data?['list'] as List?) ?? [];
    return list
        .map((e) => DoubanItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 豆瓣推荐（带筛选）
  static Future<List<DoubanItem>> doubanRecommends({
    required String kind,
    int start = 0,
    int limit = 20,
    String? category,
    String? format,
    String? region,
    String? year,
    String? platform,
    String? sort,
    String? label,
  }) async {
    final q = <String, String>{
      'kind': kind,
      'start': '$start',
      'limit': '$limit',
    };
    if (category != null) q['category'] = category;
    if (format != null) q['format'] = format;
    if (region != null) q['region'] = region;
    if (year != null) q['year'] = year;
    if (platform != null) q['platform'] = platform;
    if (sort != null) q['sort'] = sort;
    if (label != null) q['label'] = label;
    final r = await get('/api/douban/recommends', query: q);
    if (!r.ok) return [];
    final list = (r.data?['list'] as List?) ?? [];
    return list
        .map((e) => DoubanItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 番组放送表（按星期几分组）
  static Future<Map<int, List<BangumiItem>>> bangumiCalendar() async {
    final r = await get('/api/bangumi/calendar');
    if (!r.ok || r.data is! List) return {};
    final map = <int, List<BangumiItem>>{};
    for (final day in r.data as List) {
      final weekday = (day['weekday']?['id'] as num?)?.toInt() ?? 0;
      final items = (day['items'] as List?) ?? [];
      map[weekday] = items
          .map((e) => BangumiItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return map;
  }

  // ---------- 用户数据 ----------

  /// 播放记录
  static Future<List<PlayRecord>> playRecords() async {
    final r = await get('/api/playrecords');
    if (!r.ok || r.data is! Map) return [];
    final out = <PlayRecord>[];
    (r.data as Map).forEach((k, v) {
      try {
        out.add(PlayRecord.fromJson(k, v as Map<String, dynamic>));
      } catch (_) {}
    });
    out.sort((a, b) => b.saveTime.compareTo(a.saveTime));
    return out;
  }

  static Future<ApiResult<void>> savePlayRecord(PlayRecord record) async {
    return _voidResult(await post('/api/playrecords',
        body: {'key': record.key, 'record': record.toJson()}));
  }

  static Future<ApiResult<void>> deletePlayRecord(String key) async {
    return _voidResult(await delete('/api/playrecords',
        query: {'key': key}));
  }

  static Future<ApiResult<void>> clearPlayRecords() async {
    return _voidResult(await delete('/api/playrecords'));
  }

  /// 收藏
  static Future<List<FavoriteItem>> favorites() async {
    final r = await get('/api/favorites');
    if (!r.ok || r.data is! Map) return [];
    final out = <FavoriteItem>[];
    (r.data as Map).forEach((k, v) {
      try {
        out.add(FavoriteItem.fromJson(k, v as Map<String, dynamic>));
      } catch (_) {}
    });
    out.sort((a, b) => b.saveTime.compareTo(a.saveTime));
    return out;
  }

  static Future<ApiResult<void>> addFavorite(
      String key, FavoriteItem fav) async {
    return _voidResult(await post('/api/favorites',
        body: {'key': key, 'favorite': fav.toJson()}));
  }

  static Future<ApiResult<void>> removeFavorite(String key) async {
    return _voidResult(await delete('/api/favorites', query: {'key': key}));
  }

  /// 搜索历史
  static Future<List<String>> searchHistory() async {
    final r = await get('/api/searchhistory');
    if (!r.ok || r.data is! List) return [];
    return (r.data as List).map((e) => '$e').toList();
  }

  static Future<ApiResult<void>> addSearchHistory(String keyword) async {
    return _voidResult(
        await post('/api/searchhistory', body: {'keyword': keyword}));
  }

  static Future<ApiResult<void>> deleteSearchHistory(String keyword) async {
    return _voidResult(await delete('/api/searchhistory',
        query: {'keyword': keyword}));
  }

  static Future<ApiResult<void>> clearSearchHistory() async {
    return _voidResult(await delete('/api/searchhistory'));
  }

  /// 跳过片头片尾
  static Future<SkipConfig?> skipConfig(String source, String id) async {
    final r =
        await get('/api/skipconfigs', query: {'source': source, 'id': id});
    if (!r.ok || r.data == null || r.data is! Map) return null;
    return SkipConfig.fromJson(r.data as Map<String, dynamic>);
  }

  static Future<ApiResult<void>> saveSkipConfig(
      String source, String id, SkipConfig config) async {
    return _voidResult(await post('/api/skipconfigs',
        body: {'key': '$source+$id', 'config': config.toJson()}));
  }

  static Future<ApiResult<void>> deleteSkipConfig(String key) async {
    return _voidResult(
        await delete('/api/skipconfigs', query: {'key': key}));
  }

  // ---------- 直播 ----------

  static Future<List<LiveSource>> liveSources() async {
    final r = await get('/api/live/sources');
    if (!r.ok) return [];
    final list = (r.data?['data'] as List?) ?? [];
    return list
        .map((e) => LiveSource.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<LiveChannel>> liveChannels(String sourceKey) async {
    final r =
        await get('/api/live/channels', query: {'source': sourceKey});
    if (!r.ok) return [];
    final list = (r.data?['data'] as List?) ?? [];
    return list
        .map((e) => LiveChannel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<EpgProgram>> liveEpg(String tvgId, String sourceKey) async {
    final r = await get('/api/live/epg',
        query: {'tvgId': tvgId, 'source': sourceKey});
    if (!r.ok) return [];
    final list = (r.data?['data']?['programs'] as List?) ?? [];
    return list
        .map((e) => EpgProgram.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 直播 m3u8 代理地址（服务器代理，走 moontv-source 鉴权）
  static String liveProxyUrl(String channelUrl, String sourceKey,
      {bool allowCORS = false}) {
    final base = _baseUrl ?? '';
    return '$base/api/proxy/m3u8?url=${Uri.encodeComponent(channelUrl)}'
        '&moontv-source=${Uri.encodeComponent(sourceKey)}'
        '&allowCORS=$allowCORS';
  }

  /// 图片代理（豆瓣海报防盗链）
  static String imageProxy(String url) {
    final base = _baseUrl ?? '';
    return '$base/api/image-proxy?url=${Uri.encodeComponent(url)}';
  }

  static ApiResult<void> _voidResult(ApiResult<dynamic> r) =>
      r.ok ? ApiResult.success(null, r.status)
          : ApiResult.fail(r.error ?? '操作失败', r.status);
}
