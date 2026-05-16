import 'package:flutter/material.dart';
import 'package:lumox/ui/router/router.dart';

import '../../base_logic.dart';

class LogoutButton extends StatefulWidget {
  const LogoutButton({super.key});

  @override
  State<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<LogoutButton> {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: "logout",
      child: InkWell(
        onTap: () async {
          await onUserLogout();
          routerConfig.go('/login-force');
        },
        child: const Icon(Icons.logout_rounded),
      ),
    );
  }
}
