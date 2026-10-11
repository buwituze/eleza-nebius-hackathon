// Widget tests for AllDoctorsPage and LoginScreen.
//
// Run from frontend/:
//   flutter test --reporter expanded

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/screens/all_doctors_page.dart';
import 'package:frontend/screens/login_screen.dart';

void main() {
  // ── AllDoctorsPage ────────────────────────────────────────────────────────
  group('AllDoctorsPage', () {
    // Admin UI is designed for desktop — widen the test viewport for every test.
    setUp(() {});

    testWidgets('shows a loading indicator on first render', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: AllDoctorsPage(userRole: 'platform_admin', userName: 'Test Admin'),
        ),
      );

      // First frame: _isLoading == true → spinner must be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders page title and Refresh button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: AllDoctorsPage(userRole: 'platform_admin', userName: 'Test Admin'),
        ),
      );

      // Header content is rendered unconditionally (not inside loading/error guards)
      expect(find.text('All doctors with their hospital assignment.'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });
  });

  // ── LoginScreen ───────────────────────────────────────────────────────────
  group('LoginScreen', () {
    setUp(() {
      // Provide an empty SharedPreferences store so _loadSavedCredentials()
      // doesn't look for real on-device data during tests.
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders welcome heading, both input fields, and Login button',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump(); // let _loadSavedCredentials complete

      expect(find.text('Log into your account'), findsOneWidget);
      // Two TextFields: Email Address + Password
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Remember me'), findsOneWidget);
    });

    testWidgets('password visibility toggle switches the eye icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();

      // Password starts hidden — show the closed-eye icon
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);

      // Tap the toggle
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();

      // Password is now visible — icon must flip
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    });
  });
}
