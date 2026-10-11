import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Conditional import for multipart file handling
import 'api_service_stub.dart'
    if (dart.library.io) 'api_service_io.dart'
    as multipart;

class ApiService {
  static SharedPreferences? _prefs;

  static Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Automatically detect the correct base URL based on platform
  static String get baseUrl {
    if (kIsWeb) {
      return 'https://boisterously-implicatory-anderson.ngrok-free.dev'; // ngrok (local dev)
      // return 'https://benithatuze-eleza-backend.hf.space'; // HuggingFace Space
    }

    final envUrl =
        dotenv.env['API_BASE_URL'] ??
        dotenv.env['BACKEND_BASE_URL'] ??
        dotenv.env['BASE_URL'];
    if (envUrl != null && envUrl.trim().isNotEmpty) {
      return envUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }

    // For mobile, default to Android emulator
    // TODO: Update for iOS simulator or physical device
    return 'http://10.0.2.2:8000';
  }

  static dynamic _parseJsonResponse(http.Response response, String endpoint) {
    final body = response.body.trim();

    if (body.startsWith('<!DOCTYPE') || body.startsWith('<html')) {
      throw Exception(
        'Expected JSON from $endpoint but received HTML. '
        'Check API_BASE_URL and proxy/tunnel settings. '
        'status=${response.statusCode}',
      );
    }

    try {
      return jsonDecode(response.body);
    } catch (e) {
      throw Exception(
        'Invalid JSON from $endpoint: ${e.toString()} '
        'status=${response.statusCode}',
      );
    }
  }

  // Get stored auth token
  static Future<String?> getAuthToken() async {
    await _initPrefs();
    return _prefs!.getString('auth_token');
  }

  // Store auth token
  static Future<void> setAuthToken(String token) async {
    await _initPrefs();
    await _prefs!.setString('auth_token', token);
  }

  // Clear auth token
  static Future<void> clearAuthToken() async {
    await _initPrefs();
    await _prefs!.remove('auth_token');
  }

  // Get stored user info
  static Future<Map<String, dynamic>?> getUserInfo() async {
    await _initPrefs();
    final userJson = _prefs!.getString('user_info');
    if (userJson != null) {
      return jsonDecode(userJson);
    }
    return null;
  }

  // Store user info
  static Future<void> setUserInfo(Map<String, dynamic> userInfo) async {
    await _initPrefs();
    await _prefs!.setString('user_info', jsonEncode(userInfo));
  }

  // Clear user info
  static Future<void> clearUserInfo() async {
    await _initPrefs();
    await _prefs!.remove('user_info');
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }

  // Logout
  static Future<void> logout() async {
    await clearAuthToken();
    await clearUserInfo();
  }

  // Get auth headers for API calls
  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await getAuthToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // Required for ngrok free domains to skip HTML browser warning pages.
      if (kIsWeb) 'ngrok-skip-browser-warning': 'true',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Login with email and password
  static Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('POST $baseUrl/auth/login');
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (kIsWeb) 'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      debugPrint('Login response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = _parseJsonResponse(response, '/auth/login');
        final loginResponse = LoginResponse.fromJson(data);

        // Store token and user info
        await setAuthToken(loginResponse.accessToken);
        await setUserInfo(loginResponse.user.toJson());

        return loginResponse;
      } else {
        final errorData = _parseJsonResponse(response, '/auth/login');
        throw Exception(errorData['detail'] ?? 'Login failed');
      }
    } catch (e) {
      debugPrint('Error in login: $e');
      throw Exception('Login failed: $e');
    }
  }

  /// Get current user info
  static Future<UserInfo?> getCurrentUser() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = _parseJsonResponse(response, '/auth/me');
        return UserInfo.fromJson(data);
      } else {
        return null;
      }
    } catch (e) {
      debugPrint('Error getting current user: $e');
      return null;
    }
  }

  /// Get list of patients
  static Future<List<PatientListItem>> getPatients({String? search}) async {
    try {
      final headers = await _getAuthHeaders();
      final uri = Uri.parse(
        '$baseUrl/patients',
      ).replace(queryParameters: search != null ? {'search': search} : null);

      debugPrint('GET $uri');
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = _parseJsonResponse(response, uri.toString()) as List;
        return data.map((item) => PatientListItem.fromJson(item)).toList();
      } else {
        final raw = response.body.trim();
        final snippet = raw.length > 140 ? '${raw.substring(0, 140)}...' : raw;
        throw Exception(
          'Failed to get patients: ${response.statusCode}. body=$snippet',
        );
      }
    } catch (e) {
      debugPrint('Error getting patients: $e');
      throw Exception('Failed to get patients: $e');
    }
  }

  /// Get patient details
  static Future<PatientDetail> getPatient(int patientId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/patients/$patientId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = _parseJsonResponse(response, '/patients/$patientId');
        return PatientDetail.fromJson(data);
      } else {
        throw Exception('Failed to get patient: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting patient: $e');
      throw Exception('Failed to get patient: $e');
    }
  }

  /// Get patient sessions
  static Future<List<SessionSummary>> getPatientSessions(int patientId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/patients/$patientId/sessions'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data =
            _parseJsonResponse(response, '/patients/$patientId/sessions')
                as List;
        return data.map((item) => SessionSummary.fromJson(item)).toList();
      } else {
        throw Exception(
          'Failed to get patient sessions: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error getting patient sessions: $e');
      throw Exception('Failed to get patient sessions: $e');
    }
  }

  /// Get detailed session information
  static Future<SessionDetail> getSessionDetail(
    int patientId,
    int sessionId,
  ) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/patients/$patientId/session/$sessionId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = _parseJsonResponse(
          response,
          '/patients/$patientId/session/$sessionId',
        );
        return SessionDetail.fromJson(data);
      } else {
        throw Exception('Failed to get session detail: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting session detail: $e');
      throw Exception('Failed to get session detail: $e');
    }
  }

  /// Get list of rooms
  static Future<List<RoomResponse>> getRooms({
    int? facilityId,
    String? status,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final queryParams = <String, String>{};
      if (facilityId != null)
        queryParams['facility_id'] = facilityId.toString();
      if (status != null) queryParams['status'] = status;

      final uri = Uri.parse(
        '$baseUrl/rooms',
      ).replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.map((item) => RoomResponse.fromJson(item)).toList();
      } else {
        throw Exception('Failed to get rooms: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting rooms: $e');
      throw Exception('Failed to get rooms: $e');
    }
  }

  /// Create a room and return a user-facing status message.
  /// Handles immediate create (200/201) and pending confirmation (202).
  static Future<String> requestRoomCreate({
    required int facilityId,
    required String roomName,
    required String roomType,
    int? floorNumber,
    int capacity = 1,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final body = <String, dynamic>{
        'facility_id': facilityId,
        'room_name': roomName,
        'room_type': roomType,
        'capacity': capacity,
      };
      if (floorNumber != null) body['floor_number'] = floorNumber;

      final response = await http.post(
        Uri.parse('$baseUrl/rooms'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return 'Room created successfully.';
      }
      if (response.statusCode == 202) {
        final data = _parseJsonResponse(response, '/rooms');
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
        return 'Room creation is pending facility confirmation.';
      }

      final err = _parseJsonResponse(response, '/rooms');
      throw Exception(err['detail'] ?? 'Failed to create room');
    } catch (e) {
      debugPrint('Error requesting room create: $e');
      rethrow;
    }
  }

  /// Update a room and return a user-facing status message.
  /// Handles immediate update (200) and pending confirmation (202).
  static Future<String> requestRoomUpdate(
    int roomId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/rooms/$roomId'),
        headers: headers,
        body: jsonEncode(updates),
      );

      if (response.statusCode == 200) {
        return 'Room updated successfully.';
      }
      if (response.statusCode == 202) {
        final data = _parseJsonResponse(response, '/rooms/$roomId');
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
        return 'Room update is pending facility confirmation.';
      }

      final err = _parseJsonResponse(response, '/rooms/$roomId');
      throw Exception(err['detail'] ?? 'Failed to update room');
    } catch (e) {
      debugPrint('Error requesting room update: $e');
      rethrow;
    }
  }

  /// Delete a room and return a user-facing status message.
  /// Handles immediate delete (200) and pending confirmation (202).
  static Future<String> requestRoomDelete(int roomId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/rooms/$roomId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = _parseJsonResponse(response, '/rooms/$roomId');
        return data['message']?.toString() ?? 'Room deleted successfully.';
      }
      if (response.statusCode == 202) {
        final data = _parseJsonResponse(response, '/rooms/$roomId');
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
        return 'Room deletion is pending facility confirmation.';
      }

      final err = _parseJsonResponse(response, '/rooms/$roomId');
      throw Exception(err['detail'] ?? 'Failed to delete room');
    } catch (e) {
      debugPrint('Error requesting room delete: $e');
      rethrow;
    }
  }

  /// Update room status directly (hospital_admin only).
  static Future<RoomResponse> updateRoomStatus({
    required int roomId,
    required String status,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/rooms/$roomId/status'),
        headers: headers,
        body: jsonEncode({'status': status}),
      );

      if (response.statusCode == 200) {
        return RoomResponse.fromJson(
          _parseJsonResponse(response, '/rooms/$roomId/status'),
        );
      }

      final err = _parseJsonResponse(response, '/rooms/$roomId/status');
      throw Exception(err['detail'] ?? 'Failed to update room status');
    } catch (e) {
      debugPrint('Error updating room status: $e');
      rethrow;
    }
  }

  /// Assign a room to a session queue entry and return assignment metadata.
  /// Backend can auto-populate required exams when not provided.
  static Future<Map<String, dynamic>> assignRoomForSession({
    required int sessionId,
    required int roomId,
    List<String>? requiredExams,
    String? notes,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final body = <String, dynamic>{'room_id': roomId};
      if (requiredExams != null && requiredExams.isNotEmpty) {
        body['required_exams'] = requiredExams;
      }
      if (notes != null && notes.trim().isNotEmpty) {
        body['notes'] = notes.trim();
      }

      final response = await http.post(
        Uri.parse('$baseUrl/queue/session/$sessionId/assign-room'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = _parseJsonResponse(
          response,
          '/queue/session/$sessionId/assign-room',
        );
        if (data is Map<String, dynamic>) return data;
        if (data is Map) {
          return data.map((key, value) => MapEntry(key.toString(), value));
        }
        throw Exception('Invalid assignment response format');
      }

      final err = _parseJsonResponse(
        response,
        '/queue/session/$sessionId/assign-room',
      );
      throw Exception(err['detail'] ?? 'Failed to assign room');
    } catch (e) {
      debugPrint('Error assigning room for session: $e');
      rethrow;
    }
  }

  /// Fetch queue entry with assigned exams for a session
  static Future<Map<String, dynamic>?> getQueueEntryForSession(
    int sessionId,
  ) async {
    try {
      await _initPrefs();
      final headers = await _getAuthHeaders();
      final queueResponse = await http.get(
        Uri.parse('$baseUrl/queue?session_id=$sessionId'),
        headers: headers,
      );

      if (queueResponse.statusCode == 200) {
        final data = jsonDecode(queueResponse.body);
        // data should be a list of queue entries; get the first one
        if (data is List && data.isNotEmpty) {
          return data.first as Map<String, dynamic>;
        }
        return null;
      } else if (queueResponse.statusCode == 404) {
        return null;
      } else {
        final errorData = jsonDecode(queueResponse.body);
        final detail = errorData['detail'] ?? 'Failed to get queue entry';
        throw Exception(detail);
      }
    } catch (e) {
      debugPrint('Error fetching queue entry: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Facilities
  // ---------------------------------------------------------------------------

  /// List all facilities
  static Future<List<FacilityItem>> getFacilities() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/facilities'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = _parseJsonResponse(response, '/facilities') as List;
        return data.map((e) => FacilityItem.fromJson(e)).toList();
      } else {
        throw Exception('Failed to list facilities: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting facilities: $e');
      throw Exception('Failed to get facilities: $e');
    }
  }

  /// Create a new facility
  static Future<FacilityItem> createFacility({
    required String name,
    required String primaryEmail,
    required String primaryPhone,
    required String location,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/facilities'),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'primary_email': primaryEmail,
          'primary_phone': primaryPhone,
          'location': location,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return FacilityItem.fromJson(
          _parseJsonResponse(response, '/facilities'),
        );
      } else {
        final err = _parseJsonResponse(response, '/facilities');
        throw Exception(err['detail'] ?? 'Failed to create facility');
      }
    } catch (e) {
      debugPrint('Error creating facility: $e');
      rethrow;
    }
  }

  /// Update a facility
  static Future<FacilityItem> updateFacility(
    int facilityId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/facilities/$facilityId'),
        headers: headers,
        body: jsonEncode(updates),
      );
      if (response.statusCode == 200) {
        return FacilityItem.fromJson(
          _parseJsonResponse(response, '/facilities/$facilityId'),
        );
      } else {
        final err = _parseJsonResponse(response, '/facilities/$facilityId');
        throw Exception(err['detail'] ?? 'Failed to update facility');
      }
    } catch (e) {
      debugPrint('Error updating facility: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Hospital Admins (for assign-admin in facility)
  // ---------------------------------------------------------------------------

  /// List all hospital_admin users (platform_admin only)
  static Future<List<AdminUserItem>> getHospitalAdmins() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/auth/hospital-admins'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data =
            _parseJsonResponse(response, '/auth/hospital-admins') as List;
        return data.map((e) => AdminUserItem.fromJson(e)).toList();
      } else {
        throw Exception(
          'Failed to list hospital admins: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error getting hospital admins: $e');
      throw Exception('Failed to get hospital admins: $e');
    }
  }

  /// Register any user (platform_admin creates hospital_admin)
  static Future<AdminUserItem> registerUser({
    required String email,
    required String password,
    required String fullName,
    required String role,
    int? facilityId,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final body = <String, dynamic>{
        'email': email,
        'password': password,
        'full_name': fullName,
        'role': role,
      };
      if (facilityId != null) body['facility_id'] = facilityId;
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return AdminUserItem.fromJson(
          _parseJsonResponse(response, '/auth/register'),
        );
      } else {
        final err = _parseJsonResponse(response, '/auth/register');
        throw Exception(err['detail'] ?? 'Failed to register user');
      }
    } catch (e) {
      debugPrint('Error registering user: $e');
      rethrow;
    }
  }

  /// List all users (platform_admin only)
  static Future<List<SystemUserItem>> getAllUsers() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/auth/users'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = _parseJsonResponse(response, '/auth/users') as List;
        return data.map((e) => SystemUserItem.fromJson(e)).toList();
      } else {
        throw Exception('Failed to list users: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting users: $e');
      throw Exception('Failed to get users: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Doctors
  // ---------------------------------------------------------------------------

  /// List doctors (hospital_admin sees own facility; platform_admin sees all)
  static Future<List<DoctorItem>> getDoctors() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/doctors'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = _parseJsonResponse(response, '/doctors') as List;
        return data.map((e) => DoctorItem.fromJson(e)).toList();
      } else {
        throw Exception('Failed to list doctors: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting doctors: $e');
      throw Exception('Failed to get doctors: $e');
    }
  }

  /// Register a new doctor
  static Future<DoctorItem> registerDoctor({
    required String email,
    required String password,
    required String fullName,
    String? specialty,
    int? facilityId,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final body = <String, dynamic>{
        'email': email,
        'password': password,
        'full_name': fullName,
      };
      if (specialty != null && specialty.trim().isNotEmpty)
        body['specialty'] = specialty.trim();
      if (facilityId != null) body['facility_id'] = facilityId;
      final response = await http.post(
        Uri.parse('$baseUrl/doctors'),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return DoctorItem.fromJson(_parseJsonResponse(response, '/doctors'));
      } else {
        final err = _parseJsonResponse(response, '/doctors');
        throw Exception(err['detail'] ?? 'Failed to register doctor');
      }
    } catch (e) {
      debugPrint('Error registering doctor: $e');
      rethrow;
    }
  }

  /// Register a doctor and return a user-facing status message.
  /// Handles both immediate creation (201) and pending confirmation (202).
  static Future<String> requestDoctorRegistration({
    required String email,
    required String password,
    required String fullName,
    String? specialty,
    int? facilityId,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final body = <String, dynamic>{
        'email': email,
        'password': password,
        'full_name': fullName,
      };
      if (specialty != null && specialty.trim().isNotEmpty) {
        body['specialty'] = specialty.trim();
      }
      if (facilityId != null) body['facility_id'] = facilityId;

      final response = await http.post(
        Uri.parse('$baseUrl/doctors'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return 'Doctor registered successfully.';
      }

      if (response.statusCode == 202) {
        final data = _parseJsonResponse(response, '/doctors');
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
        return 'Doctor registration is pending facility confirmation.';
      }

      final err = _parseJsonResponse(response, '/doctors');
      throw Exception(err['detail'] ?? 'Failed to register doctor');
    } catch (e) {
      debugPrint('Error requesting doctor registration: $e');
      rethrow;
    }
  }

  /// Update a doctor
  static Future<DoctorItem> updateDoctor(
    int doctorId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/doctors/$doctorId'),
        headers: headers,
        body: jsonEncode(updates),
      );
      if (response.statusCode == 200) {
        return DoctorItem.fromJson(
          _parseJsonResponse(response, '/doctors/$doctorId'),
        );
      } else {
        final err = _parseJsonResponse(response, '/doctors/$doctorId');
        throw Exception(err['detail'] ?? 'Failed to update doctor');
      }
    } catch (e) {
      debugPrint('Error updating doctor: $e');
      rethrow;
    }
  }

  /// Request doctor update and return a user-facing status message.
  /// Handles immediate update (200) and pending confirmation (202).
  static Future<String> requestDoctorUpdate(
    int doctorId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/doctors/$doctorId'),
        headers: headers,
        body: jsonEncode(updates),
      );

      if (response.statusCode == 200) {
        return 'Doctor updated successfully.';
      }
      if (response.statusCode == 202) {
        final data = _parseJsonResponse(response, '/doctors/$doctorId');
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
        return 'Doctor update is pending facility confirmation.';
      }

      final err = _parseJsonResponse(response, '/doctors/$doctorId');
      throw Exception(err['detail'] ?? 'Failed to update doctor');
    } catch (e) {
      debugPrint('Error requesting doctor update: $e');
      rethrow;
    }
  }

  /// Deactivate a doctor
  static Future<DoctorItem> deactivateDoctor(int doctorId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.patch(
        Uri.parse('$baseUrl/doctors/$doctorId/deactivate'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return DoctorItem.fromJson(
          _parseJsonResponse(response, '/doctors/$doctorId/deactivate'),
        );
      } else {
        final err = _parseJsonResponse(
          response,
          '/doctors/$doctorId/deactivate',
        );
        throw Exception(err['detail'] ?? 'Failed to deactivate doctor');
      }
    } catch (e) {
      debugPrint('Error deactivating doctor: $e');
      rethrow;
    }
  }

  /// Request doctor deactivation and return a user-facing status message.
  /// Handles immediate deactivation (200) and pending confirmation (202).
  static Future<String> requestDoctorDeactivate(int doctorId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.patch(
        Uri.parse('$baseUrl/doctors/$doctorId/deactivate'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return 'Doctor deactivated successfully.';
      }
      if (response.statusCode == 202) {
        final data = _parseJsonResponse(
          response,
          '/doctors/$doctorId/deactivate',
        );
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
        return 'Doctor deactivation is pending facility confirmation.';
      }

      final err = _parseJsonResponse(response, '/doctors/$doctorId/deactivate');
      throw Exception(err['detail'] ?? 'Failed to deactivate doctor');
    } catch (e) {
      debugPrint('Error requesting doctor deactivation: $e');
      rethrow;
    }
  }

  /// Reactivate a doctor
  static Future<DoctorItem> activateDoctor(int doctorId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.patch(
        Uri.parse('$baseUrl/doctors/$doctorId/activate'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return DoctorItem.fromJson(
          _parseJsonResponse(response, '/doctors/$doctorId/activate'),
        );
      } else {
        final err = _parseJsonResponse(response, '/doctors/$doctorId/activate');
        throw Exception(err['detail'] ?? 'Failed to activate doctor');
      }
    } catch (e) {
      debugPrint('Error activating doctor: $e');
      rethrow;
    }
  }

  /// Request doctor activation and return a user-facing status message.
  /// Handles immediate activation (200) and pending confirmation (202).
  static Future<String> requestDoctorActivate(int doctorId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.patch(
        Uri.parse('$baseUrl/doctors/$doctorId/activate'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return 'Doctor activated successfully.';
      }
      if (response.statusCode == 202) {
        final data = _parseJsonResponse(
          response,
          '/doctors/$doctorId/activate',
        );
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
        return 'Doctor activation is pending facility confirmation.';
      }

      final err = _parseJsonResponse(response, '/doctors/$doctorId/activate');
      throw Exception(err['detail'] ?? 'Failed to activate doctor');
    } catch (e) {
      debugPrint('Error requesting doctor activation: $e');
      rethrow;
    }
  }

  /// Start a new patient session
  Future<StartSessionResponse> startSession({
    required String language,
    int? patientAge,
    int facilityId = 1,
  }) async {
    try {
      debugPrint('POST $baseUrl/kiosk/start');
      final response = await http.post(
        Uri.parse('$baseUrl/kiosk/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'language': language,
          'patient_age': patientAge,
          'facility_id': facilityId,
        }),
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return StartSessionResponse.fromJson(data);
      } else {
        throw Exception(
          'Failed to start session: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error in startSession: $e');
      throw Exception('Error starting session: $e');
    }
  }

  /// Submit initial audio complaint and get first question
  Future<QuestionResponse> submitInitialAudio({
    required String sessionId,
    required String audioFilePath,
    required String language,
  }) async {
    try {
      debugPrint('POST $baseUrl/kiosk/$sessionId/audio');
      debugPrint('Audio file path: $audioFilePath');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/kiosk/$sessionId/audio'),
      );

      // Use platform-specific multipart file creation
      request.files.add(
        await multipart.createMultipartFile('audio', audioFilePath),
      );
      request.fields['language'] = language;

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return QuestionResponse.fromJson(data);
      } else {
        throw Exception(
          'Failed to submit audio: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error in submitInitialAudio: $e');
      throw Exception('Error submitting audio: $e');
    }
  }

  /// Submit audio answer to a question
  Future<QuestionResponse> submitAnswer({
    required String sessionId,
    required String question,
    required String audioFilePath,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/kiosk/$sessionId/answer'),
      );

      // Use platform-specific multipart file creation
      request.files.add(
        await multipart.createMultipartFile('audio', audioFilePath),
      );
      request.fields['question'] = question;

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return QuestionResponse.fromJson(data);
      } else {
        throw Exception('Failed to submit answer: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error submitting answer: $e');
    }
  }

  /// Finish session and get routing information
  Future<FinishResponse> finishSession({
    required String sessionId,
    String patientName = '',
    String patientPhone = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/kiosk/$sessionId/finish'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'patient_name': patientName,
          'patient_phone': patientPhone,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return FinishResponse.fromJson(data);
      } else {
        throw Exception(
          'Failed to finish session: ${response.statusCode}, body: ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error finishing session: $e');
    }
  }

  /// Check session status
  Future<StatusResponse> getStatus({required String sessionId}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/kiosk/$sessionId/status'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return StatusResponse.fromJson(data);
      } else {
        throw Exception('Failed to get status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error getting status: $e');
    }
  }
}

// Response models
class StartSessionResponse {
  final String sessionId;
  final String greeting;

  StartSessionResponse({required this.sessionId, required this.greeting});

  factory StartSessionResponse.fromJson(Map<String, dynamic> json) {
    return StartSessionResponse(
      sessionId: json['session_id'],
      greeting: json['greeting'],
    );
  }
}

class QuestionResponse {
  final String sessionId;
  final String question;
  final bool coverageComplete;
  final String patientName;
  final String patientPhone;

  QuestionResponse({
    required this.sessionId,
    required this.question,
    required this.coverageComplete,
    this.patientName = '',
    this.patientPhone = '',
  });

  factory QuestionResponse.fromJson(Map<String, dynamic> json) {
    return QuestionResponse(
      sessionId: json['session_id'],
      question: json['question'],
      coverageComplete: json['coverage_complete'],
      patientName: json['patient_name'] ?? '',
      patientPhone: json['patient_phone'] ?? '',
    );
  }
}

class FinishResponse {
  final String sessionId;
  final String patientMessage;
  final String department;
  final String queue;
  final int queueNumber;
  final String locationHint;
  final String urgencyLabel;

  FinishResponse({
    required this.sessionId,
    required this.patientMessage,
    required this.department,
    required this.queue,
    required this.queueNumber,
    required this.locationHint,
    required this.urgencyLabel,
  });

  factory FinishResponse.fromJson(Map<String, dynamic> json) {
    return FinishResponse(
      sessionId: json['session_id'],
      patientMessage: json['patient_message'],
      department: json['department'],
      queue: json['queue'],
      queueNumber: json['queue_number'],
      locationHint: json['location_hint'],
      urgencyLabel: json['urgency_label'],
    );
  }
}

class StatusResponse {
  final String sessionId;
  final String stage;

  StatusResponse({required this.sessionId, required this.stage});

  factory StatusResponse.fromJson(Map<String, dynamic> json) {
    return StatusResponse(sessionId: json['session_id'], stage: json['stage']);
  }
}

// Auth Response Models
class LoginResponse {
  final String accessToken;
  final String tokenType;
  final UserInfo user;

  LoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      accessToken: json['access_token'],
      tokenType: json['token_type'],
      user: UserInfo.fromJson(json['user']),
    );
  }
}

class UserInfo {
  final int userId;
  final String email;
  final String fullName;
  final String role;
  final int? facilityId;
  final String? specialty;

  UserInfo({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    this.facilityId,
    this.specialty,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      userId: json['user_id'],
      email: json['email'],
      fullName: json['full_name'],
      role: json['role'],
      facilityId: json['facility_id'],
      specialty: json['specialty'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'email': email,
      'full_name': fullName,
      'role': role,
      'facility_id': facilityId,
      'specialty': specialty,
    };
  }
}

// Patient Response Models
class PatientListItem {
  final int patientId;
  final String fullName;
  final String? phoneNumber;
  final String? residency;
  final int? age;
  final String? priority;
  final int? sessionId;
  final String? startTime;
  final int? queueNumber;
  final String? queueStatus;

  PatientListItem({
    required this.patientId,
    required this.fullName,
    this.phoneNumber,
    this.residency,
    this.age,
    this.priority,
    this.sessionId,
    this.startTime,
    this.queueNumber,
    this.queueStatus,
  });

  factory PatientListItem.fromJson(Map<String, dynamic> json) {
    return PatientListItem(
      patientId: json['patient_id'],
      fullName: json['full_name'],
      phoneNumber: json['phone_number'] ?? json['patient_phone'],
      residency: json['residency'],
      age: json['age'] as int?,
      priority: json['priority'],
      sessionId: json['session_id'],
      startTime: json['start_time'],
      queueNumber: json['queue_number'],
      queueStatus: json['queue_status'],
    );
  }
}

class PatientDetail {
  final int patientId;
  final String fullName;
  final String phoneNumber;
  final String preferredLanguage;
  final String? location;
  final String createdAt;

  PatientDetail({
    required this.patientId,
    required this.fullName,
    required this.phoneNumber,
    required this.preferredLanguage,
    this.location,
    required this.createdAt,
  });

  factory PatientDetail.fromJson(Map<String, dynamic> json) {
    return PatientDetail(
      patientId: json['patient_id'],
      fullName: json['full_name'],
      phoneNumber: json['phone_number'],
      preferredLanguage: json['preferred_language'],
      location: json['location'],
      createdAt: json['created_at'],
    );
  }
}

class SessionSummary {
  final int sessionId;
  final String startTime;
  final String? predictedCondition;
  final String? riskLevel;
  final bool prescribed;

  SessionSummary({
    required this.sessionId,
    required this.startTime,
    this.predictedCondition,
    this.riskLevel,
    required this.prescribed,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      sessionId: json['session_id'],
      startTime: json['start_time'],
      predictedCondition: json['predicted_condition'],
      riskLevel: json['risk_level'],
      prescribed: json['prescribed'],
    );
  }
}

class SessionDetail {
  final int sessionId;
  final int patientId;
  final String startTime;
  final String? endTime;
  final String status;
  final String? detectedLanguage;
  final String? fullTranscript;
  final double? transcriptConfidence;
  final Map<String, dynamic>? extractionData;
  final Map<String, dynamic>? scoreData;
  final String? patientMessage;
  final Map<String, dynamic>? doctorBrief;
  final List<Map<String, dynamic>> conversation;
  final List<Map<String, dynamic>> symptoms;
  final Map<String, dynamic>? prediction;
  final List<Map<String, dynamic>> audioRecordings;

  SessionDetail({
    required this.sessionId,
    required this.patientId,
    required this.startTime,
    this.endTime,
    required this.status,
    this.detectedLanguage,
    this.fullTranscript,
    this.transcriptConfidence,
    this.extractionData,
    this.scoreData,
    this.patientMessage,
    this.doctorBrief,
    required this.conversation,
    required this.symptoms,
    this.prediction,
    required this.audioRecordings,
  });

  factory SessionDetail.fromJson(Map<String, dynamic> json) {
    return SessionDetail(
      sessionId: json['session_id'],
      patientId: json['patient_id'],
      startTime: json['start_time'],
      endTime: json['end_time'],
      status: json['status'],
      detectedLanguage: json['detected_language'],
      fullTranscript: json['full_transcript'],
      transcriptConfidence: (json['transcript_confidence'] as num?)?.toDouble(),
      extractionData: json['extraction_data'],
      scoreData: json['score_data'],
      patientMessage: json['patient_message'],
      doctorBrief: json['doctor_brief'],
      conversation: List<Map<String, dynamic>>.from(json['conversation'] ?? []),
      symptoms: List<Map<String, dynamic>>.from(json['symptoms'] ?? []),
      prediction: json['prediction'],
      audioRecordings: List<Map<String, dynamic>>.from(
        json['audio_recordings'] ?? [],
      ),
    );
  }
}

// Room Response Models
class RoomResponse {
  final int roomId;
  final int facilityId;
  final String roomName;
  final String roomType;
  final String status;
  final int? floorNumber;
  final int capacity;
  final DateTime? createdAt;

  RoomResponse({
    required this.roomId,
    required this.facilityId,
    required this.roomName,
    required this.roomType,
    required this.status,
    this.floorNumber,
    required this.capacity,
    this.createdAt,
  });

  factory RoomResponse.fromJson(Map<String, dynamic> json) {
    return RoomResponse(
      roomId: json['room_id'],
      facilityId: json['facility_id'],
      roomName: json['room_name'],
      roomType: json['room_type'],
      status: json['status'],
      floorNumber: json['floor_number'],
      capacity: json['capacity'],
      createdAt: _parseOptionalDateTime(json['created_at']),
    );
  }
}

DateTime? _parseOptionalDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

// Facility Models
class FacilityItem {
  final int facilityId;
  final String name;
  final String primaryEmail;
  final String primaryPhone;
  final String location;
  final int? adminUserId;
  final String? adminName;
  final int totalDoctors;
  final int totalRooms;
  final int activeRooms;
  final bool isActive;
  final DateTime? createdAt;

  FacilityItem({
    required this.facilityId,
    required this.name,
    required this.primaryEmail,
    required this.primaryPhone,
    required this.location,
    this.adminUserId,
    this.adminName,
    required this.totalDoctors,
    required this.totalRooms,
    required this.activeRooms,
    required this.isActive,
    this.createdAt,
  });

  factory FacilityItem.fromJson(Map<String, dynamic> json) {
    return FacilityItem(
      facilityId: json['facility_id'],
      name: json['name'],
      primaryEmail: json['primary_email'],
      primaryPhone: json['primary_phone'],
      location: json['location'],
      adminUserId: json['admin_user_id'],
      adminName: json['admin_name'],
      totalDoctors: json['total_doctors'] ?? 0,
      totalRooms: json['total_rooms'] ?? 0,
      activeRooms: json['active_rooms'] ?? 0,
      isActive: json['is_active'] ?? true,
      createdAt: _parseOptionalDateTime(json['created_at']),
    );
  }
}

// Admin User Model
class AdminUserItem {
  final int userId;
  final String email;
  final String fullName;
  final String role;
  final int? facilityId;
  final bool isActive;

  AdminUserItem({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    this.facilityId,
    required this.isActive,
  });

  factory AdminUserItem.fromJson(Map<String, dynamic> json) {
    return AdminUserItem(
      userId: json['user_id'],
      email: json['email'],
      fullName: json['full_name'],
      role: json['role'],
      facilityId: json['facility_id'],
      isActive: json['is_active'] ?? true,
    );
  }
}

// Doctor Model
class DoctorItem {
  final int userId;
  final String email;
  final String fullName;
  final String? specialty;
  final int? facilityId;
  final bool isActive;
  final DateTime? createdAt;

  DoctorItem({
    required this.userId,
    required this.email,
    required this.fullName,
    this.specialty,
    this.facilityId,
    required this.isActive,
    this.createdAt,
  });

  factory DoctorItem.fromJson(Map<String, dynamic> json) {
    return DoctorItem(
      userId: json['user_id'],
      email: json['email'],
      fullName: json['full_name'],
      specialty: json['specialty'],
      facilityId: json['facility_id'],
      isActive: json['is_active'] ?? true,
      createdAt: _parseOptionalDateTime(json['created_at']),
    );
  }
}

class SystemUserItem {
  final int userId;
  final String email;
  final String fullName;
  final String role;
  final int? facilityId;
  final String? specialty;
  final bool isActive;
  final DateTime? createdAt;

  SystemUserItem({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    this.facilityId,
    this.specialty,
    required this.isActive,
    this.createdAt,
  });

  factory SystemUserItem.fromJson(Map<String, dynamic> json) {
    return SystemUserItem(
      userId: json['user_id'],
      email: json['email'],
      fullName: json['full_name'],
      role: json['role'],
      facilityId: json['facility_id'],
      specialty: json['specialty'],
      isActive: json['is_active'] ?? true,
      createdAt: _parseOptionalDateTime(json['created_at']),
    );
  }
}
