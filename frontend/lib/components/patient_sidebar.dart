import 'package:flutter/material.dart';
import '../models/patient_model.dart';

class PatientSidebar extends StatefulWidget {
  final List<Patient> patients;
  final Patient? selectedPatient;
  final Function(Patient) onPatientSelected;
  final bool isAdmin;

  const PatientSidebar({
    Key? key,
    required this.patients,
    this.selectedPatient,
    required this.onPatientSelected,
    this.isAdmin = false,
  }) : super(key: key);

  @override
  State<PatientSidebar> createState() => _PatientSidebarState();
}

class _PatientSidebarState extends State<PatientSidebar> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Patient> get filteredPatients {
    if (_searchController.text.isEmpty) {
      return widget.patients;
    }
    return widget.patients
        .where(
          (patient) => patient.fullName.toLowerCase().contains(
            _searchController.text.toLowerCase(),
          ),
        )
        .toList();
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.amber;
      case 'low':
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          right: BorderSide(
            color: Color.fromARGB(255, 129, 129, 129),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
            ),
            child: const Text(
              'All Patients',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),

          // Patient list
          Expanded(
            child: ListView.builder(
              itemCount: filteredPatients.length,
              itemBuilder: (context, index) {
                final patient = filteredPatients[index];
                final isSelected =
                    widget.selectedPatient?.patientId == patient.patientId;

                return GestureDetector(
                  onTap: () {
                    widget.onPatientSelected(patient);
                  },
                  child: Container(
                    color: isSelected ? Colors.blue[50] : Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // Priority dot
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _getPriorityColor(patient.priorityLevel),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Patient info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                patient.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isSelected ? Colors.blue : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                patient.phoneNumber,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Eye icon for visibility toggle
                        Icon(
                          Icons.visibility,
                          size: 16,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
