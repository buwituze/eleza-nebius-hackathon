# Patient Detail Page - Documentation

This document describes the new Patient Detail Page and its reusable components built according to the Figma design.

## Overview

The Patient Detail Page is a comprehensive view for doctors, hospital admins, and platform admins to view detailed patient information from a consultation session. The page follows a specific layout with a navbar, sidebar, and 4-card grid layout.

## Architecture

### Models (`lib/models/patient_model.dart`)

#### Patient

- `patientId`: Unique identifier
- `fullName`: Patient's full name
- `phoneNumber`: Contact number
- `location`: Residency location
- `age`: Patient age
- `createdAt`: Account creation date
- `lastVisit`: Last consultation date
- `priorityLevel`: 'high' (red), 'medium' (gold), 'low' (green)

#### PatientSession

- `sessionId`: Unique session ID
- `patientId`: Associated patient ID
- `startTime`: Session start time
- `endTime`: Session end time
- `status`: 'active', 'awaiting_review', 'completed'
- `predictionLabel`: Predicted diagnosis
- `predictionConfidence`: Confidence score (0-1)

#### PatientBrief

Data from Model F (Doctor Summary):

- `narrativeSummary`: 2-4 sentence clinical summary
- `keyFindings`: List of important findings
- `redFlagNote`: Warning if applicable
- `chiefComplaint`: Primary complaint
- `bodyPart`: Affected body part
- `duration`: Symptom duration
- `severity`: Severity level
- `associatedSymptoms`: Related symptoms
- `riskFactors`: Risk factors identified
- `suspectedIssue`: Predicted condition
- `confidenceScore`: Confidence of prediction
- `priority`: Priority level

#### ConversationData

- `sessionId`: Associated session
- `messages`: List of conversation messages
- `audioUrl`: URL to audio recording
- `transcriptUrl`: URL to transcript
- `clarificationQuestions`: Questions asked during session

### Components

#### 1. AppNavBar (`lib/components/app_navbar.dart`)

Reusable navigation bar component.

**Features:**

- Logo/home button
- Navigation menu items
- User profile display with avatar
- Settings button
- Light, clean design matching Figma

**Usage:**

```dart
AppNavBar(
  currentUserName: 'Dr. Ingarire Yvette',
  currentUserRole: 'doctor',
  navItems: [
    NavBarItem(label: 'All Patients', onTap: () {}),
    NavBarItem(label: 'Rooms', onTap: () {}),
  ],
  activeItem: 'All Patients',
  onSettingsTap: () {},
)
```

#### 2. PatientSidebar (`lib/components/patient_sidebar.dart`)

Patient list sidebar with search and priority indicators.

**Features:**

- Displays all patients sorted by most recent first
- Color-coded priority dots (red=high, gold=medium, green=low)
- Search functionality
- Patient phone number display
- Eye icon for visibility toggle
- Active patient highlighting

**Usage:**

```dart
PatientSidebar(
  patients: patientList,
  selectedPatient: currentPatient,
  onPatientSelected: (patient) {},
  isAdmin: isPlatformAdmin,
)
```

#### 3. DoctorsBriefCard (`lib/components/doctors_brief_card.dart`)

Top-left card: Chief complaint and clinical findings.

**Displays:**

- Chief complaint
- Visitation date/duration
- Body part affected
- Severity level
- Associated symptoms (as chips)
- Red flag warnings (if any)
- Suspected issue with confidence score
- Priority badge

**Usage:**

```dart
DoctorsBriefCard(brief: patientBrief)
```

#### 4. PatientPersonalDataCard (`lib/components/patient_personal_data_card.dart`)

Top-right card: Patient demographics and personal information.

**Displays:**

- Full name
- Age
- Phone number
- Residency location
- Visitation date (from session)
- Visitation time
- Session duration

**Usage:**

```dart
PatientPersonalDataCard(
  patient: selectedPatient,
  session: selectedSession,
)
```

#### 5. SymptomsAnalysisCard (`lib/components/symptoms_analysis_card.dart`)

Bottom-left card: Analysis and visualization of symptoms linked to suspected issue.

**Displays:**

- Connection visualization between symptoms and predicted issue
- Supporting symptoms list
- Key clinical indicators
- Confidence score with visual progress bar
- Risk factors (as categorized chips)

**Usage:**

```dart
SymptomsAnalysisCard(
  brief: patientBrief,
  session: selectedSession,
)
```

#### 6. ConversationDataCard (`lib/components/conversation_data_card.dart`)

Bottom-right card: Conversation audio, Q&A, and raw transcription.

**Features:**

- Expandable audio player section
- Expandable clarification questions with numbering
- Expandable raw transcription
- Play controls for audio with progress bar
- Time indicators

**Usage:**

```dart
ConversationDataCard(
  conversationData: conversationData,
  clarificationQuestions: questionsList,
  transcriptText: fullTranscript,
)
```

### Main Page

#### PatientDetailPage (`lib/screens/patient_detail_page.dart`)

Main page orchestrating all components.

**Features:**

- Role-based access control:
  - **Doctors/Hospital Admins**: Can see "Assign Room" button
  - **Platform Admins**: View-only, no action buttons
- 2x2 grid layout for cards
- Responsive design
- Mock data for demonstration
- Header with patient name and session time

**Constructor Parameters:**

```dart
PatientDetailPage(
  userRole: 'doctor', // 'doctor', 'hospital_admin', or 'platform_admin'
  userName: 'Dr. Ingarire Yvette',
)
```

## Usage in App

### Navigate to Patient Detail Page (Doctor View)

```dart
Navigator.pushNamed(context, '/patient-detail');
```

### Navigate to Patient Detail Page (Admin View)

```dart
Navigator.pushNamed(context, '/patient-detail-admin');
```

### Direct Navigation

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const PatientDetailPage(
      userRole: 'doctor',
      userName: 'Dr. Name',
    ),
  ),
);
```

## Styling & Design

- **Color Palette:**
  - Primary: Blue (#0066FF)
  - Accent: Gold (#8B9E3A)
  - Red: #FF0000 (high priority)
  - Gold: #FFC107 (medium priority)
  - Green: #4CAF50 (low priority)

- **Typography:**
  - Headers: 16-20px, Weight 700
  - Body: 12-14px, Weight 500-600
  - Small text: 11-12px, Weight 400-500

- **Card Design:**
  - Rounded corners: 12px
  - Elevation: 2
  - Padding: 20px

## Integration with Backend

To integrate with your actual API:

1. Update `_loadPatientData()` in `PatientDetailPage` to call your API endpoints
2. Replace mock data initialization with actual API calls
3. Update models to match your backend response structure

**Example API Integration Points:**

```dart
// Get patient list
GET /patients

// Get patient details
GET /patients/{patientId}

// Get session data
GET /sessions/{sessionId}

// Get doctor brief (Model F)
GET /sessions/{sessionId}/brief

// Get conversation data
GET /sessions/{sessionId}/conversation

// Assign room
POST /patients/{patientId}/assign-room
```

## Accessibility Features

- Color-coded priority levels for quick visual identification
- Clear hierarchical information layout
- Expandable sections for conversation data
- Responsive design that works on different screen sizes

## Future Enhancements

1. Add export/print functionality for patient reports
2. Integrate real-time audio playback for conversation audio
3. Add search and filter capabilities
4. Implement real-time updates for active sessions
5. Add notes/annotations feature for doctors
6. Implement session history view

## Troubleshooting

### Missing Mock Data

If data doesn't appear, ensure `_initializeMockData()` is called in `initState()`.

### Component Not Rendering

- Check that the parent widget is a `Scaffold`
- Verify component imports are correct
- Check for null values in model data

### Navigation Issues

- Ensure routes are correctly defined in `main.dart`
- Check that route names match when using `pushNamed()`

## File Structure

```
lib/
├── models/
│   └── patient_model.dart          # Data models
├── components/
│   ├── index.dart                  # Component exports
│   ├── app_navbar.dart             # Navigation bar
│   ├── patient_sidebar.dart        # Patient list
│   ├── doctors_brief_card.dart     # Chief findings
│   ├── patient_personal_data_card.dart  # Personal info
│   ├── symptoms_analysis_card.dart # Analysis/charts
│   └── conversation_data_card.dart # Audio/transcript
└── screens/
    └── patient_detail_page.dart    # Main page
```

## Contact & Support

For questions or issues with the Patient Detail Page components, refer to the Figma design reference or contact the development team.
