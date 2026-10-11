import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/voice_interface_page.dart';
import 'screens/patient_detail_page.dart';
import 'screens/device_configuration_screen.dart';
import 'screens/login_screen.dart';
import 'screens/all_patients.dart';
import 'screens/all_doctors_page.dart';
import 'screens/admin_users_page.dart';
import 'screens/facilities_page.dart';
import 'screens/hospital_admin_dashboard.dart';
import 'services/kinyarwanda_material_localizations.dart';
import 'services/kinyarwanda_cupertino_localizations.dart';
import 'services/kinyarwanda_widgets_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('rw')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('rw'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<String> _initialRoute;

  @override
  void initState() {
    super.initState();
    _initialRoute = _determineInitialRoute();
  }

  Future<String> _determineInitialRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if device has been configured
      final isConfigured = prefs.getBool('device_configured') ?? false;

      if (!isConfigured) {
        // First time - show device configuration
        return '/device-configuration';
      }

      // Device is configured - check device type
      final deviceType = prefs.getString('device_type') ?? 'patient';

      if (deviceType == 'patient') {
        // Patient kiosk - go straight to voice interface
        return '/voice-interface';
      } else {
        // Provider device - go to login
        return '/login';
      }
    } catch (e) {
      // If anything fails, default to configuration screen
      return '/device-configuration';
    }
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/all-patients':
        return MaterialPageRoute(
          builder: (_) => const AllPatientsPage(),
          settings: settings,
        );
      case '/hospital-admin':
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder:
              (_) => HospitalAdminDashboard(
                userRole: args?['userRole'] as String? ?? 'hospital_admin',
                userName: args?['userName'] as String? ?? '',
              ),
          settings: settings,
        );
      case '/all-doctors':
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder:
              (_) => AllDoctorsPage(
                userRole: args?['userRole'] as String? ?? 'hospital_admin',
                userName: args?['userName'] as String? ?? '',
              ),
          settings: settings,
        );
      case '/facilities':
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder:
              (_) => FacilitiesPage(
                userRole: args?['userRole'] as String? ?? 'platform_admin',
                userName: args?['userName'] as String? ?? '',
              ),
          settings: settings,
        );
      case '/admin-users':
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder:
              (_) => AdminUsersPage(
                userRole: args?['userRole'] as String? ?? 'platform_admin',
                userName: args?['userName'] as String? ?? '',
              ),
          settings: settings,
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pre-Consultation Agent',
      localizationsDelegates: [
        KinyarwandaMaterialLocalizations.delegate,
        KinyarwandaCupertinoLocalizations.delegate,
        KinyarwandaWidgetsLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        ...context.localizationDelegates,
      ],
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: ThemeData(
        // Avoid depending on remote Roboto downloads on web.
        fontFamily: 'Arial',
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return DefaultTextStyle.merge(
          style: const TextStyle(
            fontFamily: 'Arial',
            fontFamilyFallback: ['Segoe UI', 'Noto Sans', 'sans-serif'],
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      onGenerateRoute: _onGenerateRoute,
      home: FutureBuilder<String>(
        future: _initialRoute,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Show loading screen while determining route
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text(
                      'Setting up device...',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            // If error, go to configuration
            return const DeviceConfigurationScreen();
          }

          final route = snapshot.data ?? '/device-configuration';
          return _buildHomeFromRoute(route);
        },
      ),
      routes: {
        '/device-configuration': (context) => const DeviceConfigurationScreen(),
        '/voice-interface': (context) => const VoiceInterfacePage(),
        '/login': (context) => const LoginScreen(),
        '/patient-detail':
            (context) => const PatientDetailPage(
              userRole: 'doctor',
              userName: 'Dr. Ingarire Yvette',
            ),
        '/patient-detail-admin':
            (context) => const PatientDetailPage(
              userRole: 'platform_admin',
              userName: 'Admin User',
            ),
      },
    );
  }

  Widget _buildHomeFromRoute(String route) {
    switch (route) {
      case '/device-configuration':
        return const DeviceConfigurationScreen();
      case '/voice-interface':
        return const VoiceInterfacePage();
      case '/login':
        return const LoginScreen();
      case '/patient-detail':
        return const PatientDetailPage(
          userRole: 'doctor',
          userName: 'Dr. Ingarire Yvette',
        );
      case '/patient-detail-admin':
        return const PatientDetailPage(
          userRole: 'platform_admin',
          userName: 'Admin User',
        );
      default:
        return const DeviceConfigurationScreen();
    }
  }
}
