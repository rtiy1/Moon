import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api.dart';

/// 通用组件库。

const kAccent = Color(0xFF10B981);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kAccent,
      brightness: brightness,
      surface: dark ? const Color(0xFF121212) : Colors.white,
    ),
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0F0F0F) : const Color(0xFFF8F9FA),
    appBarTheme: AppBarTheme(
      backgroundColor:
          dark ? const Color(0xFF0F0F0F) : const Color(0xFFF8F9FA),
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardColor: dark ? const Color(0xFF1C1C1E) : Colors.white,
  );
}

/// 海报图（豆瓣防盗链：可选走服务器 image-proxy）
class Poster extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool useProxy;

  const Poster(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.useProxy = true,
  });

  @override
  Widget build(BuildContext context) {
    final src = (useProxy && url.contains('doubanio.com'))
        ? Api.imageProxy(url)
        : url;
    if (src.isEmpty) return _placeholder();
    return CachedNetworkImage(
      imageUrl: src,
      width: width,
      height: height,
      fit: fit,
      httpHeaders: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://movie.douban.com/',
      },
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: Colors.grey.withValues(alpha: 0.15),
        child: const Icon(Icons.movie_outlined, color: Colors.grey),
      );
}

/// 竖版视频卡片（2:3 海报 + 标题 + 副标题）
class VideoCard extends StatelessWidget {
  final String title;
  final String poster;
  final String? subtitle; // 评分/年份/集数等
  final String? badge; // 右上角角标
  final double? progress; // 底部进度条 0..1
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const VideoCard({
    super.key,
    required this.title,
    this.poster = '',
    this.subtitle,
    this.badge,
    this.progress,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Poster(poster),
                  if (badge != null && badge!.isNotEmpty)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: kAccent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: Colors.black38,
                        valueColor:
                            const AlwaysStoppedAnimation(kAccent),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
        ],
      ),
    );
  }
}

/// 横排滚动卡片列表（首页各板块）
class SectionRow extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final VoidCallback? onMore;

  const SectionRow({
    super.key,
    required this.title,
    required this.children,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: kAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (onMore != null)
                GestureDetector(
                  onTap: onMore,
                  child: Text('更多',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(width: 112, child: children[i]),
          ),
        ),
      ],
    );
  }
}

/// 胶囊筛选按钮组
class ChipRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  const ChipRow({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: options.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final o = options[i];
                final sel = o == selected;
                return GestureDetector(
                  onTap: () => onSelect(o),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel
                          ? kAccent
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      o,
                      style: TextStyle(
                        fontSize: 12,
                        color: sel ? Colors.white : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用网格（海报卡片）
class PosterGrid extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;

  const PosterGrid({super.key, required this.children, this.padding = const EdgeInsets.all(12)});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = w ~/ 120;
    return GridView.count(
      padding: padding,
      crossAxisCount: cols.clamp(3, 6),
      childAspectRatio: 0.58,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: children,
    );
  }
}

/// 通用 Toast
void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : null,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}
