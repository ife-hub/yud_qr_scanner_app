import 'package:flutter/material.dart';

/// Shows assets/photos/{id}.jpg in a circle. Falls back to a solid black
/// circle if no matching photo exists (matches the design's placeholder).
class PhotoAvatar extends StatelessWidget {
  final String id;
  final double radius;

  const PhotoAvatar({super.key, required this.id, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/photos/$id.jpg',
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: radius * 2,
          height: radius * 2,
          color: Colors.black,
        ),
      ),
    );
  }
}
