import 'package:flutter/material.dart';

import '../components/admin_sidebar.dart';
import '../components/app_navbar.dart';
import '../services/api_service.dart';
import 'patient_detail_page.dart';
import 'rooms_page.dart';

class FacilityDetailPage extends StatefulWidget {
  final FacilityItem facility;
  final String userRole;
  final String userName;

  const FacilityDetailPage({
    Key? key,
    required this.facility,
    required this.userRole,
    required this.userName,
  }) : super(key: key);

  @override
  State<FacilityDetailPage> createState() => _FacilityDetailPageState();
}

class _FacilityDetailPageState extends State<FacilityDetailPage> {
  static const Color _primaryGreen = Color(0xFF8B9E3A);
  static const Color _dangerRed = Color(0xFFB91C1C);
  static const Color _accentGold = Color(0xFFB8860B);

  int _activeTab = 0;

  bool _loadingDoctors = true;
  bool _loadingRooms = true;
  bool _loadingPatients = false;

  String? _doctorsError;
  String? _roomsError;
  String? _patientsError;

  List<DoctorItem> _doctors = [];
  List<RoomResponse> _rooms = [];
  List<PatientListItem> _patients = [];

  @override
  void initState() {
    super.initState();
    _loadDoctors();
    _loadRooms();
  }

  Future<void> _loadDoctors() async {
    setState(() {
      _loadingDoctors = true;
      _doctorsError = null;
    });
    try {
      final list = await ApiService.getDoctors();
      if (!mounted) return;
      setState(() {
        _doctors =
            list
                .where((d) => d.facilityId == widget.facility.facilityId)
                .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _doctorsError = 'Failed to load doctors.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingDoctors = false;
      });
    }
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loadingRooms = true;
      _roomsError = null;
    });
    try {
      final list = await ApiService.getRooms(
        facilityId: widget.facility.facilityId,
      );
      if (!mounted) return;
      setState(() {
        _rooms = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _roomsError = 'Failed to load rooms.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingRooms = false;
      });
    }
  }

  Future<void> _loadPatients() async {
    if (widget.userRole == 'platform_admin') return;
    setState(() {
      _loadingPatients = true;
      _patientsError = null;
    });
    try {
      final list = await ApiService.getPatients();
      if (!mounted) return;
      setState(() {
        _patients = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _patientsError = 'Failed to load patients.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingPatients = false;
      });
    }
  }

  Future<void> _showAddDoctorDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final specialtyCtrl = TextEditingController();
    bool submitting = false;
    String? error;

    await showDialog<void>(
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
                'Add Doctor',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            error!,
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
                              error = null;
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
                                    facilityId: widget.facility.facilityId,
                                  );
                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                              _loadDoctors();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(message),
                                  backgroundColor: _primaryGreen,
                                ),
                              );
                            } catch (e) {
                              setModalState(() {
                                submitting = false;
                                error = e.toString().replaceFirst(
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
                          : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditDoctorDialog(DoctorItem doctor) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: doctor.fullName);
    final emailCtrl = TextEditingController(text: doctor.email);
    final specialtyCtrl = TextEditingController(text: doctor.specialty ?? '');
    bool submitting = false;
    String? error;

    await showDialog<void>(
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
                'Edit Doctor',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: 500,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            error!,
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
                      _field(specialtyCtrl, 'Specialty (optional)'),
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
                              error = null;
                            });
                            try {
                              final updates = <String, dynamic>{
                                'full_name': nameCtrl.text.trim(),
                                'email': emailCtrl.text.trim(),
                              };
                              if (specialtyCtrl.text.trim().isNotEmpty) {
                                updates['specialty'] =
                                    specialtyCtrl.text.trim();
                              }
                              final message =
                                  await ApiService.requestDoctorUpdate(
                                    doctor.userId,
                                    updates,
                                  );
                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                              _loadDoctors();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(message),
                                  backgroundColor: _primaryGreen,
                                ),
                              );
                            } catch (e) {
                              setModalState(() {
                                submitting = false;
                                error = e.toString().replaceFirst(
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
                          : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleDoctorStatus(DoctorItem doctor) async {
    final actionLabel = doctor.isActive ? 'deactivate' : 'activate';
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Text(
              '${doctor.isActive ? 'Deactivate' : 'Activate'} Doctor',
              style: const TextStyle(color: Colors.black),
            ),
            content: Text(
              'Are you sure you want to $actionLabel ${doctor.fullName}?',
              style: const TextStyle(color: Colors.black),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(foregroundColor: _primaryGreen),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      final message =
          doctor.isActive
              ? await ApiService.requestDoctorDeactivate(doctor.userId)
              : await ApiService.requestDoctorActivate(doctor.userId);
      if (!mounted) return;
      _loadDoctors();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: _primaryGreen),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: _dangerRed,
        ),
      );
    }
  }

  void _onTabSelected(int index) {
    if (index == 2 && widget.userRole == 'platform_admin') {
      _showPatientsAccessModal();
      return;
    }

    setState(() {
      _activeTab = index;
    });

    if (index == 2 && _patients.isEmpty && !_loadingPatients) {
      _loadPatients();
    }
  }

  void _showPatientsAccessModal() {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: const Text(
              'Access Required',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            content: const Text(
              'Platform admins cannot open this patient list directly. Please request access from the hospital.',
              style: TextStyle(color: Colors.black),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(foregroundColor: _primaryGreen),
                child: const Text('Understood'),
              ),
            ],
          ),
    );
  }

  void _onSidebarMenuSelected(String item) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          AdminSidebar(
            activeItem: 'Facilities',
            onItemSelected: _onSidebarMenuSelected,
          ),
          Expanded(
            child: Column(
              children: [
                AppNavBar(
                  currentUserName: widget.userName,
                  currentUserRole: widget.userRole,
                  navItems: const [],
                  activeItem: 'Facilities',
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
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Back to Facilities'),
                          style: TextButton.styleFrom(
                            foregroundColor: _primaryGreen,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            Icon(Icons.star, size: 16, color: _accentGold),
                            SizedBox(width: 8),
                            Text(
                              'Facility Profile',
                              style: TextStyle(
                                color: _accentGold,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.facility.name,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoCard(),
                        const SizedBox(height: 22),
                        _buildTabs(),
                        const SizedBox(height: 16),
                        _buildCurrentTabBody(),
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

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        runSpacing: 10,
        spacing: 28,
        children: [
          _detailItem('Location', widget.facility.location),
          _detailItem('Email', widget.facility.primaryEmail),
          _detailItem('Phone', widget.facility.primaryPhone),
          _detailItem('Admin', widget.facility.adminName ?? 'Not assigned'),
          _detailItem('Doctors', widget.facility.totalDoctors.toString()),
          _detailItem('Rooms', widget.facility.totalRooms.toString()),
          _detailItem('Active Rooms', widget.facility.activeRooms.toString()),
          _detailItem(
            'Status',
            widget.facility.isActive ? 'Active' : 'Inactive',
          ),
        ],
      ),
    );
  }

  Widget _detailItem(String label, String value) {
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final tabs = ['Doctors', 'Rooms', 'All Patients'];
    return Row(
      children: List.generate(tabs.length, (index) {
        final isActive = _activeTab == index;
        return Padding(
          padding: EdgeInsets.only(right: index == tabs.length - 1 ? 0 : 10),
          child: OutlinedButton(
            onPressed: () => _onTabSelected(index),
            style: OutlinedButton.styleFrom(
              foregroundColor: isActive ? Colors.black : _primaryGreen,
              backgroundColor: isActive ? _primaryGreen : Colors.white,
              side: BorderSide(color: _primaryGreen),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: Text(tabs[index]),
          ),
        );
      }),
    );
  }

  Widget _buildCurrentTabBody() {
    if (_activeTab == 0) return _buildDoctorsTab();
    if (_activeTab == 1) return _buildRoomsTab();
    return _buildPatientsTab();
  }

  Widget _buildDoctorsTab() {
    if (_loadingDoctors) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_doctorsError != null) {
      return _errorBlock(_doctorsError!, onRetry: _loadDoctors);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton.icon(
          onPressed: _showAddDoctorDialog,
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text('Add Doctor'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryGreen,
            foregroundColor: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 860),
                child: Table(
                  border: TableBorder.all(color: Colors.black12, width: 1),
                  columnWidths: const {
                    0: FlexColumnWidth(2.1),
                    1: FlexColumnWidth(2.3),
                    2: FlexColumnWidth(1.6),
                    3: FlexColumnWidth(1.2),
                    4: FlexColumnWidth(1.8),
                  },
                  children: [
                    const TableRow(
                      children: [
                        _TableHeader('Name'),
                        _TableHeader('Email'),
                        _TableHeader('Specialty'),
                        _TableHeader('Status'),
                        _TableHeader('Action'),
                      ],
                    ),
                    ..._doctors.map(
                      (doctor) => TableRow(
                        children: [
                          _tableCell(doctor.fullName, FontWeight.w600),
                          _tableCell(doctor.email),
                          _tableCell(
                            (doctor.specialty ?? '').trim().isEmpty
                                ? 'Not set'
                                : doctor.specialty!,
                          ),
                          _tableStatusCell(doctor.isActive),
                          _tableActionCell(doctor),
                        ],
                      ),
                    ),
                    if (_doctors.isEmpty)
                      const TableRow(
                        children: [
                          _TableCell('No doctors found'),
                          _TableCell('-'),
                          _TableCell('-'),
                          _TableCell('-'),
                          _TableCell('-'),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tableCell(String value, [FontWeight weight = FontWeight.w500]) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        value,
        style: TextStyle(color: Colors.black, fontWeight: weight),
      ),
    );
  }

  Widget _tableStatusCell(bool isActive) {
    final color = isActive ? _primaryGreen : _accentGold;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          isActive ? 'Active' : 'Inactive',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _tableActionCell(DoctorItem doctor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          TextButton(
            onPressed: () => _showEditDoctorDialog(doctor),
            style: TextButton.styleFrom(
              foregroundColor: _primaryGreen,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () => _toggleDoctorStatus(doctor),
            style: TextButton.styleFrom(
              foregroundColor: _accentGold,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: Text(doctor.isActive ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsTab() {
    if (_loadingRooms) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_roomsError != null) {
      return _errorBlock(_roomsError!, onRetry: _loadRooms);
    }

    return _simpleTable(
      columns: const ['Room', 'Type', 'Floor', 'Capacity', 'Status'],
      rows:
          _rooms
              .map(
                (r) => [
                  r.roomName,
                  r.roomType,
                  r.floorNumber?.toString() ?? '-',
                  r.capacity.toString(),
                  r.status,
                ],
              )
              .toList(),
    );
  }

  Widget _buildPatientsTab() {
    if (widget.userRole == 'platform_admin') {
      return _errorBlock(
        'This section is restricted for platform admins. Request access from the hospital.',
        isUrgent: true,
      );
    }
    if (_loadingPatients) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_patientsError != null) {
      return _errorBlock(_patientsError!, onRetry: _loadPatients);
    }

    return _simpleTable(
      columns: const ['Patient Name', 'Phone', 'Priority', 'Queue Status'],
      rows:
          _patients
              .map(
                (p) => [
                  p.fullName,
                  p.phoneNumber ?? '-',
                  p.priority ?? '-',
                  p.queueStatus ?? '-',
                ],
              )
              .toList(),
    );
  }

  Widget _simpleTable({
    required List<String> columns,
    required List<List<String>> rows,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: Colors.black12, width: 1),
            children: [
              TableRow(
                children:
                    columns
                        .map(
                          (c) => Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              c,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              if (rows.isEmpty)
                TableRow(
                  children: List.generate(
                    columns.length,
                    (index) => Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        index == 0 ? 'No records available' : '-',
                        style: const TextStyle(color: Colors.black),
                      ),
                    ),
                  ),
                )
              else
                ...rows.map(
                  (row) => TableRow(
                    children:
                        row
                            .map(
                              (value) => Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  value,
                                  style: const TextStyle(color: Colors.black),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBlock(
    String message, {
    Future<void> Function()? onRetry,
    bool isUrgent = false,
  }) {
    final color = isUrgent ? _dangerRed : _primaryGreen;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryGreen,
                side: const BorderSide(color: _primaryGreen),
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  static String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
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
      fillColor: Colors.white,
      filled: true,
      labelStyle: const TextStyle(color: Colors.black),
    );
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

class _TableHeader extends StatelessWidget {
  final String label;

  const _TableHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String value;

  const _TableCell(this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(value, style: const TextStyle(color: Colors.black)),
    );
  }
}
