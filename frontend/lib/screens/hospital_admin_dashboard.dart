import 'package:flutter/material.dart';

import '../components/admin_ui.dart';
import '../components/app_navbar.dart';
import '../services/api_service.dart';
import 'patient_detail_page.dart';

// ── Colors ──────────────────────────────────────────────────────────────────
const Color _primaryGreen = Color(0xFF8B9E3A);
const Color _accentGold = Color(0xFFB8860B);

// ── Dashboard Root ───────────────────────────────────────────────────────────
class HospitalAdminDashboard extends StatefulWidget {
  final String userRole;
  final String userName;

  const HospitalAdminDashboard({
    Key? key,
    required this.userRole,
    required this.userName,
  }) : super(key: key);

  @override
  State<HospitalAdminDashboard> createState() => _HospitalAdminDashboardState();
}

class _HospitalAdminDashboardState extends State<HospitalAdminDashboard> {
  String _activeSection = 'Doctors';
  String _effectiveName = '';
  int? _facilityId;
  bool _profileLoaded = false;

  static const List<String> _sections = ['Doctors', 'Patients', 'Rooms'];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userInfo = await ApiService.getUserInfo();
    if (!mounted) return;
    setState(() {
      _effectiveName =
          (userInfo?['full_name'] as String? ?? widget.userName).trim();
      _facilityId = userInfo?['facility_id'] as int?;
      _profileLoaded = true;
    });
  }

  String get _displayName =>
      _effectiveName.trim().isEmpty ? widget.userName : _effectiveName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          _Sidebar(
            activeItem: _activeSection,
            onItemSelected: (item) => setState(() => _activeSection = item),
          ),
          Expanded(
            child: Column(
              children: [
                AppNavBar(
                  currentUserName: _displayName,
                  currentUserRole: widget.userRole,
                  navItems: const [],
                  activeItem: _activeSection,
                  onSettingsTap: () {},
                  onPatientTap:
                      (id) => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => PatientDetailPage(
                                userRole: widget.userRole,
                                userName: _displayName,
                                initialPatientId: id,
                              ),
                        ),
                      ),
                ),
                Expanded(
                  child:
                      !_profileLoaded
                          ? const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _primaryGreen,
                              ),
                            ),
                          )
                          : IndexedStack(
                            index: _sections.indexOf(_activeSection),
                            children: [
                              _DoctorsSection(facilityId: _facilityId),
                              _PatientsSection(
                                userRole: widget.userRole,
                                userName: _displayName,
                              ),
                              _RoomsSection(facilityId: _facilityId),
                            ],
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar ──────────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final String activeItem;
  final ValueChanged<String>? onItemSelected;

  const _Sidebar({required this.activeItem, this.onItemSelected});

  static const Color _activeGreen = Color(0xFF8B9E3A);

  static const List<({String label, IconData icon})> _items = [
    (label: 'Doctors', icon: Icons.medical_services_outlined),
    (label: 'Patients', icon: Icons.people_outlined),
    (label: 'Rooms', icon: Icons.meeting_room_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(
            color: const Color.fromARGB(255, 129, 129, 129),
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 36, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade100, width: 1),
                ),
              ),
              child: const Text(
                'Hospital Admin',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._items.map((item) {
                      final isActive = item.label == activeItem;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: isActive ? _activeGreen : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onItemSelected?.call(item.label),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.icon,
                                    size: 20,
                                    color:
                                        isActive
                                            ? Colors.black
                                            : Colors.black54,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    item.label,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight:
                                          isActive
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                      color:
                                          isActive
                                              ? Colors.black
                                              : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widget helpers ────────────────────────────────────────────────────
class _HeaderCell extends StatelessWidget {
  final String label;
  const _HeaderCell(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AdminUi.primaryText,
        ),
      ),
    );
  }
}

Widget _dataCell(
  String text, {
  TextAlign align = TextAlign.start,
  FontWeight fontWeight = FontWeight.w500,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    child: Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: 13,
        color: AdminUi.primaryText,
        fontWeight: fontWeight,
      ),
    ),
  );
}

// Returns true if `date` falls within [from, to] (inclusive, date-only).
bool _inDateRange(DateTime? date, DateTime? from, DateTime? to) {
  if (from == null && to == null) return true;
  if (date == null) return false;
  final d = DateTime(date.year, date.month, date.day);
  if (from != null && d.isBefore(DateTime(from.year, from.month, from.day))) {
    return false;
  }
  if (to != null && d.isAfter(DateTime(to.year, to.month, to.day))) {
    return false;
  }
  return true;
}

String _fmtDate(DateTime? dt) {
  if (dt == null) return '—';
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
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

Widget _loadingBox() => Container(
  width: double.infinity,
  padding: const EdgeInsets.symmetric(vertical: 70),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
  ),
  child: const Center(
    child: CircularProgressIndicator(
      valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
    ),
  ),
);

Widget _errorBox(String message, VoidCallback onRetry) => Container(
  width: double.infinity,
  padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
  ),
  child: Column(
    children: [
      const Icon(Icons.error_outline, size: 42, color: _accentGold),
      const SizedBox(height: 12),
      Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, color: Colors.black),
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: onRetry,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryGreen,
          foregroundColor: Colors.black,
        ),
        child: const Text('Retry'),
      ),
    ],
  ),
);

InputDecoration _fieldDeco(String label) => InputDecoration(
  labelText: label,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: _primaryGreen),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: _primaryGreen, width: 1.4),
  ),
  fillColor: Colors.white,
  filled: true,
  labelStyle: const TextStyle(color: Colors.black),
);

String? _required(String? v) =>
    (v == null || v.trim().isEmpty) ? 'This field is required.' : null;

Widget _formField(
  TextEditingController ctrl,
  String label, {
  TextInputType? keyboardType,
  bool obscureText = false,
  String? Function(String?)? validator,
  Widget? suffixIcon,
}) => TextFormField(
  controller: ctrl,
  keyboardType: keyboardType,
  obscureText: obscureText,
  validator: validator,
  decoration: _fieldDeco(label).copyWith(suffixIcon: suffixIcon),
);

Widget _submitLoader() => const SizedBox(
  width: 16,
  height: 16,
  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
);

// ── Doctors Section ──────────────────────────────────────────────────────────
class _DoctorsSection extends StatefulWidget {
  final int? facilityId;

  const _DoctorsSection({required this.facilityId});

  @override
  State<_DoctorsSection> createState() => _DoctorsSectionState();
}

class _DoctorsSectionState extends State<_DoctorsSection>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchCtrl = TextEditingController();

  List<DoctorItem> _doctors = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  String _search = '';
  String _statusFilter = 'All';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const List<String> _statusOptions = ['All', 'Active', 'Inactive'];

  bool get _hasDateData => _doctors.any((d) => d.createdAt != null);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetch(showLoader: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool showLoader}) async {
    setState(() {
      if (showLoader) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
      _error = null;
    });
    try {
      final doctors = await ApiService.getDoctors();
      if (!mounted) return;
      setState(() => _doctors = doctors);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Failed to load doctors. Check connectivity.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  List<DoctorItem> get _filtered =>
      _doctors.where((d) {
        if (_statusFilter == 'Active' && !d.isActive) return false;
        if (_statusFilter == 'Inactive' && d.isActive) return false;
        if (!_inDateRange(d.createdAt, _dateFrom, _dateTo)) return false;
        if (_search.trim().isNotEmpty) {
          final q = _search.trim().toLowerCase();
          if (!d.fullName.toLowerCase().contains(q) &&
              !d.email.toLowerCase().contains(q) &&
              !(d.specialty ?? '').toLowerCase().contains(q)) {
            return false;
          }
        }
        return true;
      }).toList();

  Future<void> _showAddDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final specialtyCtrl = TextEditingController();
    bool submitting = false;
    bool obscure = true;
    String? modalError;

    await showDialog<void>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModal) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: const Text(
                    'Add Doctor',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  content: SizedBox(
                    width: 520,
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (modalError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                modalError!,
                                style: const TextStyle(color: _accentGold),
                              ),
                            ),
                          _formField(
                            nameCtrl,
                            'Full Name',
                            validator: _required,
                          ),
                          const SizedBox(height: 10),
                          _formField(
                            emailCtrl,
                            'Email',
                            keyboardType: TextInputType.emailAddress,
                            validator: _required,
                          ),
                          const SizedBox(height: 10),
                          _formField(
                            passCtrl,
                            'Password',
                            obscureText: obscure,
                            validator: _required,
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                              onPressed:
                                  () => setModal(() => obscure = !obscure),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _formField(specialtyCtrl, 'Specialty (optional)'),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          submitting ? null : () => Navigator.of(ctx).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: _primaryGreen,
                      ),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed:
                          submitting
                              ? null
                              : () async {
                                if (!formKey.currentState!.validate()) return;
                                final messenger = ScaffoldMessenger.of(context);
                                setModal(() {
                                  submitting = true;
                                  modalError = null;
                                });
                                try {
                                  await ApiService.registerDoctor(
                                    email: emailCtrl.text.trim(),
                                    password: passCtrl.text,
                                    fullName: nameCtrl.text.trim(),
                                    specialty:
                                        specialtyCtrl.text.trim().isEmpty
                                            ? null
                                            : specialtyCtrl.text.trim(),
                                    facilityId: widget.facilityId,
                                  );
                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  _fetch(showLoader: false);
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Doctor added successfully.',
                                      ),
                                      backgroundColor: _primaryGreen,
                                    ),
                                  );
                                } catch (e) {
                                  setModal(() {
                                    submitting = false;
                                    modalError = e.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    );
                                  });
                                }
                              },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.black,
                      ),
                      child:
                          submitting
                              ? _submitLoader()
                              : const Text('Add Doctor'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _showEditDialog(DoctorItem doctor) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: doctor.fullName);
    final specialtyCtrl = TextEditingController(text: doctor.specialty ?? '');
    bool submitting = false;
    String? modalError;

    await showDialog<void>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModal) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: const Text(
                    'Edit Doctor',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  content: SizedBox(
                    width: 520,
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (modalError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                modalError!,
                                style: const TextStyle(color: _accentGold),
                              ),
                            ),
                          _formField(
                            nameCtrl,
                            'Full Name',
                            validator: _required,
                          ),
                          const SizedBox(height: 10),
                          _formField(specialtyCtrl, 'Specialty (optional)'),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          submitting ? null : () => Navigator.of(ctx).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: _primaryGreen,
                      ),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed:
                          submitting
                              ? null
                              : () async {
                                if (!formKey.currentState!.validate()) return;
                                final messenger = ScaffoldMessenger.of(context);
                                setModal(() {
                                  submitting = true;
                                  modalError = null;
                                });
                                try {
                                  final updates = <String, dynamic>{
                                    'full_name': nameCtrl.text.trim(),
                                  };
                                  if (specialtyCtrl.text.trim().isNotEmpty) {
                                    updates['specialty'] =
                                        specialtyCtrl.text.trim();
                                  }
                                  await ApiService.updateDoctor(
                                    doctor.userId,
                                    updates,
                                  );
                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  _fetch(showLoader: false);
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Doctor updated.'),
                                      backgroundColor: _primaryGreen,
                                    ),
                                  );
                                } catch (e) {
                                  setModal(() {
                                    submitting = false;
                                    modalError = e.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    );
                                  });
                                }
                              },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.black,
                      ),
                      child: submitting ? _submitLoader() : const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _toggleStatus(DoctorItem doctor) async {
    try {
      if (doctor.isActive) {
        await ApiService.deactivateDoctor(doctor.userId);
      } else {
        await ApiService.activateDoctor(doctor.userId);
      }
      if (!mounted) return;
      _fetch(showLoader: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            doctor.isActive ? 'Doctor deactivated.' : 'Doctor activated.',
          ),
          backgroundColor: _primaryGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: _accentGold,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final doctors = _filtered;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Doctors',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Manage doctors in your facility.',
                      style: TextStyle(fontSize: 14, color: Colors.black),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _fetch(showLoader: false),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryGreen,
                  side: const BorderSide(color: _primaryGreen),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Add Doctor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: AdminSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search by name, email, or specialty...',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AdminDropdownFilter(
                  value: _statusFilter,
                  items: _statusOptions,
                  icon: Icons.filter_alt_outlined,
                  selectedLabelBuilder:
                      (v) => v == 'All' ? 'Filter' : 'Filter $v',
                  onChanged: (v) {
                    if (v != null) setState(() => _statusFilter = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: AdminDateRangeFilter(
                  fromDate: _dateFrom,
                  toDate: _dateTo,
                  enabled: _hasDateData,
                  unavailableLabel: 'Date added unavailable',
                  onFromDateChanged: (d) => setState(() => _dateFrom = d),
                  onToDateChanged: (d) => setState(() => _dateTo = d),
                ),
              ),
            ],
          ),
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: _primaryGreen,
              ),
            ),
          const SizedBox(height: 20),
          if (_isLoading)
            _loadingBox()
          else if (_error != null)
            _errorBox(_error!, () => _fetch(showLoader: true))
          else
            _buildTable(doctors),
        ],
      ),
    );
  }

  Widget _buildTable(List<DoctorItem> doctors) {
    return AdminTableShell(
      minWidth: 1300,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.0),
          1: FlexColumnWidth(2.4),
          2: FlexColumnWidth(1.6),
          3: FlexColumnWidth(1.2),
          4: FlexColumnWidth(1.6),
          5: FlexColumnWidth(2.0),
        },
        border: TableBorder(
          horizontalInside: BorderSide(
            color: AdminUi.chrome.withAlpha(40),
            width: 1,
          ),
          verticalInside: BorderSide(
            color: AdminUi.chrome.withAlpha(24),
            width: 1,
          ),
        ),
        children: [
          const TableRow(
            decoration: BoxDecoration(color: AdminUi.tableHeader),
            children: [
              _HeaderCell('Doctor'),
              _HeaderCell('Email'),
              _HeaderCell('Specialty'),
              _HeaderCell('Status'),
              _HeaderCell('Added On'),
              _HeaderCell('Actions'),
            ],
          ),
          ...doctors.map(
            (d) => TableRow(
              children: [
                _dataCell(d.fullName, fontWeight: FontWeight.w600),
                _dataCell(d.email),
                _dataCell(
                  (d.specialty ?? '').trim().isEmpty
                      ? '—'
                      : d.specialty!.trim(),
                ),
                _statusBadge(d.isActive),
                _dataCell(_fmtDate(d.createdAt)),
                _actions(d),
              ],
            ),
          ),
          if (doctors.isEmpty)
            TableRow(
              children: List.generate(
                6,
                (i) =>
                    i == 2
                        ? _dataCell(
                          'No doctors found for the current filters.',
                          align: TextAlign.center,
                        )
                        : _dataCell(''),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(bool isActive) {
    final color = isActive ? _primaryGreen : _accentGold;
    final label = isActive ? 'Active' : 'Inactive';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(12),
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
    );
  }

  Widget _actions(DoctorItem doctor) {
    final toggleColor = doctor.isActive ? AdminUi.deleteAction : _primaryGreen;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          AdminActionIconButton(
            tooltip: 'Edit',
            icon: Icons.edit_outlined,
            backgroundColor: AdminUi.editAction,
            onTap: () => _showEditDialog(doctor),
          ),
          TextButton(
            onPressed: () => _toggleStatus(doctor),
            style: TextButton.styleFrom(
              foregroundColor: toggleColor,
              backgroundColor: toggleColor.withAlpha(18),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: toggleColor.withAlpha(120)),
              ),
            ),
            child: Text(doctor.isActive ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );
  }
}

// ── Patients Section ─────────────────────────────────────────────────────────
class _PatientsSection extends StatefulWidget {
  final String userRole;
  final String userName;

  const _PatientsSection({required this.userRole, required this.userName});

  @override
  State<_PatientsSection> createState() => _PatientsSectionState();
}

class _PatientsSectionState extends State<_PatientsSection>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchCtrl = TextEditingController();

  List<PatientListItem> _patients = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  String _search = '';
  String _priorityFilter = 'All';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const List<String> _priorityOptions = ['All', 'high', 'medium', 'low'];

  bool get _hasDateData => _patients.any((p) => p.startTime != null);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetch(showLoader: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool showLoader}) async {
    setState(() {
      if (showLoader) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
      _error = null;
    });
    try {
      final patients = await ApiService.getPatients();
      if (!mounted) return;
      setState(() => _patients = patients);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Failed to load patients. Check connectivity.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  List<PatientListItem> get _filtered =>
      _patients.where((p) {
        if (_priorityFilter != 'All' &&
            (p.priority ?? '').toLowerCase() != _priorityFilter) {
          return false;
        }
        if (!_inDateRange(
          DateTime.tryParse(p.startTime ?? ''),
          _dateFrom,
          _dateTo,
        )) {
          return false;
        }
        if (_search.trim().isNotEmpty) {
          final q = _search.trim().toLowerCase();
          if (!p.fullName.toLowerCase().contains(q) &&
              !(p.phoneNumber ?? '').toLowerCase().contains(q)) {
            return false;
          }
        }
        return true;
      }).toList();

  String _priorityLabel(String v) {
    if (v == 'All') return 'All Priorities';
    return v[0].toUpperCase() + v.substring(1);
  }

  String _formatDate(String? raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const m = [
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
      return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  String _formatQueueStatus(String? s) {
    if (s == null || s.trim().isEmpty) return '—';
    final clean = s.trim().toLowerCase().replaceAll('_', ' ');
    return clean[0].toUpperCase() + clean.substring(1);
  }

  void _openPatient(PatientListItem patient) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => PatientDetailPage(
              userRole: widget.userRole,
              userName: widget.userName,
              initialPatientId: patient.patientId,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final patients = _filtered;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patients',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'View all patients and their consultation records.',
                      style: TextStyle(fontSize: 14, color: Colors.black),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _fetch(showLoader: false),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryGreen,
                  side: const BorderSide(color: _primaryGreen),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: AdminSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search by patient name or phone...',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AdminDropdownFilter(
                  value: _priorityFilter,
                  items: _priorityOptions,
                  icon: Icons.flag_outlined,
                  itemLabel: _priorityLabel,
                  selectedLabelBuilder: _priorityLabel,
                  onChanged: (v) {
                    if (v != null) setState(() => _priorityFilter = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: AdminDateRangeFilter(
                  fromDate: _dateFrom,
                  toDate: _dateTo,
                  enabled: _hasDateData,
                  unavailableLabel: 'Session date unavailable',
                  onFromDateChanged: (d) => setState(() => _dateFrom = d),
                  onToDateChanged: (d) => setState(() => _dateTo = d),
                ),
              ),
            ],
          ),
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: _primaryGreen,
              ),
            ),
          const SizedBox(height: 20),
          if (_isLoading)
            _loadingBox()
          else if (_error != null)
            _errorBox(_error!, () => _fetch(showLoader: true))
          else
            _buildTable(patients),
        ],
      ),
    );
  }

  Widget _buildTable(List<PatientListItem> patients) {
    return AdminTableShell(
      minWidth: 1160,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.2),
          1: FlexColumnWidth(1.6),
          2: FlexColumnWidth(0.7),
          3: FlexColumnWidth(1.2),
          4: FlexColumnWidth(1.6),
          5: FlexColumnWidth(1.6),
          6: FlexColumnWidth(1.1),
        },
        border: TableBorder(
          horizontalInside: BorderSide(
            color: AdminUi.chrome.withAlpha(40),
            width: 1,
          ),
          verticalInside: BorderSide(
            color: AdminUi.chrome.withAlpha(24),
            width: 1,
          ),
        ),
        children: [
          const TableRow(
            decoration: BoxDecoration(color: AdminUi.tableHeader),
            children: [
              _HeaderCell('Patient'),
              _HeaderCell('Phone'),
              _HeaderCell('Age'),
              _HeaderCell('Priority'),
              _HeaderCell('Queue Status'),
              _HeaderCell('Session Date'),
              _HeaderCell('Record'),
            ],
          ),
          ...patients.map(
            (p) => TableRow(
              children: [
                _dataCell(p.fullName, fontWeight: FontWeight.w600),
                _dataCell(p.phoneNumber ?? '—'),
                _dataCell(p.age?.toString() ?? '—'),
                _priorityBadge(p.priority),
                _dataCell(_formatQueueStatus(p.queueStatus)),
                _dataCell(_formatDate(p.startTime)),
                _viewCell(() => _openPatient(p)),
              ],
            ),
          ),
          if (patients.isEmpty)
            TableRow(
              children: List.generate(
                7,
                (i) =>
                    i == 3
                        ? _dataCell(
                          'No patients found for the current filters.',
                          align: TextAlign.center,
                        )
                        : _dataCell(''),
              ),
            ),
        ],
      ),
    );
  }

  Widget _priorityBadge(String? priority) {
    final p = (priority ?? '').toLowerCase();
    final Color color;
    final String label;
    switch (p) {
      case 'high':
        color = const Color(0xFFB91C1C);
        label = 'High';
      case 'medium':
        color = _accentGold;
        label = 'Medium';
      case 'low':
        color = _primaryGreen;
        label = 'Low';
      default:
        color = AdminUi.mutedText;
        label = '—';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(12),
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
    );
  }

  Widget _viewCell(VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AdminUi.viewAction.withAlpha(18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AdminUi.viewAction.withAlpha(60)),
          ),
          child: const Text(
            'View',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AdminUi.viewAction,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Rooms Section ────────────────────────────────────────────────────────────
class _RoomsSection extends StatefulWidget {
  final int? facilityId;

  const _RoomsSection({required this.facilityId});

  @override
  State<_RoomsSection> createState() => _RoomsSectionState();
}

class _RoomsSectionState extends State<_RoomsSection>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchCtrl = TextEditingController();

  List<RoomResponse> _rooms = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  String _search = '';
  String _statusFilter = 'All';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const List<String> _statusOptions = [
    'All',
    'active',
    'inactive',
    'maintenance',
  ];

  bool get _hasDateData => _rooms.any((r) => r.createdAt != null);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetch(showLoader: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool showLoader}) async {
    setState(() {
      if (showLoader) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
      _error = null;
    });
    try {
      final rooms = await ApiService.getRooms();
      if (!mounted) return;
      setState(() => _rooms = rooms);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Failed to load rooms. Check connectivity.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  List<RoomResponse> get _filtered =>
      _rooms.where((r) {
        if (_statusFilter != 'All' && r.status.toLowerCase() != _statusFilter) {
          return false;
        }
        if (!_inDateRange(r.createdAt, _dateFrom, _dateTo)) {
          return false;
        }
        if (_search.trim().isNotEmpty) {
          final q = _search.trim().toLowerCase();
          if (!r.roomName.toLowerCase().contains(q) &&
              !r.roomType.toLowerCase().contains(q)) {
            return false;
          }
        }
        return true;
      }).toList();

  String _label(String v) {
    if (v.trim().isEmpty) return 'Unknown';
    final s = v.trim().toLowerCase();
    return s[0].toUpperCase() + s.substring(1);
  }

  Future<void> _showAddDialog() async {
    if (widget.facilityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No facility assigned to your account.'),
          backgroundColor: _accentGold,
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final floorCtrl = TextEditingController();
    final capacityCtrl = TextEditingController(text: '1');
    bool submitting = false;
    String? modalError;

    await showDialog<void>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModal) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: const Text(
                    'Add Room',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  content: SizedBox(
                    width: 520,
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (modalError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                modalError!,
                                style: const TextStyle(color: _accentGold),
                              ),
                            ),
                          _formField(
                            nameCtrl,
                            'Room Name',
                            validator: _required,
                          ),
                          const SizedBox(height: 10),
                          _formField(
                            typeCtrl,
                            'Room Type',
                            validator: _required,
                          ),
                          const SizedBox(height: 10),
                          _formField(
                            floorCtrl,
                            'Floor (optional)',
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 10),
                          _formField(
                            capacityCtrl,
                            'Capacity',
                            keyboardType: TextInputType.number,
                            validator: _required,
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          submitting ? null : () => Navigator.of(ctx).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: _primaryGreen,
                      ),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed:
                          submitting
                              ? null
                              : () async {
                                if (!formKey.currentState!.validate()) return;
                                final messenger = ScaffoldMessenger.of(context);
                                setModal(() {
                                  submitting = true;
                                  modalError = null;
                                });
                                try {
                                  final floor =
                                      floorCtrl.text.trim().isEmpty
                                          ? null
                                          : int.tryParse(floorCtrl.text.trim());
                                  final capacity =
                                      int.tryParse(capacityCtrl.text.trim()) ??
                                      1;
                                  final msg =
                                      await ApiService.requestRoomCreate(
                                        facilityId: widget.facilityId!,
                                        roomName: nameCtrl.text.trim(),
                                        roomType: typeCtrl.text.trim(),
                                        floorNumber: floor,
                                        capacity: capacity,
                                      );
                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  _fetch(showLoader: false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(msg),
                                      backgroundColor: _primaryGreen,
                                    ),
                                  );
                                } catch (e) {
                                  setModal(() {
                                    submitting = false;
                                    modalError = e.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    );
                                  });
                                }
                              },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.black,
                      ),
                      child:
                          submitting ? _submitLoader() : const Text('Submit'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _showEditDialog(RoomResponse room) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: room.roomName);
    final typeCtrl = TextEditingController(text: room.roomType);
    final floorCtrl = TextEditingController(
      text: room.floorNumber?.toString() ?? '',
    );
    final capacityCtrl = TextEditingController(text: room.capacity.toString());
    bool submitting = false;
    String? modalError;

    await showDialog<void>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModal) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: const Text(
                    'Edit Room',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  content: SizedBox(
                    width: 520,
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (modalError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                modalError!,
                                style: const TextStyle(color: _accentGold),
                              ),
                            ),
                          _formField(
                            nameCtrl,
                            'Room Name',
                            validator: _required,
                          ),
                          const SizedBox(height: 10),
                          _formField(
                            typeCtrl,
                            'Room Type',
                            validator: _required,
                          ),
                          const SizedBox(height: 10),
                          _formField(
                            floorCtrl,
                            'Floor (optional)',
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 10),
                          _formField(
                            capacityCtrl,
                            'Capacity',
                            keyboardType: TextInputType.number,
                            validator: _required,
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          submitting ? null : () => Navigator.of(ctx).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: _primaryGreen,
                      ),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed:
                          submitting
                              ? null
                              : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModal(() {
                                  submitting = true;
                                  modalError = null;
                                });
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  final updates = <String, dynamic>{
                                    'room_name': nameCtrl.text.trim(),
                                    'room_type': typeCtrl.text.trim(),
                                    'capacity':
                                        int.tryParse(
                                          capacityCtrl.text.trim(),
                                        ) ??
                                        1,
                                    'floor_number':
                                        floorCtrl.text.trim().isEmpty
                                            ? null
                                            : int.tryParse(
                                              floorCtrl.text.trim(),
                                            ),
                                  };
                                  final msg =
                                      await ApiService.requestRoomUpdate(
                                        room.roomId,
                                        updates,
                                      );
                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  _fetch(showLoader: false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(msg),
                                      backgroundColor: _primaryGreen,
                                    ),
                                  );
                                } catch (e) {
                                  setModal(() {
                                    submitting = false;
                                    modalError = e.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    );
                                  });
                                }
                              },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.black,
                      ),
                      child: submitting ? _submitLoader() : const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _toggleStatus(RoomResponse room) async {
    final target =
        room.status.toLowerCase() == 'active' ? 'inactive' : 'active';
    try {
      await ApiService.updateRoomStatus(roomId: room.roomId, status: target);
      if (!mounted) return;
      _fetch(showLoader: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Room marked ${_label(target)}.'),
          backgroundColor: _primaryGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: _accentGold,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rooms = _filtered;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rooms',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Manage rooms in your facility.',
                      style: TextStyle(fontSize: 14, color: Colors.black),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _fetch(showLoader: false),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryGreen,
                  side: const BorderSide(color: _primaryGreen),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Room'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: AdminSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search by room name or type...',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AdminDropdownFilter(
                  value: _statusFilter,
                  items: _statusOptions,
                  icon: Icons.filter_alt_outlined,
                  itemLabel: (v) => v == 'All' ? 'All' : _label(v),
                  selectedLabelBuilder:
                      (v) => v == 'All' ? 'Filter' : 'Filter ${_label(v)}',
                  onChanged: (v) {
                    if (v != null) setState(() => _statusFilter = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: AdminDateRangeFilter(
                  fromDate: _dateFrom,
                  toDate: _dateTo,
                  enabled: _hasDateData,
                  unavailableLabel: 'Date added unavailable',
                  onFromDateChanged: (d) => setState(() => _dateFrom = d),
                  onToDateChanged: (d) => setState(() => _dateTo = d),
                ),
              ),
            ],
          ),
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: _primaryGreen,
              ),
            ),
          const SizedBox(height: 20),
          if (_isLoading)
            _loadingBox()
          else if (_error != null)
            _errorBox(_error!, () => _fetch(showLoader: true))
          else
            _buildTable(rooms),
        ],
      ),
    );
  }

  Widget _buildTable(List<RoomResponse> rooms) {
    return AdminTableShell(
      minWidth: 1260,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.0),
          1: FlexColumnWidth(1.4),
          2: FlexColumnWidth(0.7),
          3: FlexColumnWidth(0.8),
          4: FlexColumnWidth(1.1),
          5: FlexColumnWidth(1.5),
          6: FlexColumnWidth(2.2),
        },
        border: TableBorder(
          horizontalInside: BorderSide(
            color: AdminUi.chrome.withAlpha(40),
            width: 1,
          ),
          verticalInside: BorderSide(
            color: AdminUi.chrome.withAlpha(24),
            width: 1,
          ),
        ),
        children: [
          const TableRow(
            decoration: BoxDecoration(color: AdminUi.tableHeader),
            children: [
              _HeaderCell('Room'),
              _HeaderCell('Type'),
              _HeaderCell('Floor'),
              _HeaderCell('Capacity'),
              _HeaderCell('Status'),
              _HeaderCell('Added On'),
              _HeaderCell('Actions'),
            ],
          ),
          ...rooms.map(
            (r) => TableRow(
              children: [
                _dataCell(r.roomName, fontWeight: FontWeight.w600),
                _dataCell(r.roomType),
                _dataCell(r.floorNumber?.toString() ?? '—'),
                _dataCell(r.capacity.toString()),
                _statusBadge(r.status),
                _dataCell(_fmtDate(r.createdAt)),
                _roomActions(r),
              ],
            ),
          ),
          if (rooms.isEmpty)
            TableRow(
              children: List.generate(
                7,
                (i) =>
                    i == 2
                        ? _dataCell(
                          'No rooms found for the current filters.',
                          align: TextAlign.center,
                        )
                        : _dataCell(''),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final isActive = status.toLowerCase() == 'active';
    final color = isActive ? _primaryGreen : _accentGold;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _label(status),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _roomActions(RoomResponse room) {
    final isActive = room.status.toLowerCase() == 'active';
    final toggleColor = isActive ? _accentGold : _primaryGreen;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          AdminActionIconButton(
            tooltip: 'Edit',
            icon: Icons.edit_outlined,
            backgroundColor: AdminUi.editAction,
            onTap: () => _showEditDialog(room),
          ),
          TextButton(
            onPressed: () => _toggleStatus(room),
            style: TextButton.styleFrom(
              foregroundColor: toggleColor,
              backgroundColor: toggleColor.withAlpha(18),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: toggleColor.withAlpha(120)),
              ),
            ),
            child: Text(isActive ? 'Set Inactive' : 'Set Active'),
          ),
        ],
      ),
    );
  }
}
