import "package:flutter/material.dart";

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        "assets/brand.png",
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
