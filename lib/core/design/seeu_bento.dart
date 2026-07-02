import 'package:flutter/material.dart';

import 'tokens.dart';

/// Bento-сетка из чанков: каждый чанк — `BentoChunk` со своим layout-pattern'ом
/// (например `1+2` — большая карточка слева + 2 маленьких справа). Бренд-фишка:
/// ленты не плоские grid'ы, а ритмично-разбитые блоки.
///
/// Пример использования (Explore):
/// ```dart
/// SeeUBento(
///   gap: 8,
///   chunks: [
///     BentoChunk.oneLeftTwoRight(left: tile(0), top: tile(1), bottom: tile(2)),
///     BentoChunk.threeStripe(a: tile(3), b: tile(4), c: tile(5)),
///     BentoChunk.twoLeftOneRight(top: tile(6), bottom: tile(7), right: tile(8)),
///   ],
/// )
/// ```
class SeeUBento extends StatelessWidget {
  final List<BentoChunk> chunks;
  final double gap;

  const SeeUBento({
    super.key,
    required this.chunks,
    this.gap = SeeUSpacing.sm,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < chunks.length; i++) {
      children.add(chunks[i].build(gap: gap));
      if (i < chunks.length - 1) children.add(SizedBox(height: gap));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Один блок (чанк) bento-сетки. Каждый паттерн — статический-конструктор,
/// чтобы не плодить magic-int'ы и DI'ить layout сборкой через named-args.
class BentoChunk {
  final Widget Function({required double gap}) _builder;

  const BentoChunk._(this._builder);

  Widget build({required double gap}) => _builder(gap: gap);

  /// `[A | B ]`
  /// `[A | C ]`  — большая карточка A слева во всю высоту, B сверху и C снизу справа.
  factory BentoChunk.oneLeftTwoRight({
    required Widget left,
    required Widget top,
    required Widget bottom,
    double height = 240,
  }) {
    return BentoChunk._(
      ({required gap}) => SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: left),
            SizedBox(width: gap),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: top),
                  SizedBox(height: gap),
                  Expanded(child: bottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `[A | C ]`
  /// `[B | C ]` — A сверху и B снизу слева, C во всю высоту справа.
  factory BentoChunk.twoLeftOneRight({
    required Widget top,
    required Widget bottom,
    required Widget right,
    double height = 240,
  }) {
    return BentoChunk._(
      ({required gap}) => SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: top),
                  SizedBox(height: gap),
                  Expanded(child: bottom),
                ],
              ),
            ),
            SizedBox(width: gap),
            Expanded(flex: 3, child: right),
          ],
        ),
      ),
    );
  }

  /// `[A | B | C]` — горизонтальная полоса из 3 равных карточек.
  factory BentoChunk.threeStripe({
    required Widget a,
    required Widget b,
    required Widget c,
    double height = 110,
  }) {
    return BentoChunk._(
      ({required gap}) => SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: a),
            SizedBox(width: gap),
            Expanded(child: b),
            SizedBox(width: gap),
            Expanded(child: c),
          ],
        ),
      ),
    );
  }

  /// `[A    A]`
  /// `[B  C D]` — большая широкая карточка сверху и три равных снизу.
  factory BentoChunk.heroTopThreeBottom({
    required Widget hero,
    required Widget a,
    required Widget b,
    required Widget c,
    double topHeight = 180,
    double bottomHeight = 110,
  }) {
    return BentoChunk._(
      ({required gap}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topHeight, child: hero),
          SizedBox(height: gap),
          SizedBox(
            height: bottomHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: a),
                SizedBox(width: gap),
                Expanded(child: b),
                SizedBox(width: gap),
                Expanded(child: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
