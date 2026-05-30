import 'package:flutter/material.dart';

/// A [CircleAvatar] that loads a network photo and falls back gracefully
/// to an initials avatar on any image error (404, 429, timeout, etc.).
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.photoUrl,
    required this.initials,
    required this.color,
    this.radius = 20,
    this.textStyle,
  });

  final String photoUrl;
  final String initials;
  final Color color;
  final double radius;
  final TextStyle? textStyle;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  bool _imageError = false;
  String? _lastUrl;

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.photoUrl != oldWidget.photoUrl) {
      _imageError = false;
    }
  }

  bool get _showImage => widget.photoUrl.isNotEmpty && !_imageError;

  @override
  Widget build(BuildContext context) {
    _lastUrl = widget.photoUrl;
    final fontSize = widget.radius * 0.65;

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.color.withValues(alpha: 0.15),
      backgroundImage: _showImage ? NetworkImage(widget.photoUrl) : null,
      onBackgroundImageError: _showImage
          ? (exception, stackTrace) {
              // Called on 429, 404, network errors etc.
              if (mounted && widget.photoUrl == _lastUrl) {
                setState(() => _imageError = true);
              }
            }
          : null,
      child: !_showImage
          ? Text(
              widget.initials,
              style: widget.textStyle ??
                  TextStyle(
                    color: widget.color,
                    fontWeight: FontWeight.w700,
                    fontSize: fontSize,
                  ),
            )
          : null,
    );
  }
}
