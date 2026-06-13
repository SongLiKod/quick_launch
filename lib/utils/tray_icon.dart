import 'dart:io';
import 'dart:typed_data';

/// 生成简单的 "Q" 形 ICO 图标并保存到临时文件
class TrayIconHelper {
  static Uint8List generateIcon() {
    const w = 16, h = 16;
    final pixels = List.filled(w * h, 0);

    // 绘制 "Q" 形状 (蓝色系)
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final isBorder = x == 0 || x == w - 1 || y == 0 || y == h - 1;
        final isQ = (x >= 3 && x <= 12 && y >= 2 && y <= 9) &&
            !(x >= 4 && x <= 11 && y >= 3 && y <= 8);
        final isTail = (x == 10 || x == 11) && (y == 10 || y == 11);

        if (isBorder) {
          pixels[y * w + x] = 0xFF1A237E;
        } else if (isQ || isTail) {
          final t = (x + y) / (w + h);
          final r = (30 + 60 * t).round();
          final g = (80 + 100 * t).round();
          final b = (200 + 55 * t).round();
          pixels[y * w + x] = 0xFF000000 | (b << 16) | (g << 8) | r;
        } else {
          pixels[y * w + x] = 0xFFE3F2FD;
        }
      }
    }

    // BGRA bytes (bottom-up)
    final bgra = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final src = (h - 1 - y) * w + x;
        final dst = (y * w + x) * 4;
        bgra[dst] = (pixels[src] >> 0) & 0xFF;
        bgra[dst + 1] = (pixels[src] >> 8) & 0xFF;
        bgra[dst + 2] = (pixels[src] >> 16) & 0xFF;
        bgra[dst + 3] = (pixels[src] >> 24) & 0xFF;
      }
    }

    final andMask = Uint8List(w * h ~/ 8);
    const headerSize = 6 + 16;
    const bmpHdrSize = 40;
    final imgSize = bmpHdrSize + bgra.length + andMask.length;
    final total = headerSize + imgSize;
    final buf = Uint8List(total);
    final data = ByteData.view(buf.buffer);

    int off = 0;
    data.setUint16(0, 0, Endian.little);
    data.setUint16(2, 1, Endian.little);
    data.setUint16(4, 1, Endian.little);
    off = 6;
    data.setUint8(off, w);
    data.setUint8(off + 1, h);
    data.setUint8(off + 2, 0);
    data.setUint8(off + 3, 0);
    data.setUint16(off + 4, 1, Endian.little);
    data.setUint16(off + 6, 32, Endian.little);
    data.setUint32(off + 8, imgSize, Endian.little);
    data.setUint32(off + 12, headerSize, Endian.little);
    off += 16;
    data.setUint32(off, bmpHdrSize, Endian.little);
    data.setInt32(off + 4, w, Endian.little);
    data.setInt32(off + 8, h * 2, Endian.little);
    data.setUint16(off + 12, 1, Endian.little);
    data.setUint16(off + 14, 32, Endian.little);
    data.setUint32(off + 16, 0, Endian.little);
    for (int i = 20; i < bmpHdrSize; i++) {
      data.setUint8(off + i, 0);
    }
    off += bmpHdrSize;
    buf.setRange(off, off + bgra.length, bgra);
    off += bgra.length;
    buf.setRange(off, off + andMask.length, andMask);

    return buf;
  }

  /// 保存图标到临时文件并返回路径
  static Future<String> saveIconToFile() async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}\\quick_launch_tray_icon.ico');
    await file.writeAsBytes(generateIcon());
    return file.path;
  }
}
