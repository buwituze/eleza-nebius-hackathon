import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Custom Cupertino Localizations Delegate for Kinyarwanda
/// Falls back to English since Flutter doesn't natively support Kinyarwanda
class KinyarwandaCupertinoLocalizations {
  static const LocalizationsDelegate<CupertinoLocalizations> delegate =
      _KinyarwandaCupertinoLocalizationsDelegate();
}

class _KinyarwandaCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _KinyarwandaCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'rw';

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    // Use English (US) localizations as fallback for Kinyarwanda
    return GlobalCupertinoLocalizations.delegate.load(const Locale('en', 'US'));
  }

  @override
  bool shouldReload(_KinyarwandaCupertinoLocalizationsDelegate old) => false;
}
