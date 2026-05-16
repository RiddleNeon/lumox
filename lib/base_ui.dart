import 'package:flutter/material.dart';
import 'package:lumox/logic/users/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lumox/ui/router/router.dart';
import 'package:lumox/ui/theme/app_theme.dart';

import 'base_logic.dart';
import 'logic/repositories/user_repository.dart';

void startApp() async {
  final session = auth.currentSession;
  if (session != null) {
    final authUser = session.user;
    try {
      final user = await userRepository.getUserSupabase(authUser.id);
      if (user != null) {
        await onUserLogin(user, false);
      } else {
        print('Authenticated session found without profile. Waiting for onboarding completion.');
      }
    } on BanAuthException {
      userBannedHint = true;
      lastUserProfileId = authUser.id;
      await auth.signOut();
    } on AuthException catch (e) {
      print("Error fetching user profile: $e");
    }
  }

  initRouter();
  routerConfig.refresh();

  runApp(
    ValueListenableBuilder<(ThemeData, String)>(
      valueListenable: appThemeNotifier,
      builder: (context, value, child) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: value.$1,
          themeMode: value.$1.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: routerConfig,
        );
      },
    ),
  );
}

Brightness get currentSystemBrightness => WidgetsBinding.instance.platformDispatcher.platformBrightness;

final ValueNotifier<(ThemeData, String)> appThemeNotifier = ValueNotifier((currentSystemBrightness == Brightness.dark ? AppTheme.dark : AppTheme.light, currentSystemBrightness == Brightness.dark ? "default-dark" : "default"));


bool userBannedHint = false;
UserProfile? lastUserProfile; 
String? lastUserProfileId; 