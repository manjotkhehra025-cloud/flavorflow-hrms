import 'package:flutter/material.dart';

import 'brand_config.dart';

/// The selected FlavorFlow team emblem, shared across app entry and brand surfaces.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.size, this.borderRadius = 0});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: '${BrandConfig.appName} team logo',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          BrandConfig.logoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
