import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'api.dart';
import 'models.dart';
import 'widgets.dart';

/// 直播页：源标签 → 分组频道网格 → 直播播放器
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen>
    with AutomaticKeepAliveClientMixin {
  List<LiveSource> _sources = [];
  int _sourceIndex = 0;
  List<LiveChannel> _channels = [];
  Map<String, List<LiveChannel>> _groups = {};
  List<String> _groupNames = [];
  int _groupIndex = 0;
  bool _loadingSources = true;
  bool _loadingChannels = false;
  String? _error;
  int _loadGen = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() => _loadingSources = true);
    final sources = await Api.liveSources();
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _loadingSources = false;
    });
    if (sources.isNotEmpty) _loadChannels(0);
  }

  Future<void> _loadChannels(int index) async {
    final gen = ++_loadGen;
    setState(() {
      _sourceIndex = index;
      _loadingChannels = true;
      _error = null;
    });
    final channels = await Api.liveChannels(_sources[index].key);
    if (!mounted || gen != _loadGen) return;
    final groups = <String, List<LiveChannel>>{};
    for (final c in channels) {
      groups.putIfAbsent(c.group.isEmpty ? '默认' : c.group, () => []).add(c);
    }
    setState(() {
      _channels = channels;
      _groups = groups;
      _groupNames = groups.keys.toList();
      _groupIndex = 0;
      _loadingChannels = false;
      if (channels.isEmpty) _error = '该源暂无频道';
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('直播', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed:
                _sources.isEmpty ? null : () => _loadChannels(_sourceIndex),
          ),
        ],
      ),
      body: _loadingSources
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty
              ? const Center(child: Text('服务器未配置直播源'))
              : Column(
                  children: [
                    _buildSourceTabs(),
                    if (_groupNames.length > 1) _buildGroupTabs(),
                    const Divider(height: 1),
                    Expanded(child: _buildChannelGrid()),
                  ],
                ),
    );
  }

  Widget _buildSourceTabs() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _sources.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = i == _sourceIndex;
          return GestureDetector(
            onTap: () => _loadChannels(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel
                    ? kAccent
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _sources[i].name,
                style: TextStyle(
                    fontSize: 13, color: sel ? Colors.white : null),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGroupTabs() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        itemCount: _groupNames.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = i == _groupIndex;
          return GestureDetector(
            onTap: () => setState(() => _groupIndex = i),
            child: Text(
              _groupNames[i],
              style: TextStyle(
                fontSize: 13,
                color: sel ? kAccent : Colors.grey[500],
                fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChannelGrid() {
    if (_loadingChannels) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return Center(child: Text(_error!));
    final list = _groupNames.isEmpty
        ? _channels
        : _groups[_groupNames[_groupIndex]] ?? [];
    if (list.isEmpty) return const Center(child: Text('该分组暂无频道'));

    final w = MediaQuery.of(context).size.width;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: (w ~/ 110).clamp(3, 8),
        childAspectRatio: 1.5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final c = list[i];
        return GestureDetector(
          onTap: () => _play(c, list),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (c.logo.isNotEmpty)
                  Expanded(
                    child: Poster(c.logo, fit: BoxFit.contain, useProxy: false),
                  )
                else
                  const Expanded(
                      child: Icon(Icons.live_tv, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _play(LiveChannel channel, List<LiveChannel> channels) {
    final src = _sources[_sourceIndex];
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LivePlayerScreen(
        source: src,
        channel: channel,
        channels: channels,
      ),
    ));
  }
}

/// 直播播放器
class LivePlayerScreen extends StatefulWidget {
  final LiveSource source;
  final LiveChannel channel;
  final List<LiveChannel> channels;

  const LivePlayerScreen({
    super.key,
    required this.source,
    required this.channel,
    required this.channels,
  });

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<LivePlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  late LiveChannel _channel;
  List<EpgProgram> _epg = [];
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isFullscreen = false;
  StreamSubscription<bool>? _playingSub;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _channel = widget.channel;
    _open();
    _loadEpg();
    _startHideTimer();
  }

  void _open() {
    // 直播走服务器 m3u8 代理（自动处理 UA / 跨域 / 地址重写）
    final url = Api.liveProxyUrl(_channel.url, widget.source.key,
        allowCORS: true);
    _player.open(Media(url), play: true);
    _playingSub ??= _player.stream.playing.listen((p) {
      _playing = p;
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadEpg() async {
    if (_channel.tvgId.isEmpty) return;
    final epg = await Api.liveEpg(_channel.tvgId, widget.source.key);
    if (mounted) setState(() => _epg = epg);
  }

  void _switch(LiveChannel c) {
    setState(() => _channel = c);
    _open();
    _loadEpg();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _controlsVisible = false);
    });
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

  void _showChannels() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.channels.length,
          itemBuilder: (_, i) {
            final c = widget.channels[i];
            final sel = c.id == _channel.id;
            return ListTile(
              selected: sel,
              dense: true,
              title: Text(c.name),
              subtitle: c.group.isNotEmpty ? Text(c.group) : null,
              trailing:
                  sel ? const Icon(Icons.check, color: kAccent) : null,
              onTap: () {
                Navigator.pop(ctx);
                if (!sel) _switch(c);
              },
            );
          },
        ),
      ),
    );
  }

  void _showEpg() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: _epg.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('暂无节目单')),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _epg.length,
                itemBuilder: (_, i) {
                  final p = _epg[i];
                  return ListTile(
                    dense: true,
                    title: Text(p.title),
                    subtitle: Text('${p.start} - ${p.end}'),
                  );
                },
              ),
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingSub?.cancel();
    _player.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            setState(() => _controlsVisible = !_controlsVisible);
            if (_controlsVisible) _startHideTimer();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _controller, controls: NoVideoControls),
              if (_controlsVisible) ...[
                Positioned(
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
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Text(
                            '${_channel.name} · ${widget.source.name}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
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
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                              _playing ? Icons.pause : Icons.play_arrow,
                              color: Colors.white),
                          onPressed: () {
                            _player.playOrPause();
                            _startHideTimer();
                          },
                        ),
                        TextButton(
                          onPressed: _showChannels,
                          child: const Text('频道',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        ),
                        TextButton(
                          onPressed: _showEpg,
                          child: const Text('节目单',
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
                          onPressed: _toggleFullscreen,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
