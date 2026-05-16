import 'package:flutter/material.dart';
import 'package:lumox/base_logic.dart';

import 'base_ui.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  debugPrint = (String? message, {int? wrapWidth}) {if(!(message?.startsWith("Got object store box") ?? false)) {}};
  await initLogic();
  //? await publishTest();

  startApp();
}