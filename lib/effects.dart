import 'package:flutter/painting.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

class WindowEffects {
  static bool _ready = false;
  static Future<void> setAcrylic(bool enabled) async {
    if (!_ready) {
      await Window.initialize();
      _ready = true;
    }
    await Window.setEffect(
      effect: enabled ? WindowEffect.acrylic : WindowEffect.solid,
      color: enabled ? const Color(0xA8FFF7E9) : const Color(0xFFFFF9EE),
      dark: false,
    );
  }
}
