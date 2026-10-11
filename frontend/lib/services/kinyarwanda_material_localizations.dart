import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Custom Material Localizations Delegate for Kinyarwanda
/// Falls back to English since Flutter doesn't natively support Kinyarwanda
class KinyarwandaMaterialLocalizations {
  static const LocalizationsDelegate<MaterialLocalizations> delegate =
      _KinyarwandaMaterialLocalizationsDelegate();
}

class _KinyarwandaMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _KinyarwandaMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'rw';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    // Use English (US) localizations as fallback for Kinyarwanda
    return GlobalMaterialLocalizations.delegate.load(const Locale('en', 'US'));
  }

  @override
  bool shouldReload(_KinyarwandaMaterialLocalizationsDelegate old) => false;
}
