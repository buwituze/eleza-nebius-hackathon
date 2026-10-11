import 'package:flutter/material.dart';

import '../components/admin_ui.dart';
import '../components/app_navbar.dart';
import '../components/assign_room_dialog.dart';
import '../screens/patient_detail_page.dart';
import '../screens/rooms_page.dart';
import '../services/api_service.dart';

// ─── Design tokens ───────────────────────────────────────────────────────────
const _kBorder = Color(0xFF9CA3AF);
const _kBorderLight = Color(0xFFE5E7EB);
const _kHeaderBg = Color(0xFFF9FAFB);
const _kGreen = Color(0xFF8B9E3A);
const _kRed = Color(0xFFDC2626);
const _kAmber = Color(0xFFD97706);
const _kTextDark = Color(0xFF111827);
const _kTextMid = Color(0xFF374151);
const _kTextLight = Color(0xFF6B7280);

class AllPatientsPage extends StatefulWidget {
  const AllPatientsPage({super.key});

  @override
  State<AllPatientsPage> createState() => _AllPatientsPageState();
}

class _AllPatientsPageState extends State<AllPatientsPage> {
  final TextEditingController _searchController = TextEditingController();

  int _latestFetchRequestId = 0;
  List<PatientListItem> _allPatients = [];

  String _searchQuery = '';
  String _priorityFilter = 'All';
  DateTime? _sessionFrom;
  DateTime? _sessionTo;

  String _currentUserName = 'Clinician';
  String _currentUserRole = 'Doctor';
  String? _currentUserSpecialty;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  static const List<String> _priorityOptions = ['All', 'High', 'Medium', 'Low'];

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _fetchPatients(showLoader: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final user = await ApiService.getUserInfo();
    if (!mounted || user == null) return;
    setState(() {
      final name = user['full_name'];
      final role = user['role'];
      final spec = user['specialty'];
      if (name is String && name.trim().isNotEmpty) _currentUserName = name;
      if (role is String && role.trim().isNotEmpty) _currentUserRole = role;
      if (spec is String && spec.trim().isNotEmpty)
        _currentUserSpecialty = spec;
    });
  }

  Future<void> _fetchPatients({required bool showLoader}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    }

    final requestId = ++_latestFetchRequestId;

    try {
      final result = await ApiService.getPatients();
      if (!mounted || requestId != _latestFetchRequestId) return;
      // Sort patients by startTime descending (most recent first)
      result.sort((a, b) {
        final aTime = DateTime.tryParse(a.startTime ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b.startTime ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      setState(() => _allPatients = result);
    } catch (e) {
      if (!mounted || requestId != _latestFetchRequestId) return;
      setState(
        () =>
            _errorMessage =
                'Failed to load patients. Please verify server connectivity and login status.',
      );
      debugPrint('Failed to fetch patients: $e');
    } finally {
      if (!mounted || requestId != _latestFetchRequestId) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  List<PatientListItem> get _filteredPatients {
    return _allPatients.where((p) {
      if (_priorityFilter != 'All') {
        final prio = (p.priority ?? '').toLowerCase();
        if (_priorityFilter == 'High' && prio != 'high') return false;
        if (_priorityFilter == 'Medium' && prio != 'medium') return false;
        if (_priorityFilter == 'Low' && prio != 'low') return false;
      }
      if (!_matchesSessionDate(p.startTime)) return false;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final name = p.fullName.toLowerCase();
        final residency = (p.residency ?? '').toLowerCase();
        final phone = (p.phoneNumber ?? '').toLowerCase();
        final queueNo = p.queueNumber == null ? '' : '${p.queueNumber}';
        if (!name.contains(q) &&
            !residency.contains(q) &&
            !phone.contains(q) &&
            !queueNo.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _capitalize(String? text) {
    final v = (text ?? '').trim();
    if (v.isEmpty) return '—';
    return v[0].toUpperCase() + v.substring(1).toLowerCase();
  }

  Color _priorityColor(String? priority) {
    switch ((priority ?? '').toLowerCase()) {
      case 'high':
        return _kRed;
      case 'medium':
        return _kAmber;
      default:
        return _kGreen;
    }
  }

  bool get _hasSessionDateData =>
      _allPatients.any((patient) => _sessionDate(patient.startTime) != null);

  String _priorityFilterLabel(String value) {
    return value == 'All' ? 'Filter' : 'Filter $value';
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime? _sessionDate(String? rawDate) {
    if (rawDate == null || rawDate.trim().isEmpty) return null;
    return DateTime.tryParse(rawDate);
  }

  bool _matchesSessionDate(String? rawDate) {
    if (_sessionFrom == null && _sessionTo == null) return true;

    final parsedDate = _sessionDate(rawDate);
    if (parsedDate == null) return false;

    final sessionDate = _dateOnly(parsedDate);
    final fromDate = _sessionFrom == null ? null : _dateOnly(_sessionFrom!);
    final toDate = _sessionTo == null ? null : _dateOnly(_sessionTo!);

    if (fromDate != null && sessionDate.isBefore(fromDate)) return false;
    if (toDate != null && sessionDate.isAfter(toDate)) return false;
    return true;
  }

  void _setSessionFrom(DateTime? value) {
    setState(() {
      _sessionFrom = value;
      if (_sessionTo != null &&
          value != null &&
          _dateOnly(_sessionTo!).isBefore(_dateOnly(value))) {
        _sessionTo = value;
      }
    });
  }

  void _setSessionTo(DateTime? value) {
    setState(() {
      _sessionTo = value;
      if (_sessionFrom != null &&
          value != null &&
          _dateOnly(_sessionFrom!).isAfter(_dateOnly(value))) {
        _sessionFrom = value;
      }
    });
  }

  void _openPatientDetail(PatientListItem patient) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PatientDetailPage(
              userRole: _normalizedRole(_currentUserRole),
              userName: _currentUserName,
              userSpecialty: _currentUserSpecialty,
              initialPatientId: patient.patientId,
            ),
      ),
    );
  }

  void _onEditPatient(PatientListItem patient) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Patient editing is not yet available.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onAssignPatient(PatientListItem patient) {
    if (patient.sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active session found for this patient.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder:
          (_) => AssignRoomDialog(
            onRoomAssigned:
                (roomId, exams) => _doAssign(patient, roomId, exams),
          ),
    );
  }

  Future<void> _doAssign(
    PatientListItem patient,
    int roomId,
    List<String> exams,
  ) async {
    final sessionId = patient.sessionId;
    if (sessionId == null) return;
    try {
      final response = await ApiService.assignRoomForSession(
        sessionId: sessionId,
        roomId: roomId,
        requiredExams: exams.isEmpty ? null : exams,
      );
      if (!mounted) return;
      final msg = (response['message'] ?? 'Assigned successfully').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
      _fetchPatients(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Assignment failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  String _normalizedRole(String role) {
    final n = role.trim().toLowerCase().replaceAll(' ', '_');
    if (n == 'hospital_admin' || n == 'platform_admin' || n == 'doctor')
      return n;
    return 'doctor';
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final patients = _filteredPatients;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          AppNavBar(
            currentUserName: _currentUserName,
            currentUserRole: _currentUserRole,
            currentUserSpecialty: _currentUserSpecialty,
            onPatientTap: (id) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PatientDetailPage(
                  userRole: _normalizedRole(_currentUserRole),
                  userName: _currentUserName,
                  userSpecialty: _currentUserSpecialty,
                  initialPatientId: id,
                ),
              ),
            ),
            navItems: [
              NavBarItem(label: 'All Patients', onTap: () {}),
              NavBarItem(
                label: 'Rooms',
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) => RoomsPage(
                              userRole: _normalizedRole(_currentUserRole),
                              userName: _currentUserName,
                              userSpecialty: _currentUserSpecialty,
                            ),
                      ),
                    ),
              ),
            ],
            activeItem: 'All Patients',
            onSettingsTap: () {},
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Page title
                  const Text(
                    'All Patients',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'View and manage all patient records',
                    style: TextStyle(fontSize: 13, color: _kTextLight),
                  ),
                  const SizedBox(height: 24),

                  // Toolbar
                  _toolbar(),
                  if (_isRefreshing)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: _kGreen,
                        backgroundColor: Color(0xFFE5E7EB),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Table / states
                  if (_isLoading)
                    _loadingState()
                  else if (_errorMessage != null)
                    _errorState()
                  else
                    _table(patients),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────────────────────

  Widget _toolbar() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: AdminSearchField(
            controller: _searchController,
            hintText: 'Search by name, phone, residency, or queue #',
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: AdminDropdownFilter(
            value: _priorityFilter,
            items: _priorityOptions,
            icon: Icons.filter_alt_outlined,
            selectedLabelBuilder: _priorityFilterLabel,
            onChanged: (v) {
              if (v != null) setState(() => _priorityFilter = v);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: AdminDateRangeFilter(
            fromDate: _sessionFrom,
            toDate: _sessionTo,
            onFromDateChanged: _setSessionFrom,
            onToDateChanged: _setSessionTo,
            enabled: _hasSessionDateData,
            unavailableLabel:
                'Session date filter unavailable because the current patients API does not expose parseable start_time.',
          ),
        ),
        const SizedBox(width: 12),
        _outlineButton(
          label: 'Refresh',
          icon: Icons.refresh,
          onTap: _isLoading ? null : () => _fetchPatients(showLoader: false),
        ),
      ],
    );
  }

  Widget _outlineButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: _kTextMid),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: _kTextMid,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Table ─────────────────────────────────────────────────────────────────────

  Widget _table(List<PatientListItem> patients) {
    return AdminTableShell(
      minWidth: 1080,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.8),
          1: FlexColumnWidth(1.0),
          2: FlexColumnWidth(2.2),
          3: FlexColumnWidth(1.4),
          4: FlexColumnWidth(1.0),
          5: FlexColumnWidth(1.5),
          6: FlexColumnWidth(2.0),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: _kBorderLight, width: 1),
          verticalInside: BorderSide(color: _kBorderLight, width: 1),
        ),
        children: [
          // Header
          const TableRow(
            decoration: BoxDecoration(color: _kHeaderBg),
            children: [
              _HeaderCell('Patient Name'),
              _HeaderCell('Age'),
              _HeaderCell('Residency'),
              _HeaderCell('Priority'),
              _HeaderCell('Queue #'),
              _HeaderCell('Status'),
              _HeaderCell('Actions'),
            ],
          ),
          // Data rows
          ...patients.map(
            (p) => TableRow(
              decoration: const BoxDecoration(color: Colors.white),
              children: [
                _nameCell(p.fullName),
                _textCell(p.age != null ? '${p.age}' : '—'),
                _textCell(
                  (p.residency ?? '').trim().isEmpty ? '—' : p.residency!,
                ),
                _priorityCell(p.priority),
                _textCell(p.queueNumber != null ? '#${p.queueNumber}' : '—'),
                _queueStatusCell(p.queueStatus),
                _actionCell(p),
              ],
            ),
          ),
          // Empty state
          if (patients.isEmpty)
            TableRow(
              children: [
                _emptyCell(),
                const SizedBox.shrink(),
                const SizedBox.shrink(),
                const SizedBox.shrink(),
                const SizedBox.shrink(),
                const SizedBox.shrink(),
                const SizedBox.shrink(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _nameCell(String name) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        name,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _kTextDark,
        ),
      ),
    );
  }

  Widget _textCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(text, style: const TextStyle(fontSize: 13, color: _kTextMid)),
    );
  }

  Widget _priorityCell(String? priority) {
    final label = _capitalize(priority);
    final color = _priorityColor(priority);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(24),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _queueStatusCell(String? status) {
    if (status == null || status.isEmpty) {
      return _textCell('—');
    }
    final label = status.replaceAll('_', ' ');
    final label2 = label[0].toUpperCase() + label.substring(1).toLowerCase();
    final Color color;
    switch (status.toLowerCase()) {
      case 'in_progress':
        color = const Color(0xFF2563EB);
        break;
      case 'waiting':
        color = const Color(0xFFD97706);
        break;
      case 'completed':
        color = const Color(0xFF16A34A);
        break;
      case 'cancelled':
        color = const Color(0xFFDC2626);
        break;
      default:
        color = const Color(0xFF6B7280);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Text(
            label2,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionCell(PatientListItem patient) {
    final canAssign = patient.sessionId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: TextButton(
              onPressed: canAssign ? () => _onAssignPatient(patient) : null,
              style: TextButton.styleFrom(
                backgroundColor:
                    canAssign ? const Color(0xFF8B9E3A) : _kBorderLight,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                'Assign',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 2),
          _iconBtn(
            icon: Icons.visibility_outlined,
            tooltip: 'View patient',
            color: _kGreen,
            onTap: () => _openPatientDetail(patient),
          ),
          _iconBtn(
            icon: Icons.edit_outlined,
            tooltip: 'Edit patient',
            color: _kTextMid,
            onTap: () => _onEditPatient(patient),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _emptyCell() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Text(
        'No patients found.',
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[500],
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  // ── State widgets ─────────────────────────────────────────────────────────────

  Widget _loadingState() {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2),
      ),
    );
  }

  Widget _errorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 40, color: _kRed),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _kTextMid),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _fetchPatients(showLoader: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: _kGreen,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared header cell widget ─────────────────────────────────────────────────

class _HeaderCell extends StatelessWidget {
  final String label;
  const _HeaderCell(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _kTextMid,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
