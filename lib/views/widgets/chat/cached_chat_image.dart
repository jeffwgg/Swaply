import 'dart:io';

import 'package:flutter/material.dart';

import '../../../services/chat_media_cache_service.dart';

class CachedChatImage extends StatefulWidget {
  const CachedChatImage({
    required this.imageUrl,
    this.cachedPath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String imageUrl;
  final String? cachedPath;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<CachedChatImage> createState() => _CachedChatImageState();
}

class _CachedChatImageState extends State<CachedChatImage> {
  File? _cachedFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    if (widget.cachedPath != null) {
      final file = await ChatMediaCacheService.instance
          .getCachedMedia(widget.cachedPath);
      if (file != null && mounted) {
        setState(() => _cachedFile = file);
        return;
      }
    }

    setState(() => _isLoading = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedFile != null) {
      return Image.file(
        _cachedFile!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          return _buildError();
        },
      );
    }

    if (_isLoading) {
      return Image.network(
        widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildError();
        },
      );
    }

    return _buildError();
  }

  Widget _buildError() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[300],
      child: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}
