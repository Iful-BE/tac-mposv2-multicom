import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  static final ValueNotifier<Color> primaryColor =
      ValueNotifier(Colors.redAccent);

  static Future<void> loadThemeColor() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int? colorValue = prefs.getInt('theme_color');
    if (colorValue != null) {
      primaryColor.value = Color(colorValue);
    }
  }

  static Future<void> setThemeColor(Color color) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color', color.value);
    primaryColor.value = color;
  }
}
