import 'package:flutter/material.dart';
import '../models/patient_model.dart';

class PatientPersonalDataCard extends StatelessWidget {
  final Patient patient;
  final PatientSession? session;

  const PatientPersonalDataCard({Key? key, required this.patient, this.session})
    : super(key: key);

  Widget _buildInfoTile(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value ?? 'Not available',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                'Patient Personal Data',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),

              // Full Name
              _buildInfoTile('Full Name', patient.fullName),

              const Divider(height: 1),

              // Age
              _buildInfoTile(
                'Age',
                patient.age != null
                    ? '${patient.age} years old'
                    : 'Not recorded',
              ),

              const Divider(height: 1),

              // Phone Number
              _buildInfoTile('Phone Number', patient.phoneNumber),

              const Divider(height: 1),

              // Residency / Location
              _buildInfoTile('Residency Location', patient.location),

              const Divider(height: 1),

              // Visit Date (from session)
              if (session != null)
                _buildInfoTile(
                  'Visitation Date',
                  _formatDate(session!.startTime),
                ),

              if (session != null) const Divider(height: 1),

              // Visitation Time (from session)
              if (session != null)
                _buildInfoTile(
                  'Visitation Time',
                  _formatTime(session!.startTime),
                ),

              if (session != null) const Divider(height: 1),

              // Period (if session has end time)
              if (session != null && session!.endTime != null)
                _buildInfoTile(
                  'Duration',
                  _calculateDuration(session!.startTime, session!.endTime!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day} ${_getMonthName(dateTime.month)} ${dateTime.year}';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _calculateDuration(DateTime start, DateTime end) {
    final duration = end.difference(start);
    final minutes = duration.inMinutes;
    final hours = duration.inHours;

    if (hours > 0) {
      final mins = minutes % 60;
      return '$hours h ${mins}m';
    } else {
      return '${minutes} minutes';
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
