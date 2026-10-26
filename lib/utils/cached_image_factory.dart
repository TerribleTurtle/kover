import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

class CachedImageFactory extends WidgetFactory {
  final Map<int, (MemoryImage, Size?)> _cache = {};
  final double? maxHeight;

  CachedImageFactory({this.maxHeight});

  @override
  Widget? buildImageWidget(
    BuildTree meta,
    ImageSource src,
  ) {
    if (src.url.endsWith('.svg') || src.url.startsWith('data:image/svg+xml')) {
      return super.buildImageWidget(meta, src);
    }

    final hash = Object.hash(src.url, src.url.length);
    var cached = _cache[hash];
    if (cached == null) {
      final bytes = bytesFromDataUri(src.url);
      if (bytes == null) {
        return super.buildImageWidget(meta, src);
      }
      cached = (MemoryImage(bytes), _imageSize(bytes));
      _cache[hash] = cached;
    }
    final (provider, size) = cached;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight ?? double.infinity,
      ),
      child: Image(
        key: ValueKey(hash),
        image: provider,
        gaplessPlayback: true,
        fit: .contain,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return FittedBox(
            fit: .contain,
            child: SizedBox(
              height: src.height ?? size?.height ?? maxHeight,
              width: src.width ?? size?.width,
              child: const Center(child: CircularProgressIndicator()),
            ),
          );
        },
      ),
    );
  }

  // Parse header dimensions so synchronous headless layout matches decoded image bounds.
  static Size? _imageSize(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length >= 24 && data.getUint32(0) == 0x89504E47) {
      return Size(data.getUint32(16).toDouble(), data.getUint32(20).toDouble());
    }
    if (bytes.length >= 10 && data.getUint32(0) == 0x47494638) {
      return Size(
        data.getUint16(6, .little).toDouble(),
        data.getUint16(8, .little).toDouble(),
      );
    }
    if (bytes.length >= 4 && data.getUint16(0) == 0xFFD8) {
      for (var i = 2; i + 4 <= bytes.length;) {
        if (bytes[i] != 0xFF) break;
        while (i < bytes.length && bytes[i] == 0xFF) {
          i++;
        }
        if (i + 2 >= bytes.length) break;
        final m = bytes[i++];
        if (m == 0xD8 || m == 0xD9 || (m >= 0xD0 && m <= 0xD7)) continue;
        final len = data.getUint16(i);
        if (len < 2) break;
        if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
          return i + 7 <= bytes.length
              ? Size(
                  data.getUint16(i + 5).toDouble(),
                  data.getUint16(i + 3).toDouble(),
                )
              : null;
        }
        i += len;
      }
    }
    return null;
  }
}
