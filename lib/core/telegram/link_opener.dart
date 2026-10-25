import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../storage/app_preferences.dart';

/// Opens a link the way the user chose (Settings → Chats → "Open links
/// in"): a Chromium Custom Tab by default, never an embedded WebView, or
/// the external browser app. mailto:, tel: and app links always go to the
/// system.
Future<bool> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  var external = false;
  try {
    external = context.read<AppPreferences>().openLinksExternally;
  } on ProviderNotFoundException {
    // Tests and previews: default behaviour.
  }
  final web = uri.scheme == 'http' || uri.scheme == 'https';
  return launchUrl(
    uri,
    mode: web && !external ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication,
  );
}
