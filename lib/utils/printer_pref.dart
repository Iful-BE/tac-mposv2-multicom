import 'package:shared_preferences/shared_preferences.dart';
import 'printer_helper.dart';

class PrinterPref {
  static const _keyPaperSize = 'paper_size';

  static Future<void> setPaperSize(PaperSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyPaperSize,
      size == PaperSize.mm58 ? '58' : '80',
    );
  }

  static Future<PaperSize> getPaperSize() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyPaperSize) ?? '80';

    return value == '58' ? PaperSize.mm58 : PaperSize.mm80;
  }
}
