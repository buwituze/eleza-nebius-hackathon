import 'dart:async';

import 'package:flutter/material.dart';

import '../components/admin_sidebar.dart';
import '../components/admin_ui.dart';
import '../components/app_navbar.dart';
import '../screens/facility_detail_page.dart';
import '../screens/patient_detail_page.dart';
import '../screens/rooms_page.dart';
import '../services/api_service.dart';

class FacilitiesPage extends StatefulWidget {
  final String userRole;
  final String userName;

  const FacilitiesPage({
    super.key,
    required this.userRole,
    required this.userName,
  });

  @override
  State<FacilitiesPage> createState() => _FacilitiesPageState();
}

class _FacilitiesPageState extends State<FacilitiesPage> {
  static const Color _primaryGreen = Color(0xFF8B9E3A);
  static const Color _accentGold = Color(0xFFB8860B);

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<FacilityItem> _all = [];
  String _searchQuery = '';
  String? _statusFilter = 'All';
  DateTime? _createdFrom;
  DateTime? _createdTo;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  static const _statusOptions = ['All', 'Active', 'Inactive'];

  @override
  void initState() {
    super.initState();
    _fetch(showLoader: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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
      final result = await ApiService.getFacilities();
      if (!mounted) return;
      setState(() => _all = result);
    } catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _errorMessage =
                'Failed to load facilities. Check connectivity and login status.',
      );
      debugPrint('Fetch facilities error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      setState(() {});
    });
  }

  bool get _hasCreatedAtData =>
      _all.any((facility) => facility.createdAt != null);

  String _statusFilterLabel(String value) {
    return value == 'All' ? 'Filter' : 'Filter $value';
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

  List<FacilityItem> get _filtered {
    return _all.where((f) {
      if (_statusFilter == 'Active' && !f.isActive) return false;
      if (_statusFilter == 'Inactive' && f.isActive) return false;
      if (!_matchesCreatedDate(f.createdAt)) return false;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        if (!f.name.toLowerCase().contains(q) &&
            !f.location.toLowerCase().contains(q) &&
            !(f.adminName ?? '').toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  int get _activeCount => _all.where((f) => f.isActive).length;
  int get _totalDoctors => _all.fold(0, (sum, f) => sum + f.totalDoctors);

  // -------------------------------------------------------------------------
  // Add Facility modal
  // -------------------------------------------------------------------------
  void _showAddFacilityDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    String? saveError;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: const Text(
                'Add Facility',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (saveError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            saveError!,
                            style: const TextStyle(color: _accentGold),
                          ),
                        ),
                      _formField(
                        nameCtrl,
                        'Facility Name',
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      _formField(
                        emailCtrl,
                        'Primary Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      _formField(
                        phoneCtrl,
                        'Primary Phone',
                        keyboardType: TextInputType.phone,
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      _formField(
                        locationCtrl,
                        'Location',
                        validator: _required,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.black,
                  ),
                  onPressed:
                      saving
                          ? null
                          : () async {
                            if (!formKey.currentState!.validate()) return;
                            setModalState(() {
                              saving = true;
                              saveError = null;
                            });
                            try {
                              await ApiService.createFacility(
                                name: nameCtrl.text.trim(),
                                primaryEmail: emailCtrl.text.trim(),
                                primaryPhone: phoneCtrl.text.trim(),
                                location: locationCtrl.text.trim(),
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              _fetch(showLoader: false);
                            } catch (e) {
                              setModalState(() {
                                saving = false;
                                saveError = e.toString().replaceFirst(
                                  'Exception: ',
                                  '',
                                );
                              });
                            }
                          },
                  child:
                      saving
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // View Facility modal
  // -------------------------------------------------------------------------
  void _showViewDialog(FacilityItem f) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Text(
              f.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _infoRow('Location', f.location),
                  _infoRow('Email', f.primaryEmail),
                  _infoRow('Phone', f.primaryPhone),
                  _infoRow('Admin', f.adminName ?? '—'),
                  _infoRow('Total Doctors', f.totalDoctors.toString()),
                  _infoRow('Total Rooms', f.totalRooms.toString()),
                  _infoRow('Active Rooms', f.activeRooms.toString()),
                  _infoRow('Status', f.isActive ? 'Active' : 'Inactive'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _showEditDialog(f);
                },
                child: const Text('Edit'),
              ),
            ],
          ),
    );
  }

  // -------------------------------------------------------------------------
  // Edit Facility modal
  // -------------------------------------------------------------------------
  void _showEditDialog(FacilityItem facility) {
    final nameCtrl = TextEditingController(text: facility.name);
    final emailCtrl = TextEditingController(text: facility.primaryEmail);
    final phoneCtrl = TextEditingController(text: facility.primaryPhone);
    final locationCtrl = TextEditingController(text: facility.location);
    final hospitalAdminsFuture = ApiService.getHospitalAdmins();
    bool isActive = facility.isActive;
    int? selectedAdminId = facility.adminUserId;

    // New hospital admin form state
    bool showNewAdminForm = false;
    final newNameCtrl = TextEditingController();
    final newEmailCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();

    final formKey = GlobalKey<FormState>();
    bool saving = false;
    String? saveError;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Text(
                'Edit ${facility.name}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (saveError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              saveError!,
                              style: const TextStyle(color: _accentGold),
                            ),
                          ),
                        _formField(
                          nameCtrl,
                          'Facility Name',
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        _formField(
                          emailCtrl,
                          'Primary Email',
                          keyboardType: TextInputType.emailAddress,
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        _formField(
                          phoneCtrl,
                          'Primary Phone',
                          keyboardType: TextInputType.phone,
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        _formField(
                          locationCtrl,
                          'Location',
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        // Active toggle
                        Row(
                          children: [
                            const Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Switch(
                              value: isActive,
                              activeColor: _primaryGreen,
                              onChanged:
                                  (v) => setModalState(() => isActive = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Hospital Admin',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Assign existing admin
                        FutureBuilder<List<AdminUserItem>>(
                          future: hospitalAdminsFuture,
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: LinearProgressIndicator(
                                  color: _primaryGreen,
                                ),
                              );
                            }
                            if (snap.hasError) {
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _accentGold.withAlpha(120),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: _accentGold.withAlpha(22),
                                ),
                                child: Text(
                                  'Could not load hospital admins. Please retry after backend fix.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _accentGold,
                                  ),
                                ),
                              );
                            }
                            final admins = snap.data ?? [];
                            final items = [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text(
                                  '— None —',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                              ...admins.map(
                                (a) => DropdownMenuItem<int?>(
                                  value: a.userId,
                                  child: Text('${a.fullName} (${a.email})'),
                                ),
                              ),
                            ];
                            return DropdownButtonFormField<int?>(
                              value:
                                  admins.any((a) => a.userId == selectedAdminId)
                                      ? selectedAdminId
                                      : null,
                              decoration: InputDecoration(
                                labelText: 'Assign existing admin',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                              items: items,
                              onChanged:
                                  (val) => setModalState(() {
                                    selectedAdminId = val;
                                  }),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        // Or create a new hospital admin
                        GestureDetector(
                          onTap:
                              () => setModalState(
                                () => showNewAdminForm = !showNewAdminForm,
                              ),
                          child: Row(
                            children: [
                              Icon(
                                showNewAdminForm
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: _primaryGreen,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                showNewAdminForm
                                    ? 'Hide new admin form'
                                    : '+ Create a new hospital admin',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _primaryGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showNewAdminForm) ...[
                          const SizedBox(height: 12),
                          _formField(
                            newNameCtrl,
                            'Full Name',
                            validator: _required,
                          ),
                          const SizedBox(height: 10),
                          _formField(
                            newEmailCtrl,
                            'Email',
                            keyboardType: TextInputType.emailAddress,
                            validator: _required,
                          ),
                          const SizedBox(height: 10),
                          _formField(
                            newPasswordCtrl,
                            'Password',
                            obscureText: true,
                            validator: _required,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'New admin will be linked to this facility.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.black,
                  ),
                  onPressed:
                      saving
                          ? null
                          : () async {
                            if (!formKey.currentState!.validate()) return;
                            setModalState(() {
                              saving = true;
                              saveError = null;
                            });
                            try {
                              int? adminId = selectedAdminId;
                              // Create new admin if the form is shown and filled
                              if (showNewAdminForm &&
                                  newEmailCtrl.text.trim().isNotEmpty) {
                                final newAdmin = await ApiService.registerUser(
                                  email: newEmailCtrl.text.trim(),
                                  password: newPasswordCtrl.text,
                                  fullName: newNameCtrl.text.trim(),
                                  role: 'hospital_admin',
                                  facilityId: facility.facilityId,
                                );
                                adminId = newAdmin.userId;
                              }
                              final updates = <String, dynamic>{
                                'name': nameCtrl.text.trim(),
                                'primary_email': emailCtrl.text.trim(),
                                'primary_phone': phoneCtrl.text.trim(),
                                'location': locationCtrl.text.trim(),
                                'is_active': isActive,
                              };
                              if (adminId != null) {
                                updates['admin_user_id'] = adminId;
                              }
                              await ApiService.updateFacility(
                                facility.facilityId,
                                updates,
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              _fetch(showLoader: false);
                            } catch (e) {
                              setModalState(() {
                                saving = false;
                                saveError = e.toString().replaceFirst(
                                  'Exception: ',
                                  '',
                                );
                              });
                            }
                          },
                  child:
                      saving
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  void _onSidebarMenuSelected(String item) {
    if (item == 'Facilities') return;

    switch (item) {
      case 'Users':
        Navigator.of(context).pushNamed(
          '/admin-users',
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
    final items = _filtered;

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
                        // Header row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Facilities',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Manage all registered facilities and their hospital admins.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
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
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: _showAddFacilityDialog,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Facility'),
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
                        // Metric cards
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _metricCard(
                              'Total Facilities',
                              _all.length.toString(),
                            ),
                            _metricCard('Active', _activeCount.toString()),
                            _metricCard(
                              'Total Doctors',
                              _totalDoctors.toString(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Filter bar
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
                        // Table or state
                        if (_isLoading)
                          _loadingState()
                        else if (_errorMessage != null)
                          _errorState()
                        else
                          _table(items),
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
            hintText: 'Search facilities…',
            onChanged: _onSearchChanged,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: AdminDropdownFilter(
            value: _statusFilter ?? _statusOptions.first,
            items: _statusOptions,
            icon: Icons.filter_alt_outlined,
            selectedLabelBuilder: _statusFilterLabel,
            onChanged: (value) => setState(() => _statusFilter = value),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 4,
          child: AdminDateRangeFilter(
            fromDate: _createdFrom,
            toDate: _createdTo,
            onFromDateChanged: _setCreatedFrom,
            onToDateChanged: _setCreatedTo,
            enabled: _hasCreatedAtData,
            unavailableLabel:
                'Created date filter unavailable because the current facilities API does not expose created_at.',
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value) {
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ],
      ),
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

  Widget _table(List<FacilityItem> items) {
    return AdminTableShell(
      minWidth: 1420,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.3),
          1: FlexColumnWidth(2.4),
          2: FlexColumnWidth(1.8),
          3: FlexColumnWidth(2.1),
          4: FlexColumnWidth(1.9),
          5: FlexColumnWidth(1.1),
          6: FlexColumnWidth(1.2),
          7: FlexColumnWidth(1.5),
          8: FlexColumnWidth(1.2),
          9: FlexColumnWidth(1.1),
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
          TableRow(
            decoration: const BoxDecoration(color: AdminUi.tableHeader),
            children: [
              _headerCell('Facility'),
              _headerCell('Primary Email'),
              _headerCell('Primary Phone'),
              _headerCell('Location'),
              _headerCell('Admin'),
              _headerCell('Doctors'),
              _headerCell('Rooms'),
              _headerCell('Created At'),
              _headerCell('Status'),
              _headerCell('Action'),
            ],
          ),
          ...items.map(
            (f) => TableRow(
              children: [
                _facilityNameCell(f),
                _dataCell(f.primaryEmail),
                _dataCell(f.primaryPhone),
                _dataCell(f.location),
                _dataCell(f.adminName ?? '—'),
                _dataCell(f.totalDoctors.toString()),
                _dataCell('${f.activeRooms}/${f.totalRooms}'),
                _dataCell(_fmtDate(f.createdAt)),
                _statusBadge(f.isActive),
                _actionCell(f),
              ],
            ),
          ),
          if (items.isEmpty)
            TableRow(
              children: List.generate(
                10,
                (i) =>
                    i == 4
                        ? _dataCell(
                          'No facilities found for the current filters.',
                          align: TextAlign.center,
                        )
                        : _dataCell(''),
              ),
            ),
        ],
      ),
    );
  }

  Widget _headerCell(String label) {
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

  Widget _facilityNameCell(FacilityItem f) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        f.name,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AdminUi.primaryText,
        ),
      ),
    );
  }

  Widget _statusBadge(bool isActive) {
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
          isActive ? 'Active' : 'Inactive',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _actionCell(FacilityItem f) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdminActionIconButton(
            tooltip: 'View',
            icon: Icons.visibility_outlined,
            backgroundColor: AdminUi.viewAction,
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (_) => FacilityDetailPage(
                          facility: f,
                          userRole: widget.userRole,
                          userName: widget.userName,
                        ),
                  ),
                ),
          ),
          const SizedBox(width: 6),
          AdminActionIconButton(
            tooltip: 'Edit',
            icon: Icons.edit_outlined,
            backgroundColor: AdminUi.editAction,
            onTap: () => _showEditDialog(f),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  static String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  static Widget _formField(
    TextEditingController ctrl,
    String label, {
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}
