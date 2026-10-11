import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AssignedExamsModal extends StatefulWidget {
  final int? sessionId;
  final String patientName;

  const AssignedExamsModal({
    Key? key,
    required this.sessionId,
    required this.patientName,
  }) : super(key: key);

  @override
  State<AssignedExamsModal> createState() => _AssignedExamsModalState();
}

class _AssignedExamsModalState extends State<AssignedExamsModal> {
  bool _isLoading = true;
  String? _errorMessage;
  List<String> _assignedExams = [];
  Map<String, dynamic>? _queueData;

  @override
  void initState() {
    super.initState();
    _loadAssignedExams();
  }

  Future<void> _loadAssignedExams() async {
    if (widget.sessionId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No session available';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final queueData = await ApiService.getQueueEntryForSession(
        widget.sessionId!,
      );

      if (!mounted) return;

      if (queueData != null) {
        final exams = queueData['required_exams'];
        final examsList =
            (exams != null && exams is List)
                ? List<String>.from(exams.map((e) => e.toString()))
                : <String>[];

        setState(() {
          _queueData = queueData;
          _assignedExams = examsList;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No assigned exams found for this patient';
          _assignedExams = [];
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load exams: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SingleChildScrollView(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assigned Exams',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Patient: ${widget.patientName}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Content
              _isLoading
                  ? const SizedBox(
                    height: 200,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF8B9E3A),
                      ),
                    ),
                  )
                  : _errorMessage != null
                  ? _buildErrorState()
                  : _assignedExams.isEmpty
                  ? _buildEmptyState()
                  : _buildExamsList(),
              const SizedBox(height: 20),
              // Footer button
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B9E3A),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red[400], size: 48),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.red[400]),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadAssignedExams,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[400],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.info_outline, color: Color(0xFFC1B967), size: 48),
          SizedBox(height: 16),
          Text(
            'No exams assigned yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _buildExamsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Metadata if available
        if (_queueData != null)
          Column(
            children: [
              _buildInfoRow('Room:', _queueData!['room_name'] ?? 'N/A'),
              _buildInfoRow('Status:', _queueData!['queue_status'] ?? 'N/A'),
              _buildInfoRow('Department:', _queueData!['department'] ?? 'N/A'),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFD1D5DB), height: 1),
              const SizedBox(height: 16),
            ],
          ),
        const Text(
          'Required Exams:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 12),
        ..._assignedExams.asMap().entries.map((entry) {
          final index = entry.key;
          final exam = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B9E3A),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      exam,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF374151),
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7280),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF111827),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
