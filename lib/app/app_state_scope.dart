import 'package:flutter/widgets.dart';

import '../services/sip/softphone_controller.dart';

class AppStateScope extends InheritedNotifier<SoftphoneController> {
  const AppStateScope({
    super.key,
    required SoftphoneController controller,
    required super.child,
  }) : super(notifier: controller);

  static SoftphoneController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();

    assert(scope != null, 'AppStateScope bulunamadi.');

    return scope!.notifier!;
  }
}
