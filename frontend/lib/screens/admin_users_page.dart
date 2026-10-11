import 'package:flutter/material.dart';

import '../components/admin_sidebar.dart';
import '../components/admin_ui.dart';
import '../components/app_navbar.dart';
import '../services/api_service.dart';
import 'patient_detail_page.dart';
import 'rooms_page.dart';

class AdminUsersPage extends StatefulWidget {
  final String userRole;
  final String userName;

  const AdminUsersPage({
    Key? key,
    required this.userRole,
    required this.userName,
  }) : super(key: key);

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  static const Color _primaryGreen = Color(0xFF8B9E3A);
  static const Color _dangerRed = Color(0xFFB91C1C);
  static const Color _accentGold = Color(0xFFB8860B);

  final TextEditingController _searchController = TextEditingController();

  List<SystemUserItem> _allUsers = [];
  List<FacilityItem> _facilities = [];

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _searchQuery = '';
  String _roleFilter = 'All';
  DateTime? _createdFrom;
  DateTime? _createdTo;

  final Map<int, bool> _localUserActiveOverrides = {};

  static const List<String> _roleOptions = [
    'All',
    'platform_admin',
    'hospital_admin',
    'doctor',
  ];

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
        ApiService.getAllUsers(),
        ApiService.getFacilities(),
      ]);

      if (!mounted) return;
      setState(() {
        _allUsers = results[0] as List<SystemUserItem>;
        _facilities = results[1] as List<FacilityItem>;
        _localUserActiveOverrides.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Failed to load users. Make sure you are logged in as a platform admin.';
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
    if (facilityId == null) return '-';
    for (final f in _facilities) {
      if (f.facilityId == facilityId) return f.name;
    }
    return 'Facility #$facilityId';
  }

  String _formatRole(String role) {
    switch (role) {
      case 'platform_admin':
        return 'Platform Admin';
      case 'hospital_admin':
        return 'Hospital Admin';
      case 'doctor':
        return 'Doctor';
      default:
        return role;
    }
  }

  bool get _hasCreatedAtData => _allUsers.any((user) => user.createdAt != null);

  bool _effectiveIsActive(SystemUserItem user) {
    return _localUserActiveOverrides[user.userId] ?? user.isActive;
  }

  String _roleFilterLabel(String value) {
    return value == 'All' ? 'Filter' : 'Filter ${_formatRole(value)}';
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _matchesCreatedDate(DateTime? createdAt) {
    if (_createdFrom == null && _createdTo == null) return true;
    if (createdAt == null) return false;

    final createdDate = _dateOnly(createdAt);
    final fromDate = _createdFrom == null ? null : _dateOnly(_createdFrom!);
    final toDate = _createdTo == null ? null : _dateOnly(_createdTo!);

    if (fromDate != null && createdDate.isBefore(fromDate)) return false;
    if (toDate != null && createdDate.isAfter(toDate)) return false;
    return true;
  }

  void _setCreatedFrom(DateTime? value) {
    setState(() {
      _createdFrom = value;
      if (_createdTo != null &&
          value != null &&
          _dateOnly(_createdTo!).isBefore(_dateOnly(value))) {
        _createdTo = value;
      }
    });
  }

  void _setCreatedTo(DateTime? value) {
    setState(() {
      _createdTo = value;
      if (_createdFrom != null &&
          value != null &&
          _dateOnly(_createdFrom!).isAfter(_dateOnly(value))) {
        _createdFrom = value;
      }
    });
  }

  void _toggleLocalUserStatus(SystemUserItem user) {
    final currentValue = _effectiveIsActive(user);
    final nextValue = !currentValue;

    setState(() {
      if (nextValue == user.isActive) {
        _localUserActiveOverrides.remove(user.userId);
      } else {
        _localUserActiveOverrides[user.userId] = nextValue;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'User status changed locally only. Backend activation is not wired for users yet.',
        ),
      ),
    );
  }

  List<SystemUserItem> get _filteredUsers {
    return _allUsers.where((u) {
      if (_roleFilter != 'All' && u.role != _roleFilter) return false;
      if (!_matchesCreatedDate(u.createdAt)) return false;

      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final inName = u.fullName.toLowerCase().contains(q);
        final inEmail = u.email.toLowerCase().contains(q);
        final inFacility = _facilityNameById(
          u.facilityId,
        ).toLowerCase().contains(q);
        if (!inName && !inEmail && !inFacility) return false;
      }
      return true;
    }).toList();
  }

  void _onSidebarMenuSelected(String item) {
    switch (item) {
      case 'Users':
        return;
      case 'Facilities':
        Navigator.of(context).pushReplacementNamed(
          '/facilities',
          arguments: {'userRole': widget.userRole, 'userName': widget.userName},
        );
        break;
      case 'Doctors':
        Navigator.of(context).pushNamed(
          '/all-doctors',
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

  void _showRegisterDoctorModal() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final specialtyCtrl = TextEditingController();
    int? selectedFacilityId;
    bool submitting = false;
    String? modalError;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Text(
                'Register Doctor',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
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
                            style: const TextStyle(color: _dangerRed),
                          ),
                        ),
                      _field(nameCtrl, 'Full Name', validator: _required),
                      const SizedBox(height: 10),
                      _field(
                        emailCtrl,
                        'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: _required,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        passwordCtrl,
                        'Temporary Password',
                        obscureText: true,
                        validator: _required,
                      ),
                      const SizedBox(height: 10),
                      _field(specialtyCtrl, 'Specialty (optional)'),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: selectedFacilityId,
                        decoration: _inputDecoration('Affiliated Hospital'),
                        items:
                            _facilities
                                .map(
                                  (f) => DropdownMenuItem<int>(
                                    value: f.facilityId,
                                    child: Text(f.name),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (v) => setModalState(() {
                              selectedFacilityId = v;
                            }),
                        validator: (v) {
                          if (v == null) {
                            return 'Affiliated hospital is required.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(foregroundColor: _primaryGreen),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      submitting
                          ? null
                          : () async {
                            if (!formKey.currentState!.validate()) return;
                            setModalState(() {
                              submitting = true;
                              modalError = null;
                            });

                            try {
                              final message =
                                  await ApiService.requestDoctorRegistration(
                                    email: emailCtrl.text.trim(),
                                    password: passwordCtrl.text,
                                    fullName: nameCtrl.text.trim(),
                                    specialty:
                                        specialtyCtrl.text.trim().isEmpty
                                            ? null
                                            : specialtyCtrl.text.trim(),
                                    facilityId: selectedFacilityId,
                                  );

                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                              _fetch(showLoader: false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(message),
                                  backgroundColor: _primaryGreen,
                                ),
                              );
                            } catch (e) {
                              setModalState(() {
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
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text('Register'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddHospitalAdminModal() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    int? selectedFacilityId;
    bool submitting = false;
    String? modalError;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Text(
                'Add Hospital Admin',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
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
                            style: const TextStyle(color: _dangerRed),
                          ),
                        ),
                      _field(nameCtrl, 'Full Name', validator: _required),
                      const SizedBox(height: 10),
                      _field(
                        emailCtrl,
                        'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: _required,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        passwordCtrl,
                        'Temporary Password',
                        obscureText: true,
                        validator: _required,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: selectedFacilityId,
                        decoration: _inputDecoration('Affiliated Hospital'),
                        items:
                            _facilities
                                .map(
                                  (f) => DropdownMenuItem<int>(
                                    value: f.facilityId,
                                    child: Text(f.name),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (v) => setModalState(() {
                              selectedFacilityId = v;
                            }),
                        validator: (v) {
                          if (v == null) {
                            return 'Affiliated hospital is required.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(foregroundColor: _primaryGreen),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      submitting
                          ? null
                          : () async {
                            if (!formKey.currentState!.validate()) return;
                            setModalState(() {
                              submitting = true;
                              modalError = null;
                            });

                            try {
                              await ApiService.registerUser(
                                email: emailCtrl.text.trim(),
                                password: passwordCtrl.text,
                                fullName: nameCtrl.text.trim(),
                                role: 'hospital_admin',
                                facilityId: selectedFacilityId,
                              );

                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                              _fetch(showLoader: false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Hospital admin added successfully.',
                                  ),
                                  backgroundColor: _primaryGreen,
                                ),
                              );
                            } catch (e) {
                              setModalState(() {
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
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text('Add Admin'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = _filteredUsers;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          AdminSidebar(
            activeItem: 'Users',
            onItemSelected: _onSidebarMenuSelected,
          ),
          Expanded(
            child: Column(
              children: [
                AppNavBar(
                  currentUserName: widget.userName,
                  currentUserRole: widget.userRole,
                  navItems: const [],
                  activeItem: 'Users',
                  onSettingsTap: () {},
                  onPatientTap: (id) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PatientDetailPage(
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
                      horizontal: 28,
                      vertical: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 16,
                                        color: _accentGold,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Platform Administration',
                                        style: TextStyle(
                                          color: _accentGold,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Users',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Manage user accounts across facilities.',
                                    style: TextStyle(color: Colors.black),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed:
                                          _isLoading
                                              ? null
                                              : () => _fetch(showLoader: false),
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('Refresh'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _primaryGreen,
                                        side: const BorderSide(
                                          color: _primaryGreen,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _showRegisterDoctorModal,
                                      icon: const Icon(
                                        Icons.person_add_alt_1,
                                        size: 18,
                                      ),
                                      label: const Text('Register Doctor'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primaryGreen,
                                        foregroundColor: Colors.black,
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _showAddHospitalAdminModal,
                                      icon: const Icon(
                                        Icons.admin_panel_settings,
                                        size: 18,
                                      ),
                                      label: const Text('Add Hospital Admin'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primaryGreen,
                                        foregroundColor: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _buildFilters(),
                        if (_isRefreshing)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        const SizedBox(height: 16),
                        if (_isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(30),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (_errorMessage != null)
                          _buildErrorState()
                        else
                          _buildTable(users),
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

  Widget _buildFilters() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: AdminSearchField(
            controller: _searchController,
            hintText: 'Search by name, email, or hospital',
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: AdminDropdownFilter(
            value: _roleFilter,
            items: _roleOptions,
            icon: Icons.filter_alt_outlined,
            itemLabel: _formatRole,
            selectedLabelBuilder: _roleFilterLabel,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _roleFilter = v);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: AdminDateRangeFilter(
            fromDate: _createdFrom,
            toDate: _createdTo,
            onFromDateChanged: _setCreatedFrom,
            onToDateChanged: _setCreatedTo,
            enabled: _hasCreatedAtData,
            unavailableLabel:
                'Created date filter unavailable because the current users API does not expose created_at.',
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.tableSurface,
        border: Border.all(color: _dangerRed),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _dangerRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: _dangerRed),
            ),
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

  Widget _buildTable(List<SystemUserItem> users) {
    return AdminTableShell(
      minWidth: 1320,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.1),
          1: FlexColumnWidth(2.5),
          2: FlexColumnWidth(1.5),
          3: FlexColumnWidth(2.0),
          4: FlexColumnWidth(1.5),
          5: FlexColumnWidth(1.5),
          6: FlexColumnWidth(1.1),
          7: FlexColumnWidth(1.6),
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
              _HeaderCell('Name'),
              _HeaderCell('Email'),
              _HeaderCell('Role'),
              _HeaderCell('Facility'),
              _HeaderCell('Specialty'),
              _HeaderCell('Created At'),
              _HeaderCell('Status'),
              _HeaderCell('Action'),
            ],
          ),
          ...users.map(
            (user) => TableRow(
              children: [
                _userNameCell(user),
                _dataCell(user.email),
                _dataCell(_formatRole(user.role)),
                _dataCell(_facilityNameById(user.facilityId)),
                _dataCell(
                  user.specialty?.trim().isNotEmpty == true
                      ? user.specialty!
                      : '-',
                ),
                _dataCell(_fmtDate(user.createdAt)),
                _statusBadge(_effectiveIsActive(user)),
                _userActionCell(user),
              ],
            ),
          ),
          if (users.isEmpty)
            TableRow(
              children: List.generate(
                8,
                (index) =>
                    index == 3
                        ? _dataCell(
                          'No users found for current filters.',
                          align: TextAlign.center,
                        )
                        : _dataCell(''),
              ),
            ),
        ],
      ),
    );
  }

  Widget _userNameCell(SystemUserItem user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        user.fullName,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AdminUi.primaryText,
        ),
      ),
    );
  }

  Widget _dataCell(String text, {TextAlign align = TextAlign.start}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(
          fontSize: 13,
          color: AdminUi.primaryText,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _statusBadge(bool isActive) {
    final color = isActive ? _primaryGreen : _dangerRed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          isActive ? 'Active' : 'Inactive',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _userActionCell(SystemUserItem user) {
    final isActive = _effectiveIsActive(user);
    final color = isActive ? _dangerRed : _primaryGreen;
    final label = isActive ? 'Deactivate' : 'Activate';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _toggleLocalUserStatus(user),
          style: TextButton.styleFrom(
            foregroundColor: color,
            backgroundColor: color.withAlpha(18),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: color.withAlpha(120)),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: Text(label),
        ),
      ),
    );
  }

  static InputDecoration _inputDecoration(String label) {
    return InputDecoration(
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
      labelStyle: const TextStyle(color: Colors.black),
      fillColor: Colors.white,
      filled: true,
    );
  }

  static String? _required(String? v) {
    if (v == null || v.trim().isEmpty) return 'This field is required.';
    return null;
  }

  static Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: _inputDecoration(label),
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
