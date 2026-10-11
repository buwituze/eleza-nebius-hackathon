import 'package:flutter/material.dart';

import '../components/admin_sidebar.dart';
import '../components/admin_ui.dart';
import '../components/app_navbar.dart';
import '../services/api_service.dart';
import 'patient_detail_page.dart';
import 'rooms_page.dart';

class AllDoctorsPage extends StatefulWidget {
  final String userRole;
  final String userName;

  const AllDoctorsPage({
    Key? key,
    required this.userRole,
    required this.userName,
  }) : super(key: key);

  @override
  State<AllDoctorsPage> createState() => _AllDoctorsPageState();
}

class _AllDoctorsPageState extends State<AllDoctorsPage> {
  static const Color _primaryGreen = Color(0xFF8B9E3A);
  static const Color _accentGold = Color(0xFFB8860B);

  final TextEditingController _searchController = TextEditingController();

  List<DoctorItem> _allDoctors = [];
  Map<int, String> _facilityNames = {};

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  String _searchQuery = '';
  String _statusFilter = 'All';
  String _facilityFilter = 'All';

  static const List<String> _statusOptions = ['All', 'Active', 'Inactive'];

  @override
  void initState() {
    super.initState();
    _fetch(showLoader: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool showLoader}) async {
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

    try {
      final results = await Future.wait([
        ApiService.getDoctors(),
        ApiService.getFacilities(),
      ]);

      final doctors = results[0] as List<DoctorItem>;
      final facilities = results[1] as List<FacilityItem>;
      final facilityNames = <int, String>{
        for (final facility in facilities) facility.facilityId: facility.name,
      };

      if (!mounted) return;
      setState(() {
        _allDoctors = doctors;
        _facilityNames = facilityNames;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Failed to load doctors. Check connectivity and access permissions.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  String _facilityNameById(int? facilityId) {
    if (facilityId == null) return 'Unassigned';
    return _facilityNames[facilityId] ?? 'Facility #$facilityId';
  }

  List<String> get _facilityOptions {
    final values = _facilityNames.values.toSet().toList()..sort();
    return ['All', ...values];
  }

  List<DoctorItem> get _filtered {
    return _allDoctors.where((doctor) {
      if (_statusFilter == 'Active' && !doctor.isActive) return false;
      if (_statusFilter == 'Inactive' && doctor.isActive) return false;

      if (_facilityFilter != 'All') {
        final facilityName = _facilityNameById(doctor.facilityId);
        if (facilityName != _facilityFilter) return false;
      }

      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        final facilityName = _facilityNameById(doctor.facilityId).toLowerCase();
        final specialty = (doctor.specialty ?? '').toLowerCase();
        final matches =
            doctor.fullName.toLowerCase().contains(query) ||
            doctor.email.toLowerCase().contains(query) ||
            specialty.contains(query) ||
            facilityName.contains(query);
        if (!matches) return false;
      }

      return true;
    }).toList();
  }

  String _statusFilterLabel(String value) {
    return value == 'All' ? 'Filter' : 'Filter $value';
  }

  String _facilityFilterLabel(String value) {
    return value == 'All' ? 'Filter' : 'Filter $value';
  }

  void _onSidebarMenuSelected(String item) {
    if (item == 'Doctors') return;

    switch (item) {
      case 'Users':
        Navigator.of(context).pushReplacementNamed(
          '/admin-users',
          arguments: {'userRole': widget.userRole, 'userName': widget.userName},
        );
        break;
      case 'Facilities':
        Navigator.of(context).pushReplacementNamed(
          '/facilities',
          arguments: {'userRole': widget.userRole, 'userName': widget.userName},
        );
        break;
      case 'Rooms':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => RoomsPage(
                  userRole: widget.userRole,
                  userName: widget.userName,
                ),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final doctors = _filtered;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          AdminSidebar(
            activeItem: 'Doctors',
            onItemSelected: _onSidebarMenuSelected,
          ),
          Expanded(
            child: Column(
              children: [
                AppNavBar(
                  currentUserName: widget.userName,
                  currentUserRole: widget.userRole,
                  navItems: const [],
                  activeItem: 'Doctors',
                  onSettingsTap: () {},
                  onPatientTap:
                      (id) => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => PatientDetailPage(
                                userRole: widget.userRole,
                                userName: widget.userName,
                                initialPatientId: id,
                              ),
                        ),
                      ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 26,
                    ),
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
                                    'All doctors with their hospital assignment.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _isLoading
                                      ? null
                                      : () => _fetch(showLoader: false),
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
                        _filterBar(),
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
                          _loadingState()
                        else if (_errorMessage != null)
                          _errorState()
                        else
                          _table(doctors),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: AdminSearchField(
            controller: _searchController,
            hintText: 'Search doctors or hospitals...',
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _dropdownFilter(
            value: _statusFilter,
            icon: Icons.filter_alt_outlined,
            items: _statusOptions,
            selectedLabelBuilder: _statusFilterLabel,
            onChanged: (value) {
              if (value != null) setState(() => _statusFilter = value);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: _dropdownFilter(
            value: _facilityFilter,
            icon: Icons.local_hospital_outlined,
            items: _facilityOptions,
            selectedLabelBuilder: _facilityFilterLabel,
            onChanged: (value) {
              if (value != null) setState(() => _facilityFilter = value);
            },
          ),
        ),
      ],
    );
  }

  Widget _dropdownFilter({
    required String value,
    required IconData icon,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String Function(String item)? selectedLabelBuilder,
  }) {
    return AdminDropdownFilter(
      value: value,
      items: items,
      icon: icon,
      onChanged: onChanged,
      selectedLabelBuilder: selectedLabelBuilder,
    );
  }

  Widget _loadingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 70),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
        ),
      ),
    );
  }

  Widget _errorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 42, color: _accentGold),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _fetch(showLoader: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryGreen,
              foregroundColor: Colors.black,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Widget _table(List<DoctorItem> doctors) {
    return AdminTableShell(
      minWidth: 1260,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.2),
          1: FlexColumnWidth(2.4),
          2: FlexColumnWidth(1.8),
          3: FlexColumnWidth(2.4),
          4: FlexColumnWidth(1.5),
          5: FlexColumnWidth(1.2),
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
              _HeaderCell('Hospital'),
              _HeaderCell('Added On'),
              _HeaderCell('Status'),
            ],
          ),
          ...doctors.map(
            (doctor) => TableRow(
              children: [
                _dataCell(doctor.fullName, fontWeight: FontWeight.w600),
                _dataCell(doctor.email),
                _dataCell(
                  (doctor.specialty ?? '').trim().isEmpty
                      ? '—'
                      : doctor.specialty!.trim(),
                ),
                _dataCell(_facilityNameById(doctor.facilityId)),
                _dataCell(_fmtDate(doctor.createdAt)),
                _statusBadge(doctor.isActive),
              ],
            ),
          ),
          if (doctors.isEmpty)
            TableRow(
              children: List.generate(
                6,
                (index) =>
                    index == 2
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
}

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
