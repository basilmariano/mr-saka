import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:forui/forui.dart';

import '../../l10n/app_localizations.dart';

/// Root widget.
///
/// Forui provides the visual language; MaterialApp stays underneath for routing,
/// dialogs, date pickers and localisation delegates, which Forui does not replace.
/// `FTheme` is installed via the `builder` so every route — including ones pushed
/// onto the navigator — sits inside it.
///
/// FR-055: v1 presents all farmer-facing text in English. FR-056/FR-057: the text
/// lives in ARB files and behaviour never branches on it, so the phase-2 local
/// language can be added without reworking screens.
class SakaApp extends StatelessWidget {
  const SakaApp({required this.home, super.key});

  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          FLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        // Light mode always. The app is used outdoors in bright sunlight, where a
        // dark surface reflects glare and washes out; following the device's dark
        // setting would make the numbers harder to read exactly when the farmer is
        // standing in the field trying to read them.
        theme: materialHost(Brightness.light),
        darkTheme: materialHost(Brightness.light),
        themeMode: ThemeMode.light,
        builder: (context, child) => FTheme(
          data: sakaTheme.light,
          child: child ?? const SizedBox.shrink(),
        ),
        home: home,
      );
}

/// Green, because this is a farming app and the palette should not fight that.
final sakaTheme = FThemes.green;

/// The thin Material layer beneath Forui.
///
/// Only the things Forui does not own are configured here: scaffold background,
/// date picker and dialog surfaces. Buttons and fields are Forui's, so no button
/// theme is set — the previous `Size.fromHeight` minimum, which forced infinite
/// width on any button inside a Row, is gone with it.
ThemeData materialHost(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E7D32),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.comfortable,
  );
}
