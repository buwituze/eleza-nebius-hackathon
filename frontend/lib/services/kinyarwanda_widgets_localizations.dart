import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Custom Widgets Localizations Delegate for Kinyarwanda
/// Falls back to English since Flutter doesn't natively support Kinyarwanda
class KinyarwandaWidgetsLocalizations {
  static const LocalizationsDelegate<WidgetsLocalizations> delegate =
      _KinyarwandaWidgetsLocalizationsDelegate();
}

class _KinyarwandaWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _KinyarwandaWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'rw';

  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    // Use English (US) localizations as fallback for Kinyarwanda
    return GlobalWidgetsLocalizations.delegate.load(const Locale('en', 'US'));
  }

  @override
  bool shouldReload(_KinyarwandaWidgetsLocalizationsDelegate old) => false;
}
