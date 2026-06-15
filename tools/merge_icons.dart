// ignore_for_file: avoid_print
// 合并 logo16/32/48/64.ico → 多尺寸 app_icon.ico + assets/logo.ico
import 'dart:io';
import 'dart:typed_data';

void main() {
  final sizes = [16, 32, 48, 64];
  final files = sizes.map((s) => 'logo$s.ico').toList();

  // 解析每个 ICO 文件，提取图像数据
  final images = <Uint8List>[];
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    // ICO header: 6 bytes, then 16-byte directory entry
    final imgOffset = data.getUint32(6 + 12, Endian.little); // offset in directory
    final imgSize = data.getUint32(6 + 8, Endian.little); // size in directory
    images.add(bytes.sublist(imgOffset, imgOffset + imgSize));
  }

  // 合并为多尺寸 ICO
  final headerSize = 6 + sizes.length * 16;
  int total = headerSize;
  for (final img in images) {
    total += img.length;
  }
  final buf = Uint8List(total);
  final out = ByteData.view(buf.buffer, buf.offsetInBytes, total);

  int off = 0;
  out.setUint16(0, 0, Endian.little); // reserved
  out.setUint16(2, 1, Endian.little); // type = ICO
  out.setUint16(4, sizes.length, Endian.little); // count
  off = 6;
  int imgOff = headerSize;
  for (int i = 0; i < sizes.length; i++) {
    out.setUint8(off, sizes[i]);
    out.setUint8(off + 1, sizes[i]);
    out.setUint8(off + 2, 0); // colors
    out.setUint8(off + 3, 0); // reserved
    out.setUint16(off + 4, 1, Endian.little); // planes
    out.setUint16(off + 6, 32, Endian.little); // bpp
    out.setUint32(off + 8, images[i].length, Endian.little);
    out.setUint32(off + 12, imgOff, Endian.little);
    off += 16;
    buf.setRange(imgOff, imgOff + images[i].length, images[i]);
    imgOff += images[i].length;
  }

  // 写入目标文件
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(buf);
  File('assets/logo.ico').writeAsBytesSync(buf);
  print('[OK] Generated app_icon.ico + assets/logo.ico (${sizes.join("x, ")}x) — ${buf.length} bytes');
}
