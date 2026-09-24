import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'api.dart';
import 'models.dart';
import 'widgets.dart';

/// 点播播放页：media_kit 播放器 + 选集/换源/倍速/跳过片头片尾/进度同步/收藏。
class PlayerScreen extends StatefulWidget {
  final String? source;
  final String? id;
  final String title;
  final String? year;
  final String? searchTitle;
  final int episodeIndex;
  final int startAtSeconds;

  const PlayerScreen({
    super.key,
    this.source,
    this.id,
    required this.title,
    this.year,
    this.searchTitle,
    this.episodeIndex = 0,
    this.startAtSeconds = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // 播放器
  late final Player _player;
  late final VideoController _videoController;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _completedSub;

  // 数据
  VodItem? _detail;
  List<VodItem> _allSources = [];
  String _source = '';
  String _id = '';
  int _episode = 0;
  int _resumeSeconds = 0;
  bool _loading = true;
  String? _error;

  // 控制栏
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isFullscreen = false;
  bool _seeking = false;
  Duration? _dragPos;

  // 状态快照（流监听）
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _speed = 1.0;

  // 收藏 / 跳过配置
  bool _favorite = false;
  SkipConfig _skipConfig = const SkipConfig();
  int _lastSkipCheckMs = 0;

  // 进度保存
  Timer? _saveTimer;
  int _lastSavedSeconds = -1;

  bool get _isLast => _detail == null || _episode >= _detail!.episodes.length - 1;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _source = widget.source ?? '';
    _id = widget.id ?? '';
    _episode = widget.episodeIndex;
    _resumeSeconds = widget.startAtSeconds;
    _init();
    _startHideTimer();
  }

  Future<void> _init() async {
    VodItem? detail;
    if (_source.isNotEmpty && _id.isNotEmpty) {
      detail = await Api.detail(_source, _id);
    }
    // 详情拿不到时，用搜索兜底
    if (detail == null) {
      final results = await Api.search(
          (widget.searchTitle?.isNotEmpty ?? false)
              ? widget.searchTitle!
              : widget.title);
      _allSources = results;
      detail = results.cast<VodItem?>().firstWhere(
            (v) => v!.source == _source && v.id == _id,
            orElse: () => results.isNotEmpty ? results.first : null,
          );
      if (detail != null) {
        _source = detail.source;
        _id = detail.id;
      }
    } else {
      // 异步拉取同源其它资源用于换源
      _loadAllSources();
    }
    if (!mounted) return;
    if (detail == null || detail.episodes.isEmpty) {
      setState(() {
        _loading = false;
        _error = '未找到可播放资源';
      });
      return;
    }
    _detail = detail;

    // 读取历史进度（未显式指定时）
    if (widget.episodeIndex == 0 && widget.startAtSeconds == 0) {
      final records = await Api.playRecords();
      if (!mounted) return;
      final rec = records.cast<PlayRecord?>().firstWhere(
          (r) => r!.source == _source && r.id == _id,
          orElse: () => null);
      if (rec != null) {
        _episode = (rec.index - 1).clamp(0, detail.episodes.length - 1);
        _resumeSeconds = rec.playTime;
      }
    }

    await _loadSkipConfig();
    _checkFavorite();
    _playEpisode(_episode, _resumeSeconds);
    _saveTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _saveProgress());
  }

  Future<void> _loadAllSources() async {
    final q = (widget.searchTitle?.isNotEmpty ?? false)
        ? widget.searchTitle!
        : widget.title;
    final results = await Api.search(q);
    if (!mounted) return;
    setState(() => _allSources = results);
  }

  Future<void> _loadSkipConfig() async {
    if (_source.isEmpty || _id.isEmpty) return;
    final c = await Api.skipConfig(_source, _id);
    if (mounted && c != null) setState(() => _skipConfig = c);
  }

  Future<void> _checkFavorite() async {
    final favs = await Api.favorites();
    if (!mounted) return;
    setState(() =>
        _favorite = favs.any((f) => f.source == _source && f.id == _id));
  }

  void _playEpisode(int index, int resumeSeconds) {
    final d = _detail;
    if (d == null || index < 0 || index >= d.episodes.length) return;
    _saveProgress(force: true); // 切集前保存上一集进度
    setState(() {
      _episode = index;
      _resumeSeconds = resumeSeconds;
      _error = null;
    });
    _lastSavedSeconds = -1;
    _open(d.episodes[index], Duration(seconds: resumeSeconds));
  }

  Future<void> _open(String url, Duration startAt) async {
    await _posSub?.cancel();
    await _completedSub?.cancel();
    await _player.open(Media(url), play: true);
    if (startAt > Duration.zero) {
      // 等待时长可用后 seek（比固定延时可靠）
      unawaited(_waitAndSeek(startAt));
    }
    _posSub = _player.stream.position.listen((p) {
      _position = p;
      if (mounted) setState(() {});
      _checkSkip();
    });
    _completedSub = _player.stream.completed.listen((done) {
      if (done) _onCompleted();
    });
    _player.stream.playing.listen((p) {
      _playing = p;
      if (mounted) setState(() {});
    });
    _player.stream.duration.listen((d) {
      _duration = d;
      if (mounted) setState(() {});
    });
    _player.stream.buffering.listen((b) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _waitAndSeek(Duration target) async {
    // 等 duration > 0 再 seek，最多等 15s
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final d = _player.state.duration;
      if (d > Duration.zero) {
        var t = target;
        if (t >= d - const Duration(seconds: 2)) {
          t = d - const Duration(seconds: 5);
        }
        if (t > Duration.zero) await _player.seek(t);
        return;
      }
    }
  }

  /// 跳过片头片尾（1.5s 节流，与 LunaTV 网页端逻辑一致）
  void _checkSkip() {
    if (!_skipConfig.enable) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSkipCheckMs < 1500) return;
    _lastSkipCheckMs = now;

    final pos = _position.inMilliseconds / 1000.0;
    final dur = _duration.inMilliseconds / 1000.0;
    if (dur <= 0) return;

    if (_skipConfig.introTime > 0 && pos < _skipConfig.introTime) {
      _player.seek(Duration(milliseconds: (_skipConfig.introTime * 1000).round()));
      toast(context, '已跳过片头 (${_fmt(_skipConfig.introTime)})');
      return;
    }
    if (_skipConfig.outroTime < 0 && pos > dur + _skipConfig.outroTime) {
      if (!_isLast) {
        toast(context, '已跳过片尾 (${_fmt(-_skipConfig.outroTime)})');
        _playEpisode(_episode + 1, 0);
      } else {
        _player.pause();
      }
    }
  }

  void _onCompleted() {
    if (!_isLast) {
      _playEpisode(_episode + 1, 0);
    } else {
      toast(context, '播放完成');
    }
  }

  Future<void> _saveProgress({bool force = false}) async {
    final d = _detail;
    if (d == null || _source.isEmpty) return;
    final pos = _position.inSeconds;
    final dur = _duration.inSeconds;
    if (pos < 1 || dur <= 0) return;
    if (!force && pos == _lastSavedSeconds) return;
    _lastSavedSeconds = pos;
    await Api.savePlayRecord(PlayRecord(
      source: _source,
      id: _id,
      title: d.title,
      sourceName: d.sourceName,
      cover: d.poster,
      year: d.year,
      index: _episode + 1,
      totalEpisodes: d.episodes.length,
      playTime: pos,
      totalTime: dur,
      saveTime: DateTime.now().millisecondsSinceEpoch,
      searchTitle: widget.searchTitle ?? '',
    ));
  }

  Future<void> _toggleFavorite() async {
    final d = _detail;
    if (d == null) return;
    final key = '$_source+$_id';
    if (_favorite) {
      final r = await Api.removeFavorite(key);
      if (r.ok && mounted) {
        setState(() => _favorite = false);
        toast(context, '已取消收藏');
      }
    } else {
      final r = await Api.addFavorite(
        key,
        FavoriteItem(
          source: _source,
          id: _id,
          title: d.title,
          sourceName: d.sourceName,
          year: d.year,
          cover: d.poster,
          totalEpisodes: d.episodes.length,
          saveTime: DateTime.now().millisecondsSinceEpoch,
          searchTitle: widget.searchTitle ?? '',
        ),
      );
      if (r.ok && mounted) {
        setState(() => _favorite = true);
        toast(context, '已收藏');
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing && !_seeking) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _onUserInteract() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _startHideTimer();
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    setState(() => _isFullscreen = !_isFullscreen);
  }

  void _showSkipSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('跳过片头片尾'),
                value: _skipConfig.enable,
                onChanged: (v) {
                  _updateSkip(_skipConfig.copyWith(enable: v));
                  setSheet(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.vertical_align_top),
                title: const Text('设置片头（当前进度为片头结束点）'),
                trailing: Text(_skipConfig.introTime > 0
                    ? _fmt(_skipConfig.introTime)
                    : '未设置'),
                onTap: () {
                  final p = _position.inMilliseconds / 1000.0;
                  if (p > 0) {
                    _updateSkip(_skipConfig.copyWith(introTime: p));
                    setSheet(() {});
                    toast(context, '片头 ${_fmt(p)}');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.vertical_align_bottom),
                title: const Text('设置片尾（当前进度为片尾开始点）'),
                trailing: Text(_skipConfig.outroTime < 0
                    ? '-${_fmt(_skipConfig.outroTime)}'
                    : '未设置'),
                onTap: () {
                  final dur = _duration.inMilliseconds;
                  final pos = _position.inMilliseconds;
                  final outro = -(dur - pos) / 1000.0;
                  if (outro < 0) {
                    _updateSkip(_skipConfig.copyWith(outroTime: outro));
                    setSheet(() {});
                    toast(context, '片尾 -${_fmt(outro)}');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Colors.redAccent),
                title: const Text('删除跳过配置',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  _updateSkip(const SkipConfig());
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateSkip(SkipConfig c) async {
    setState(() => _skipConfig = c);
    if (_source.isEmpty || _id.isEmpty) return;
    if (c.isEmpty) {
      await Api.deleteSkipConfig('$_source+$_id');
    } else {
      await Api.saveSkipConfig(_source, _id, c);
    }
  }

  void _showEpisodes() {
    final d = _detail;
    if (d == null) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('选集 · 共${d.episodes.length}集',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 2.6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: d.episodes.length,
                itemBuilder: (_, i) {
                  final sel = i == _episode;
                  final label = i < d.episodeTitles.length &&
                          d.episodeTitles[i].isNotEmpty
                      ? d.episodeTitles[i]
                      : '第${i + 1}集';
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _playEpisode(i, 0);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel
                            ? kAccent
                            : Theme.of(ctx)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: sel ? Colors.white : null)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSources() {
    if (_allSources.isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('切换播放源',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _allSources.length,
                itemBuilder: (_, i) {
                  final s = _allSources[i];
                  final sel = s.source == _source && s.id == _id;
                  return ListTile(
                    selected: sel,
                    title: Text(s.sourceName),
                    subtitle: Text('${s.episodeCount}集'),
                    trailing:
                        sel ? const Icon(Icons.check, color: kAccent) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (!sel) _switchSource(s);
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

  Future<void> _switchSource(VodItem v) async {
    _saveProgress(force: true);
    final keepEpisode = _episode;
    final keepPos = _position.inSeconds;
    final detail = await Api.detail(v.source, v.id);
    if (!mounted) return;
    if (detail == null || detail.episodes.isEmpty) {
      toast(context, '该源不可用', error: true);
      return;
    }
    setState(() {
      _detail = detail;
      _source = detail.source;
      _id = detail.id;
    });
    await _loadSkipConfig();
    _checkFavorite();
    _playEpisode(
      keepEpisode.clamp(0, detail.episodes.length - 1),
      keepPos,
    );
  }

  void _showSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            for (final s in speeds)
              ListTile(
                title: Text('${s}x'),
                trailing: (_speed - s).abs() < 0.01
                    ? const Icon(Icons.check, color: kAccent)
                    : null,
                onTap: () {
                  _player.setRate(s);
                  setState(() => _speed = s);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(num seconds) {
    final t = seconds.abs().round();
    final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  void dispose() {
    _saveProgress(force: true);
    _saveTimer?.cancel();
    _hideTimer?.cancel();
    _posSub?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveProgress(force: true);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: kAccent))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              style:
                                  const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('返回'),
                          ),
                        ],
                      ),
                    )
                  : _buildPlayer(),
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    return GestureDetector(
      onTap: () {
        setState(() => _controlsVisible = !_controlsVisible);
        if (_controlsVisible) _startHideTimer();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(controller: _videoController, controls: NoVideoControls),
          if (_controlsVisible) ...[
            _buildTopBar(),
            _buildCenterPlay(),
            _buildBottomBar(),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Text(
                '${_detail?.title ?? widget.title} · ${_episode + 1}/${_detail?.episodes.length ?? 0}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: '跳过片头片尾',
              icon: const Icon(Icons.fast_forward, color: Colors.white),
              onPressed: _showSkipSheet,
            ),
            IconButton(
              tooltip: '收藏',
              icon: Icon(
                  _favorite ? Icons.favorite : Icons.favorite_border,
                  color: _favorite ? Colors.redAccent : Colors.white),
              onPressed: _toggleFavorite,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPlay() {
    return Center(
      child: IgnorePointer(
        ignoring: _playing,
        child: AnimatedOpacity(
          opacity: _playing ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: IconButton(
            iconSize: 64,
            icon: Icon(
                _playing ? Icons.pause_circle : Icons.play_circle,
                color: Colors.white70),
            onPressed: _player.playOrPause,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final shownPos = _dragPos ?? _position;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(_fmt(shownPos.inSeconds),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: shownPos.inMilliseconds
                        .clamp(0, _duration.inMilliseconds)
                        .toDouble(),
                    max: _duration.inMilliseconds.toDouble() + 1,
                    activeColor: kAccent,
                    onChangeStart: (_) {
                      _seeking = true;
                      _hideTimer?.cancel();
                    },
                    onChanged: (v) {
                      setState(() =>
                          _dragPos = Duration(milliseconds: v.round()));
                    },
                    onChangeEnd: (v) {
                      _player.seek(Duration(milliseconds: v.round()));
                      _dragPos = null;
                      _seeking = false;
                      _startHideTimer();
                    },
                  ),
                ),
                Text(_fmt(_duration.inSeconds),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12)),
              ],
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white),
                  onPressed: () {
                    _player.playOrPause();
                    _onUserInteract();
                  },
                ),
                if (!_isLast)
                  IconButton(
                    tooltip: '下一集',
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: () => _playEpisode(_episode + 1, 0),
                  ),
                TextButton(
                  onPressed: () {
                    _onUserInteract();
                    _showSpeedSheet();
                  },
                  child: Text('${_speed}x',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                ),
                TextButton(
                  onPressed: () {
                    _onUserInteract();
                    _showEpisodes();
                  },
                  child: const Text('选集',
                      style:
                          TextStyle(color: Colors.white, fontSize: 13)),
                ),
                if (_allSources.length > 1)
                  TextButton(
                    onPressed: () {
                      _onUserInteract();
                      _showSources();
                    },
                    child: const Text('换源',
                        style: TextStyle(
                            color: Colors.white, fontSize: 13)),
                  ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                      _isFullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: Colors.white),
                  onPressed: () {
                    _onUserInteract();
                    _toggleFullscreen();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
