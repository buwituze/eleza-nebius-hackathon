class Patient {
  final int patientId;
  final String fullName;
  final String phoneNumber;
  final String? location;
  final int? age;
  final DateTime createdAt;
  final DateTime? lastVisit;
  final String priorityLevel; // 'high', 'medium', 'low'

  Patient({
    required this.patientId,
    required this.fullName,
    required this.phoneNumber,
    this.location,
    this.age,
    required this.createdAt,
    this.lastVisit,
    this.priorityLevel = 'low',
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      patientId: json['patient_id'] ?? 0,
      fullName: json['full_name'] ?? '',
      phoneNumber: json['phone_number'] ?? '',
      location: json['location'],
      age: json['age'],
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
      lastVisit:
          json['last_visit'] != null
              ? DateTime.parse(json['last_visit'])
              : null,
      priorityLevel: json['priority_level'] ?? 'low',
    );
  }
}

class PatientSession {
  final int sessionId;
  final int patientId;
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // 'active', 'awaiting_review', 'completed'
  final String? predictionLabel;
  final double? predictionConfidence;

  PatientSession({
    required this.sessionId,
    required this.patientId,
    required this.startTime,
    this.endTime,
    required this.status,
    this.predictionLabel,
    this.predictionConfidence,
  });

  factory PatientSession.fromJson(Map<String, dynamic> json) {
    return PatientSession(
      sessionId: json['session_id'] ?? 0,
      patientId: json['patient_id'] ?? 0,
      startTime:
          json['start_time'] != null
              ? DateTime.parse(json['start_time'])
              : DateTime.now(),
      endTime:
          json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      status: json['status'] ?? 'active',
      predictionLabel: json['prediction_label'],
      predictionConfidence: (json['prediction_confidence'] as num?)?.toDouble(),
    );
  }
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
  final double confidenceScore;
  final String priority;

  PatientBrief({
    required this.narrativeSummary,
    required this.keyFindings,
    required this.redFlagNote,
    required this.chiefComplaint,
    this.bodyPart,
    this.duration,
    this.severity,
    this.associatedSymptoms = const [],
    this.riskFactors = const [],
    this.suspectedIssue,
    this.confidenceScore = 0.0,
    this.priority = 'low',
  });

  factory PatientBrief.fromJson(Map<String, dynamic> json) {
    return PatientBrief(
      narrativeSummary: json['narrative_summary'] ?? '',
      keyFindings: List<String>.from(json['key_findings'] ?? []),
      redFlagNote: json['red_flag_note'] ?? '',
      chiefComplaint: json['chief_complaint'] ?? '',
      bodyPart: json['body_part'],
      duration: json['duration'],
      severity: json['severity'],
      associatedSymptoms: List<String>.from(json['associated_symptoms'] ?? []),
      riskFactors: List<String>.from(json['risk_factors'] ?? []),
      suspectedIssue: json['suspected_issue'],
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      priority: json['priority'] ?? 'low',
    );
  }
}

class ConversationData {
  final int sessionId;
  final List<ConversationMessage> messages;
  final String? audioUrl;
  final String? transcriptUrl;
  final List<String> clarificationQuestions;

  ConversationData({
    required this.sessionId,
    required this.messages,
    this.audioUrl,
    this.transcriptUrl,
    this.clarificationQuestions = const [],
  });

  factory ConversationData.fromJson(Map<String, dynamic> json) {
    var messagesJson = json['messages'] as List? ?? [];
    return ConversationData(
      sessionId: json['session_id'] ?? 0,
      messages:
          messagesJson.map((m) => ConversationMessage.fromJson(m)).toList(),
      audioUrl: json['audio_url'],
      transcriptUrl: json['transcript_url'],
      clarificationQuestions: List<String>.from(
        json['clarification_questions'] ?? [],
      ),
    );
  }
}

class ConversationMessage {
  final int messageId;
  final String senderType; // 'patient' or 'ml_system'
  final String messageText;
  final DateTime timestamp;

  ConversationMessage({
    required this.messageId,
    required this.senderType,
    required this.messageText,
    required this.timestamp,
  });

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      messageId: json['message_id'] ?? 0,
      senderType: json['sender_type'] ?? 'patient',
      messageText: json['message_text'] ?? '',
      timestamp:
          json['timestamp'] != null
              ? DateTime.parse(json['timestamp'])
              : DateTime.now(),
    );
  }
}
