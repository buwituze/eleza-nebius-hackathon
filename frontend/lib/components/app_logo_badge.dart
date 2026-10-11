import 'package:flutter/material.dart';

class AppLogoBadge extends StatelessWidget {
  final double size;
  final double padding;
  final double borderWidth;
  final Color borderColor;
  final Color backgroundColor;

  const AppLogoBadge({
    super.key,
    required this.size,
    this.padding = 10,
    this.borderWidth = 1,
    this.borderColor = const Color(0xFF8B9E3A),
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Image.asset(
        'assets/images/logo_.png',
        fit: BoxFit.contain,
        errorBuilder:
            (context, error, stackTrace) => Icon(
              Icons.local_hospital_outlined,
              color: borderColor,
              size: size * 0.42,
            ),
      ),
    );
  }
}
