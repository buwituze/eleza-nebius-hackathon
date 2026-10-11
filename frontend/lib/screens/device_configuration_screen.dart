import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceConfigurationScreen extends StatefulWidget {
  const DeviceConfigurationScreen({Key? key}) : super(key: key);

  @override
  State<DeviceConfigurationScreen> createState() =>
      _DeviceConfigurationScreenState();
}

class _DeviceConfigurationScreenState extends State<DeviceConfigurationScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Hospital logo/icon
                Image.asset(
                  'assets/images/full-logo.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 40),

                // Welcome text
                const Text(
                  'Eleza',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                Text(
                  'Configure this device for hospital use',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black.withAlpha((0.7 * 255).toInt()),
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 60),

                // Device type selection
                const Text(
                  'What will this device be used for?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // Device type buttons in a row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 200, // Increased width by 20px
                      child: _buildDeviceTypeButton(
                        icon: Icons.mic,
                        title: 'Patient Kiosk',
                        subtitle: 'Voice consultation interface',
                        color: const Color(0xFF8B9E3A),
                        onPressed: () => _configureDevice('patient'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200, // Increased width by 20px
                      child: _buildDeviceTypeButton(
                        icon: Icons.medical_services,
                        title: 'Healthcare Provider',
                        subtitle: 'Patient management dashboard',
                        color: const Color(0xFFFFD700), // Gold color
                        onPressed: () => _configureDevice('provider'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 60),

                // Footer note
                Text(
                  'This configuration can be changed later in settings',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withAlpha((0.5 * 255).toInt()),
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 20),

                // Loading indicator
                if (_isLoading)
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceTypeButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      // Removed fixed height to prevent overflow
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12), // Smaller radius
        border: Border.all(color: Colors.grey[300]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).toInt()),
            blurRadius: 8, // Smaller shadow
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _isLoading ? null : onPressed,
          splashColor: Colors.transparent, // Remove splash effect
          highlightColor: Colors.transparent, // Remove highlight effect
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ), // Reduced padding
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: color,
                ), // Use the color parameter for icons
                const SizedBox(height: 6), // Reduced spacing
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12, // Smaller font
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2), // Reduced spacing
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10, // Smaller font
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _configureDevice(String deviceType) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Save device configuration
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_type', deviceType);
      await prefs.setBool('device_configured', true);

      // Navigate to appropriate interface
      if (deviceType == 'patient') {
        Navigator.pushReplacementNamed(context, '/voice-interface');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Configuration failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
