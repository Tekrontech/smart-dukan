import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// FLAG_SECURE on screens that show CNIC data (spec Section 9): blocks
/// screenshots, screen recording and the recent-apps preview. Implemented
/// in MainActivity via the `smartdukan/secure` channel.
class SecureScreen {
  SecureScreen._();

  static const _channel = MethodChannel('smartdukan/secure');

  static Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('setSecure', on);
    } on MissingPluginException {
      // Tests / non-Android: nothing to do.
    } on PlatformException {
      // Never block the user because of this.
    }
  }
}

/// Wrap a screen that shows CNIC data.
class SecureArea extends StatefulWidget {
  const SecureArea({super.key, required this.child});

  final Widget child;

  @override
  State<SecureArea> createState() => _SecureAreaState();
}

class _SecureAreaState extends State<SecureArea> {
  @override
  void initState() {
    super.initState();
    SecureScreen.set(true);
  }

  @override
  void dispose() {
    SecureScreen.set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
