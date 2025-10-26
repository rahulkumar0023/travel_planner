import 'package:flutter/widgets.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void navToSignIn() {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  nav.pushNamedAndRemoveUntil('/sign-in', (r) => false);
}

