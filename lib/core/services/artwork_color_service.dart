import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 封面主色提取服务（对标 TuneFreeNext 的 DynamicArtworkController /
/// `_extractPalette`）。下载封面后做有界采样，提取一个柔和的主色，
/// 供播放页背景做切歌渐变过渡。
///
/// 采用可注入 loader 设计：默认走网络下载 + dart:ui 解码，测试可注入假
/// loader 而不依赖真实网络/平台通道。提取结果按 URL 做 LRU 内存缓存，
/// 同一首歌反复切歌不会重复下载。
class ArtworkColorService {
  ArtworkColorService({Future<Uint8List> Function(Uri uri)? loader})
      : _loader = loader ?? _defaultLoader;

  final Future<Uint8List> Function(Uri uri) _loader;
  final LinkedHashMap<String, Color> _cache = LinkedHashMap<String, Color>();
  static const int _maxCacheEntries = 64;

  /// 测试中使用的假服务：直接按 URL 返回颜色，不做任何 IO/解码。
  factory ArtworkColorService.forTesting(
    Color? Function(Uri uri) resolve,
  ) {
    return ArtworkColorService(
      loader: (uri) async => throw UnimplementedError(),
    ).._testResolve = resolve;
  }

  Color? Function(Uri uri)? _testResolve;

  /// 提取 [uri] 封面的主色。失败返回 null（调用方保持原色，绝不让
  /// 背景着色阻塞或破坏播放）。
  Future<Color?> colorFor(Uri uri) async {
    final key = uri.toString();
    final cached = _cache[key];
    if (cached != null) return cached;

    final testResolve = _testResolve;
    if (testResolve != null) {
      final color = testResolve(uri);
      if (color != null) _remember(key, color);
      return color;
    }

    try {
      final bytes = await _loader(uri);
      final color = await _extractDominant(bytes);
      if (color != null) _remember(key, color);
      return color;
    } catch (_) {
      return null;
    }
  }

  void _remember(String key, Color color) {
    _cache[key] = color;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// 有界解码：把图片缩放到最长边 <= 64px，再对像素做加权直方图统计，
  /// 忽略接近纯黑/纯白/低饱和的像素，取出现最多色桶的平均色。
  Future<Color?> _extractDominant(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      const maxEdge = 64;
      final scale = maxEdge /
          (descriptor.width > descriptor.height
                  ? descriptor.width
                  : descriptor.height)
              .clamp(1, maxEdge);
      codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(1, maxEdge),
        targetHeight: (descriptor.height * scale).round().clamp(1, maxEdge),
      );
      image = (await codec.getNextFrame()).image;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;
      return _dominantFromPixels(byteData.buffer.asUint8List());
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  /// 4-bit 每通道色桶统计（4096 桶），返回最高频桶的中心色。
  static Color? _dominantFromPixels(Uint8List rgba) {
    final histogram = Uint32List(16 * 16 * 16);
    var count = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      final a = rgba[i + 4 - 1];
      if (a < 160) continue; // 忽略透明像素
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
      if (max - min < 18) continue; // 忽略灰阶/低饱和
      if (max > 245 || min < 12) continue; // 忽略接近纯白/纯黑
      final index = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      histogram[index]++;
      count++;
    }
    if (count == 0) return null;
    // 取最高频色桶，用该桶中心作为稳定主色（避免逐帧抖动）。
    var bestIndex = 0;
    var bestCount = 0;
    for (var i = 0; i < histogram.length; i++) {
      if (histogram[i] > bestCount) {
        bestCount = histogram[i];
        bestIndex = i;
      }
    }
    final br = ((bestIndex >> 8) & 0xF) * 17;
    final bg = ((bestIndex >> 4) & 0xF) * 17;
    final bb = (bestIndex & 0xF) * 17;
    return Color.fromRGBO(br, bg, bb, 1);
  }

  static Future<Uint8List> _defaultLoader(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Mozilla/5.0');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('cover HTTP ${response.statusCode}', uri: uri);
      }
      return await response.fold<List<int>>(<int>[], (acc, chunk) {
        acc.addAll(chunk);
        return acc;
      }).then((list) => Uint8List.fromList(list));
    } finally {
      client.close(force: true);
    }
  }
}
