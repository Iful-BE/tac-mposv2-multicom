// lib/utils/printer_helper.dart

enum PaperSize { mm58, mm80 }

class PrintFormat {
  final int paper; // total kolom aman

  PrintFormat(this.paper);
}

/// NOTE:
/// - 58mm  ≈ 28–29 kolom aman
/// - 80mm  ≈ 38–40 kolom aman
/// Angka ini SUDAH DIKURANGI margin fisik printer
PrintFormat getFormat(PaperSize size) {
  switch (size) {
    case PaperSize.mm58:
      return PrintFormat(32); // JANGAN lebih
    case PaperSize.mm80:
    default:
      return PrintFormat(42); // TERBUKTI AMAN
  }
}

/// Cetak: [text kiri][spasi][harga]
/// Harga TIDAK pernah nempel ujung kanan printer
String lr(String left, String right, PrintFormat f) {
  // minimal 1 spasi antara kiri dan kanan
  final maxLeft = f.paper - right.length - 1;

  final l = left.length > maxLeft
      ? left.substring(0, maxLeft)
      : left.padRight(maxLeft);

  return '$l $right';
}
