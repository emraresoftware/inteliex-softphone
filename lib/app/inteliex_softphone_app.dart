import 'package:flutter/material.dart';

import '../core/config/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../services/sip/softphone_controller.dart';
import 'app_state_scope.dart';
import 'home_shell.dart';

class InteliexSoftphoneApp extends StatelessWidget {
  const InteliexSoftphoneApp({
    super.key,
    required this.controller,
  });

  final SoftphoneController controller;

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      controller: controller,
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
