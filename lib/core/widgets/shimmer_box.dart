import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../constants/app_colors.dart';

/// Brand-tinted shimmer primitive — Vistar Premium edition.
///
/// Dark `--surface2` base (`#16142A`) with a translucent pink → orange
/// sweep that mirrors the CSS `.skel::after` recipe in the design system.
/// Period is 1300ms so it reads as "considered" rather than spinny.
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

  // Base is a hair lighter than --surface2 so it's visible against cards
  // that sit on --surface2 themselves.
  static const Color _baseColor = AppColors.surfaceElevated;
  // Pink-orange average — picks up the ribbon's mid stops at low alpha.
  static const Color _highlightColor = Color(0x33E0218A);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Shimmer.fromColors(
        baseColor: _baseColor,
        highlightColor: _highlightColor,
        period: const Duration(milliseconds: 1300),
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
