import 'package:flutter/material.dart';

import '../components/app_navbar.dart';
import '../components/assign_room_dialog.dart';
import '../components/assigned_exams_modal.dart';
import '../screens/rooms_page.dart';
import '../services/api_service.dart';

const _kBorder = Color(0xFFCBD5E1);
const _kBorderLight = Color(0xFFD1D5DB);
const _kPageBg = Colors.white;
const _kGreen = Color(0xFF8B9E3A);
const _kTextPrimary = Color(0xFF111827);
const _kTextSecondary = Color(0xFF374151);
const _kTextMuted = Color(0xFF6B7280);

class PatientDetailPage extends StatefulWidget {
  final String userRole; // 'doctor', 'hospital_admin', 'platform_admin'
  final String userName;
  final String? userSpecialty;
  final int? initialPatientId;

  const PatientDetailPage({
    super.key,
    required this.userRole,
    required this.userName,
    this.userSpecialty,
    this.initialPatientId,
  });

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  final TextEditingController _sidebarSearchController =
      TextEditingController();

  List<PatientListItem> _patientListItems = [];
  PatientListItem? _selectedListItem;
  PatientDetail? _selectedPatientDetail;
  SessionDetail? _selectedSessionDetail;
  PatientBrief? _patientBrief;

  bool _isLoadingPatients = true;
  bool _isLoadingDetail = false;
  String? _patientsError;
  String? _detailError;
  String _sidebarSearch = '';

  String get _normalizedUserRole {
    return widget.userRole
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  bool get _isPlatformAdmin => _normalizedUserRole == 'platform_admin';
  bool get _isDoctor => _normalizedUserRole == 'doctor';

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  @override
  void dispose() {
    _sidebarSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoadingPatients = true;
      _patientsError = null;
    });

    try {
      final patients = await ApiService.getPatients();
      patients.sort((a, b) {
        final aTime = _parseDateTime(a.startTime);
        final bTime = _parseDateTime(b.startTime);
        if (aTime == null && bTime == null) {
          return a.fullName.compareTo(b.fullName);
        }
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime); // latest first
      });

      if (!mounted) return;
      setState(() {
        _patientListItems = patients;
        _isLoadingPatients = false;
      });

      if (patients.isNotEmpty) {
        final requestedId = widget.initialPatientId;
        final initial =
            requestedId == null
                ? patients.first
                : patients.firstWhere(
                  (item) => item.patientId == requestedId,
                  orElse: () => patients.first,
                );
        _selectPatient(initial);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _patientsError = 'Failed to load patients: $e';
        _isLoadingPatients = false;
      });
    }
  }

  void _selectPatient(PatientListItem patientListItem) {
    setState(() {
      _selectedListItem = patientListItem;
      _selectedPatientDetail = null;
      _selectedSessionDetail = null;
      _patientBrief = null;
      _detailError = null;
      _isLoadingDetail = true;
    });
    _loadPatientData(patientListItem);
  }

  Future<void> _loadPatientData(PatientListItem patientListItem) async {
    try {
      final patientDetail = await ApiService.getPatient(
        patientListItem.patientId,
      );

      SessionDetail? sessionDetail;
      if (patientListItem.sessionId != null) {
        sessionDetail = await ApiService.getSessionDetail(
          patientListItem.patientId,
          patientListItem.sessionId!,
        );
      }

      if (!mounted) return;
      setState(() {
        _selectedPatientDetail = patientDetail;
        _selectedSessionDetail = sessionDetail;
        _patientBrief = _buildPatientBrief(sessionDetail);
        _isLoadingDetail = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detailError = 'Failed to load patient data: $e';
        _isLoadingDetail = false;
      });
    }
  }

  PatientBrief? _buildPatientBrief(SessionDetail? sessionDetail) {
    if (sessionDetail == null) return null;
    final doctorBrief = sessionDetail.doctorBrief;
    if (doctorBrief == null || doctorBrief.isEmpty) return null;

    return PatientBrief(
      narrativeSummary: (doctorBrief['narrative_summary'] ?? '').toString(),
      keyFindings: _toStringList(doctorBrief['key_findings']),
      redFlagNote: (doctorBrief['red_flag_note'] ?? '').toString(),
      chiefComplaint: (doctorBrief['chief_complaint'] ?? '').toString(),
      bodyPart: doctorBrief['body_part']?.toString(),
      duration: doctorBrief['duration']?.toString(),
      severity: doctorBrief['severity']?.toString(),
      associatedSymptoms: _toStringList(doctorBrief['associated_symptoms']),
      riskFactors: _toStringList(doctorBrief['risk_factors']),
      suspectedIssue: doctorBrief['suspected_issue']?.toString(),
      confidenceScore: _asDouble(doctorBrief['confidence_score']),
      priority: (doctorBrief['priority'] ?? 'low').toString(),
    );
  }

  List<String> _toStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  int? get _resolvedAge {
    if (_selectedListItem?.age != null) return _selectedListItem!.age;
    final fromExtraction =
        _selectedSessionDetail?.extractionData?['patient_age'];
    if (fromExtraction is int) return fromExtraction;
    if (fromExtraction is String) return int.tryParse(fromExtraction);
    return null;
  }

  String get _resolvedResidency {
    final location = (_selectedPatientDetail?.location ?? '').trim();
    if (location.isNotEmpty) return location;
    final fallback = (_selectedListItem?.residency ?? '').trim();
    if (fallback.isNotEmpty) return fallback;
    return '--';
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '--';
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
    return '${dateTime.day.toString().padLeft(2, '0')} ${months[dateTime.month - 1]} ${dateTime.year}';
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '--';
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  List<String> _symptomItems() {
    if (_patientBrief != null && _patientBrief!.associatedSymptoms.isNotEmpty) {
      return _patientBrief!.associatedSymptoms;
    }

    final symptoms = <String>[];
    for (final symptom
        in _selectedSessionDetail?.symptoms ?? const <Map<String, dynamic>>[]) {
      final name = (symptom['symptom_name'] ?? '').toString().trim();
      if (name.isNotEmpty) symptoms.add(name);
    }
    return symptoms;
  }

  List<String> _clarificationQuestions() {
    final questions = <String>[];
    for (final msg
        in _selectedSessionDetail?.conversation ??
            const <Map<String, dynamic>>[]) {
      final sender = (msg['sender_type'] ?? '').toString().toLowerCase();
      final text = (msg['message_text'] ?? '').toString().trim();
      if (sender != 'patient' && text.contains('?')) {
        questions.add(text);
      }
    }
    return questions;
  }

  List<_GraphDatum> _factorGraphData() {
    final age = _resolvedAge;
    final symptomCount = _symptomItems().length;
    final gender =
        (_selectedSessionDetail?.extractionData?['patient_gender'] ?? '')
            .toString()
            .trim();
    final residency = _resolvedResidency;

    final ageScore =
        age == null
            ? 0.25
            : (age >= 60
                ? 0.85
                : (age >= 45 ? 0.62 : (age >= 18 ? 0.38 : 0.55)));
    final symptomScore = (0.18 + (symptomCount * 0.16)).clamp(0.0, 1.0);
    final genderScore = gender.isEmpty ? 0.20 : 0.44;
    final residencyScore = residency == '--' ? 0.22 : 0.50;

    return [
      _GraphDatum(label: 'Age', value: ageScore),
      _GraphDatum(label: 'Symptoms', value: symptomScore),
      _GraphDatum(label: 'Gender', value: genderScore),
      _GraphDatum(label: 'Residency', value: residencyScore),
    ];
  }

  List<_GraphDatum> _confidenceGraphData() {
    final modelConfidence = (_patientBrief?.confidenceScore ?? 0.0).clamp(
      0.0,
      1.0,
    );
    final transcriptQuality =
        (_selectedSessionDetail?.transcriptConfidence ?? 0.0).clamp(0.0, 1.0);

    final severityRaw =
        _selectedSessionDetail?.scoreData?['severity_estimate'] ??
        _selectedSessionDetail?.extractionData?['severity_estimate'];
    double severityScore = 0.0;
    if (severityRaw is num) {
      severityScore = (severityRaw.toDouble() / 10.0).clamp(0.0, 1.0);
    } else if (severityRaw is String) {
      final parsed = double.tryParse(severityRaw);
      if (parsed != null) {
        severityScore = (parsed / 10.0).clamp(0.0, 1.0);
      } else {
        severityScore = _severityTextToScore(severityRaw);
      }
    }
    // Fallback: use doctorBrief severity text when no numeric value
    if (severityScore == 0.0) {
      final severityText = _patientBrief?.severity ?? '';
      if (severityText.isNotEmpty) {
        severityScore = _severityTextToScore(severityText);
      }
    }

    return [
      _GraphDatum(label: 'Model', value: modelConfidence),
      _GraphDatum(label: 'Transcript', value: transcriptQuality),
      _GraphDatum(
        label: 'Severity',
        value: severityScore,
        barColor: _severityColor(severityScore),
      ),
    ];
  }

  double _severityTextToScore(String text) {
    switch (text.trim().toLowerCase()) {
      case 'mild':
        return 0.25;
      case 'low':
        return 0.30;
      case 'moderate':
      case 'medium':
        return 0.60;
      case 'high':
        return 0.80;
      case 'severe':
        return 0.90;
      case 'critical':
        return 1.0;
      default:
        return 0.0;
    }
  }

  Color _severityColor(double score) {
    if (score >= 0.75) return const Color(0xFFDC2626);
    if (score >= 0.45) return const Color(0xFFF59E0B);
    return _kGreen;
  }

  @override
  Widget build(BuildContext context) {
    final isPlatformAdmin = _isPlatformAdmin;

    return Scaffold(
      backgroundColor: _kPageBg,
      body: Column(
        children: [
          AppNavBar(
            currentUserName: widget.userName,
            currentUserRole: widget.userRole,
            currentUserSpecialty: widget.userSpecialty,
            navItems: [
              NavBarItem(
                label: 'All Patients',
                onTap: () => _goToAllPatients(),
              ),
              NavBarItem(label: 'Rooms', onTap: () => _goToRooms()),
            ],
            activeItem: 'All Patients',
            onSettingsTap: () {},
            onPatientTap: (id) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PatientDetailPage(
                  userRole: widget.userRole,
                  userName: widget.userName,
                  userSpecialty: widget.userSpecialty,
                  initialPatientId: id,
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 1180;
                if (isCompact) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(0, 24, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 360, child: _buildSidebar()),
                        const SizedBox(height: 14),
                        _buildMainContent(isPlatformAdmin, compact: true),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(0, 24, 14, 14),
                  child: Row(
                    children: [
                      SizedBox(width: 260, child: _buildSidebar()),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMainContent(
                          isPlatformAdmin,
                          compact: false,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    if (_isLoadingPatients) {
      return _panelShell(
        child: const Center(
          child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2),
        ),
      );
    }

    if (_patientsError != null) {
      return _panelShell(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All Patients',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: _kTextPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _patientsError!,
              style: const TextStyle(fontSize: 12, color: _kTextSecondary),
            ),
            const SizedBox(height: 10),
            _outlinedAction(label: 'Retry', onTap: _loadPatients),
          ],
        ),
      );
    }

    final filtered =
        _patientListItems.where((item) {
          if (_sidebarSearch.trim().isEmpty) return true;
          return item.fullName.toLowerCase().contains(
            _sidebarSearch.trim().toLowerCase(),
          );
        }).toList();

    return _panelShell(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _kBorderLight, width: 1),
              ),
            ),
            child: Row(
              children: const [
                Expanded(
                  child: Text(
                    'All Patients',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kTextPrimary,
                    ),
                  ),
                ),
                Icon(Icons.search, size: 16, color: Colors.black),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _sidebarSearchController,
                onChanged: (value) => setState(() => _sidebarSearch = value),
                style: const TextStyle(fontSize: 12, color: _kTextPrimary),
                decoration: InputDecoration(
                  hintText: 'Search patient',
                  hintStyle: const TextStyle(fontSize: 12, color: _kTextMuted),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: _kBorder, width: 1.4),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                final isSelected =
                    _selectedListItem?.patientId == item.patientId;
                return InkWell(
                  onTap: () => _selectPatient(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? const Color(0xFFF3F4E8) : Colors.white,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: _kTextPrimary,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _priorityDotColor(item.priority),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.visibility_outlined,
                          size: 14,
                          color: Colors.black,
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

  Color _priorityDotColor(String? priority) {
    switch ((priority ?? '').toLowerCase()) {
      case 'high':
        return const Color(0xFFDC2626);
      case 'medium':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFFA7F3A0);
    }
  }

  Widget _buildMainContent(bool isPlatformAdmin, {required bool compact}) {
    if (_selectedListItem == null && !_isLoadingPatients) {
      return _panelShell(
        padding: const EdgeInsets.all(18),
        child: const Text(
          'No patient selected.',
          style: TextStyle(fontSize: 14, color: _kTextSecondary),
        ),
      );
    }

    if (_isLoadingDetail) {
      return _panelShell(
        child: const SizedBox(
          height: 220,
          child: Center(
            child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2),
          ),
        ),
      );
    }

    if (_detailError != null) {
      return _panelShell(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _detailError!,
              style: const TextStyle(fontSize: 13, color: _kTextSecondary),
            ),
            const SizedBox(height: 12),
            _outlinedAction(
              label: 'Reload',
              onTap: () {
                final item = _selectedListItem;
                if (item != null) _selectPatient(item);
              },
            ),
          ],
        ),
      );
    }

    final patientName =
        _selectedPatientDetail?.fullName ?? _selectedListItem?.fullName ?? '--';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    'Patient : $patientName',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _kTextPrimary,
                    ),
                  ),
                ),
              ),
              if (_isDoctor)
                _filledAction(
                  label: 'Assign Room',
                  onTap: _showAssignRoomDialog,
                ),
              const SizedBox(width: 12),
              _filledAction(
                label: 'View Exams',
                onTap: _showAssignedExamsModal,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (compact) ...[
            _buildStructuredAndPersonal(compact: true),
            const SizedBox(height: 14),
            _buildBottomRow(compact: true),
          ] else ...[
            _buildStructuredAndPersonal(compact: false),
            const SizedBox(height: 14),
            _buildBottomRow(compact: false),
          ],
        ],
      ),
    );
  }

  void _goToAllPatients() {
    Navigator.pushReplacementNamed(context, '/all-patients');
  }

  void _goToRooms() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) {
          return RoomsPage(
            userRole: _normalizedUserRole,
            userName: widget.userName,
            userSpecialty: widget.userSpecialty,
          );
        },
      ),
    );
  }

  Widget _buildStructuredAndPersonal({required bool compact}) {
    if (compact) {
      return Column(
        children: [
          _structuredInfoCard(),
          const SizedBox(height: 14),
          _personalInfoCard(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _structuredInfoCard()),
        const SizedBox(width: 14),
        Expanded(child: _personalInfoCard()),
      ],
    );
  }

  Widget _buildBottomRow({required bool compact}) {
    if (compact) {
      return Column(
        children: [
          _visualizationCard(),
          const SizedBox(height: 14),
          _rawDataCard(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _visualizationCard()),
        const SizedBox(width: 14),
        Expanded(child: _rawDataCard()),
      ],
    );
  }

  Widget _structuredInfoCard() {
    final sessionStart = _parseDateTime(_selectedSessionDetail?.startTime);
    final chiefComplaint = (_patientBrief?.chiefComplaint?.isNotEmpty == true
            ? _patientBrief!.chiefComplaint
            : _selectedSessionDetail?.extractionData?['chief_complaint']
                    ?.toString() ??
                '--')
        .trim();
    final duration = (_patientBrief?.duration?.isNotEmpty == true
            ? _patientBrief!.duration!
            : _selectedSessionDetail?.extractionData?['duration']?.toString() ??
                '--')
        .trim();
    final suggestedIssue =
        (_patientBrief?.suspectedIssue ??
                _selectedSessionDetail?.prediction?['predicted_condition']
                    ?.toString() ??
                '--')
            .trim();

    final redFlagNote = (_patientBrief?.redFlagNote ?? '').trim();
    final redFlagsDetected =
        _selectedSessionDetail?.extractionData?['red_flags_present'] == true;
    final redFlagLines = <String>[];
    if (redFlagNote.isNotEmpty) redFlagLines.add(redFlagNote);
    if (redFlagsDetected && redFlagLines.isEmpty) {
      redFlagLines.add('Potential red flags detected in extraction data.');
    }

    final narrativeSummary = (_patientBrief?.narrativeSummary ?? '').trim();
    final keyFindings = _patientBrief?.keyFindings ?? [];
    final symptoms = _symptomItems();

    return _panelShell(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldRow(
            'Chief Complaint',
            chiefComplaint.isEmpty ? '--' : chiefComplaint,
          ),
          _fieldRow('Visitation Date', _formatDate(sessionStart)),
          _fieldRow('Visitation Time', _formatTime(sessionStart)),
          _fieldRow('Period', duration.isEmpty ? '--' : duration),
          const SizedBox(height: 10),
          _sectionTitle('Red Flag Notes'),
          if (redFlagLines.isEmpty)
            _bulletText('--')
          else
            ...redFlagLines.map(_bulletText),
          const SizedBox(height: 10),
          _sectionTitle('Symptom'),
          if (symptoms.isEmpty)
            _bulletText('--')
          else
            ...symptoms.take(5).map(_bulletText),
          const SizedBox(height: 10),
          _fieldRow(
            'Suggested Issues',
            suggestedIssue.isEmpty ? '--' : suggestedIssue,
          ),
          const SizedBox(height: 10),
          _sectionTitle('Narrative Notes'),
          if (narrativeSummary.isEmpty)
            _bulletText('--')
          else
            _bulletText(narrativeSummary),
          if (keyFindings.isNotEmpty) ...[
            const SizedBox(height: 6),
            _sectionTitle('Key Findings'),
            ...keyFindings.map(_bulletText),
          ],
        ],
      ),
    );
  }

  Widget _personalInfoCard() {
    final fullName = _selectedPatientDetail?.fullName ?? '--';
    final age = _resolvedAge != null ? '${_resolvedAge!} years old' : '--';
    final phone = (_selectedPatientDetail?.phoneNumber ?? '').trim();
    final language = (_selectedPatientDetail?.preferredLanguage ?? '').trim();
    final queueNumber = _selectedListItem?.queueNumber;
    final queueStatus = (_selectedListItem?.queueStatus ?? '').trim();
    final priority = (_selectedListItem?.priority ?? '').trim();

    return _panelShell(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldRow('Full Name', fullName),
          _fieldRow('Age', age),
          _fieldRow('Phone', phone.isEmpty ? '--' : phone),
          _fieldRow('Residency', _resolvedResidency),
          _fieldRow('Language', language.isEmpty ? '--' : language),
          _fieldRow(
            'Queue Number',
            queueNumber != null ? '#$queueNumber' : '--',
          ),
          _fieldRow(
            'Queue Status',
            queueStatus.isEmpty ? '--' : queueStatus,
          ),
          _fieldRow(
            'Priority',
            priority.isEmpty ? '--' : priority.toUpperCase(),
          ),
        ],
      ),
    );
  }

  Widget _visualizationCard() {
    final factors = _factorGraphData();
    final confidence = _confidenceGraphData();

    return _panelShell(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Risk Visualization',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Graph 1 of 2: factor contribution from available patient fields',
            style: TextStyle(fontSize: 11, color: _kTextMuted),
          ),
          const SizedBox(height: 6),
          _graphShell(child: _factorGraph(factors)),
          const SizedBox(height: 10),
          const Text(
            'Graph 2 of 2: confidence and severity breakdown',
            style: TextStyle(fontSize: 11, color: _kTextMuted),
          ),
          const SizedBox(height: 6),
          _graphShell(child: _confidenceGraph(confidence)),
        ],
      ),
    );
  }

  Widget _rawDataCard() {
    final audioRows =
        _selectedSessionDetail?.audioRecordings ??
        const <Map<String, dynamic>>[];
    final questions = _clarificationQuestions();
    final transcript = (_selectedSessionDetail?.fullTranscript ?? '').trim();

    return _panelShell(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionBox(
            title: 'Listen To Conversation Audio',
            child:
                audioRows.isEmpty
                    ? const Text(
                      '--',
                      style: TextStyle(fontSize: 12, color: _kTextMuted),
                    )
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                          audioRows.take(3).map((audio) {
                            final sequence =
                                audio['sequence_number']?.toString() ?? '--';
                            final path = (audio['file_path'] ?? '').toString();
                            final shortPath =
                                path.isEmpty
                                    ? '--'
                                    : path.length > 42
                                    ? '...${path.substring(path.length - 39)}'
                                    : path;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Clip $sequence: $shortPath',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _kTextSecondary,
                                ),
                              ),
                            );
                          }).toList(),
                    ),
          ),
          const SizedBox(height: 8),
          _sectionBox(
            title: 'Clarification Questions asked',
            child:
                questions.isEmpty
                    ? const Text(
                      'More..',
                      style: TextStyle(fontSize: 12, color: _kTextMuted),
                    )
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                          questions
                              .take(3)
                              .map((q) => _bulletText(q, compact: true))
                              .toList(),
                    ),
          ),
          const SizedBox(height: 8),
          _sectionBox(
            title: 'Raw Conversation Transcription',
            child: Text(
              transcript.isEmpty ? 'More..' : transcript,
              maxLines: transcript.isEmpty ? null : 9,
              overflow:
                  transcript.isEmpty
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: _kTextSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _factorGraph(List<_GraphDatum> data) {
    return Column(
      children:
          data.map((entry) {
            final percentage = (entry.value * 100).round();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      entry.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kTextSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        border: Border.all(color: _kBorderLight),
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: entry.value,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _kGreen,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$percentage%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11, color: _kTextMuted),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _confidenceGraph(List<_GraphDatum> data) {
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children:
            data.map((entry) {
              final h = (entry.value * 100).clamp(2.0, 100.0);
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${(entry.value * 100).round()}%',
                    style: const TextStyle(fontSize: 11, color: _kTextMuted),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Container(
                      width: 44,
                      height: h,
                      decoration: BoxDecoration(
                        color: entry.barColor ?? _kGreen,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        border: Border.all(color: _kBorder),
                      ),
                    ),
                  ),
                  Container(
                    width: 44,
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      entry.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _kTextSecondary,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
      ),
    );
  }

  Widget _graphShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }

  Widget _sectionBox({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _fieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: _kTextSecondary),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: _kTextPrimary,
              ),
            ),
            TextSpan(text: value.isEmpty ? '--' : value),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String label) {
    return Text(
      '$label:',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: _kTextPrimary,
      ),
    );
  }

  Widget _bulletText(String text, {bool compact = false}) {
    return Padding(
      padding: EdgeInsets.only(top: compact ? 3 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.circle, size: 5, color: _kTextSecondary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                color: _kTextSecondary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelShell({Widget? child, EdgeInsetsGeometry? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kBorder, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: padding,
      child: child,
    );
  }

  Widget _filledAction({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: _kGreen,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _outlinedAction({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _kBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _kTextPrimary,
          ),
        ),
      ),
    );
  }

  void _showAssignRoomDialog() {
    if (!_isDoctor) return;
    showDialog(
      context: context,
      builder: (context) {
        return AssignRoomDialog(
          onRoomAssigned: (roomId, exams) {
            _assignRoomToPatient(roomId, exams);
          },
        );
      },
    );
  }

  void _showAssignedExamsModal() {
    final sessionId =
        _selectedSessionDetail?.sessionId ?? _selectedListItem?.sessionId;
    final patientName =
        _selectedPatientDetail?.fullName ??
        _selectedListItem?.fullName ??
        'Patient';

    showDialog(
      context: context,
      builder: (context) {
        return AssignedExamsModal(
          sessionId: sessionId,
          patientName: patientName,
        );
      },
    );
  }

  Future<void> _assignRoomToPatient(int roomId, List<String> exams) async {
    if (!_isDoctor) return; // doctor-only

    final sessionId =
        _selectedSessionDetail?.sessionId ?? _selectedListItem?.sessionId;
    if (sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active session found for this patient.'),
        ),
      );
      return;
    }

    try {
      final response = await ApiService.assignRoomForSession(
        sessionId: sessionId,
        roomId: roomId,
        requiredExams: exams.isEmpty ? null : exams,
      );

      final assignedExams = _toStringList(response['required_exams']);
      final rawMessage =
          (response['message'] ?? 'Room assigned successfully')
              .toString()
              .trim();
      final snackMessage =
          assignedExams.isEmpty
              ? rawMessage
              : '$rawMessage\nExams: ${assignedExams.join(', ')}';

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(snackMessage)));

      if (_selectedListItem != null) {
        await _loadPatientData(_selectedListItem!);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to assign room: $e')));
    }
  }
}

class _GraphDatum {
  final String label;
  final double value;
  final Color? barColor;

  const _GraphDatum({required this.label, required this.value, this.barColor});
}

class PatientBrief {
  final String narrativeSummary;
  final List<String> keyFindings;
  final String redFlagNote;
  final String chiefComplaint;
  final String? bodyPart;
  final String? duration;
  final String? severity;
  final List<String> associatedSymptoms;
  final List<String> riskFactors;
  final String? suspectedIssue;
  final double? confidenceScore;
  final String priority;

  const PatientBrief({
    required this.narrativeSummary,
    required this.keyFindings,
    required this.redFlagNote,
    required this.chiefComplaint,
    this.bodyPart,
    this.duration,
    this.severity,
    required this.associatedSymptoms,
    required this.riskFactors,
    this.suspectedIssue,
    this.confidenceScore,
    required this.priority,
  });
}
