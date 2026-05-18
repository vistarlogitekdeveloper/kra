import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Brand-tinted shimmer primitive.
///
/// Default gray shimmer looks generic — so we use a subtle purple base
/// (#E8E0EC) and a near-white highlight (#F5F0F8) that catches the
/// brand purple gently. Period is 1500ms — slower shimmers feel more
/// considered than the snappy 1000ms default.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry margin;

  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
    this.margin = EdgeInsets.zero,
  });

  static const Color _baseColor = Color(0xFFE8E0EC);
  static const Color _highlightColor = Color(0xFFF5F0F8);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Shimmer.fromColors(
        baseColor: _baseColor,
        highlightColor: _highlightColor,
        period: const Duration(milliseconds: 1500),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: _baseColor,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      ),
    );
  }
}
