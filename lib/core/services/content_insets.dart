import 'package:flutter/widgets.dart';

/// 统一的内容安全区（对标 TuneFreeNext 的 `TuneShellContentInsets`）。
///
/// ## 设计原则：单一真相
///
/// Insets 的唯一分发通道仍然是 Flutter 原生的 `MediaQuery`。本类**不**新建
/// 平行的 `InheritedNotifier`/Provider——那样会和 MediaQuery 形成两个数据源，
/// 两者更新不同步时恰恰会造成「双重避让 / 漏避让」。这里做的是把散落在各处的
/// 两件事收敛到一处：
///
/// 1. **计算**：原生挖孔高度（`DeviceInsets.top`）与 Flutter `padding.top` 的
///    「只补不覆盖」取大逻辑，收敛到 [resolve] / [effectiveTop]，可独立单测；
/// 2. **读取**：所有顶部组件统一走 [topOf]，语义是「当前还需要让出多少」——
///    已经被 `SafeArea` 消费过的子树读到 0，因此头部组件可以无条件叠加而
///    不会双重避让。这与改动前逐字一致。
///
/// ## 用法
///
/// - 根节点：`MediaQuery(data: ContentInsets.resolve(mq, nativeTop), child: …)`
/// - 头部组件：`final inset = ContentInsets.topOf(context)`
/// - 需要整份快照：`final insets = ContentInsets.of(context)`
@immutable
class ContentInsets {
  const ContentInsets._({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
    required this.viewTop,
  });

  /// 顶部系统区（状态栏 + 挖孔），已含原生补足。
  final double top;
  final double bottom;
  final double left;
  final double right;

  /// 被键盘等占据的视图 inset 顶部，常规页面恒为 0。
  final double viewTop;

  /// 原生报告的顶部安全区大于 Flutter 报告值时取原生值，否则保持 Flutter 值。
  ///
  /// 这是「补足」而非「覆盖」：正常设备上两者一致，行为与改动前完全相同；
  /// 只有少数国产 ROM 不透传 `displayCutout`、导致 Flutter 少算挖孔时才会抬高。
  static double effectiveTop(double flutterTop, double nativeTop) =>
      nativeTop > flutterTop ? nativeTop : flutterTop;

  /// 把原生补足应用到 [MediaQueryData]，由根节点包裹一次。
  ///
  /// 未发生变化时直接返回原对象，避免无谓的 MediaQuery 变更广播。
  static MediaQueryData resolve(MediaQueryData data, double nativeTop) {
    final effective = effectiveTop(data.padding.top, nativeTop);
    if (effective == data.padding.top) return data;
    return data.copyWith(
      padding: data.padding.copyWith(top: effective),
      viewPadding: data.viewPadding.copyWith(top: effective),
    );
  }

  /// 从当前 context 读取一份 [ContentInsets] 快照。
  factory ContentInsets.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ContentInsets._(
      top: mq.padding.top,
      bottom: mq.padding.bottom,
      left: mq.padding.left,
      right: mq.padding.right,
      viewTop: mq.viewInsets.top,
    );
  }

  /// 顶部还需要让出的高度。
  ///
  /// 已被 `SafeArea` 消费的子树读到 0——这正是「读多少让多少」不双重避让的关键。
  static double topOf(BuildContext context) => MediaQuery.paddingOf(context).top;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentInsets &&
          other.top == top &&
          other.bottom == bottom &&
          other.left == left &&
          other.right == right &&
          other.viewTop == viewTop);

  @override
  int get hashCode => Object.hash(top, bottom, left, right, viewTop);

  @override
  String toString() =>
      'ContentInsets(top: $top, left: $left, right: $right, '
      'bottom: $bottom, viewTop: $viewTop)';
}
