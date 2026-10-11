import 'package:flutter/material.dart';

const Color _green = Color(0xFF8B9E3A);

void showTermsOfService(BuildContext context) {
  _showLegalDialog(
    context: context,
    title: 'Terms of Service',
    sections: const [
      _LegalSection(
        heading: '1. Authorized Use',
        body:
            'Access to Eleza is restricted to credentialed healthcare professionals and authorized administrative staff employed by or contracted with a registered facility on the platform. '
            'You are granted access solely for clinical and administrative purposes within your assigned role (Doctor, Hospital Admin, or Platform Admin). '
            'Any use outside the scope of your role, including accessing records you have no clinical or administrative need to review, is strictly prohibited.',
      ),
      _LegalSection(
        heading: '2. Account & Credential Security',
        body:
            'Your login credentials are personal and non-transferable. You must not share your password with any other person. '
            'You are fully responsible for all activity that occurs under your account. '
            'If you suspect that your credentials have been compromised, you must report this to your facility administrator immediately and change your password without delay.',
      ),
      _LegalSection(
        heading: '3. Patient Data Confidentiality',
        body:
            'All patient information accessible through Eleza — including pre-consultation summaries, voice transcripts, triage scores, and personal identifiers — is confidential health data. '
            'You are bound by professional confidentiality obligations and by applicable law not to disclose, copy, or transmit patient data outside of the platform except as required for direct patient care or lawful reporting obligations. '
            'Unauthorized disclosure of patient data may result in disciplinary action, suspension of platform access, and legal liability.',
      ),
      _LegalSection(
        heading: '4. Nature of Eleza\'s AI Assistance',
        body:
            'Eleza provides AI-assisted pre-consultation summaries, triage priority scores, and symptom briefs as decision-support tools only. '
            'These outputs do not constitute medical diagnoses or clinical recommendations. '
            'All clinical decisions, diagnoses, prescriptions, and treatment plans remain the sole professional and legal responsibility of the licensed healthcare provider. '
            'You must apply your clinical judgment to every case and must not rely on Eleza\'s outputs as a substitute for professional assessment.',
      ),
      _LegalSection(
        heading: '5. Accuracy of Information',
        body:
            'You agree to ensure that any information you enter or update within the platform — including patient notes, room assignments, and doctor profiles — is accurate to the best of your knowledge. '
            'Deliberately entering false or misleading information is a violation of these Terms and may constitute a reportable professional conduct issue.',
      ),
      _LegalSection(
        heading: '6. Security Incidents',
        body:
            'You must report any suspected security incidents, data breaches, or unauthorized access to patient data to your facility administrator and to the Eleza platform team as soon as possible after becoming aware of the incident. '
            'Do not attempt to investigate or remediate a security incident on your own without authorization.',
      ),
      _LegalSection(
        heading: '7. Acceptable Use',
        body:
            'You must not attempt to reverse-engineer, tamper with, or circumvent any security or access control mechanisms of the platform. '
            'You must not use Eleza to process data unrelated to its intended clinical and administrative purpose. '
            'Any automated scraping, bulk data extraction, or integration not authorized in writing by the platform team is prohibited.',
      ),
      _LegalSection(
        heading: '8. Suspension & Termination',
        body:
            'Eleza reserves the right to suspend or terminate your access at any time in the event of a breach of these Terms, at the request of your facility administrator, or for legitimate operational or security reasons. '
            'Upon termination, your obligation to maintain the confidentiality of patient data continues indefinitely.',
      ),
      _LegalSection(
        heading: '9. Changes to These Terms',
        body:
            'These Terms may be updated periodically. You will be notified of material changes upon your next login. '
            'Continued use of the platform after notification constitutes acceptance of the revised Terms.',
      ),
      _LegalSection(
        heading: '10. Governing Law',
        body:
            'These Terms are governed by the laws of the Republic of Rwanda, including but not limited to Law No. 058/2021 of 13/10/2021 on the Protection of Personal Data and Privacy, and applicable healthcare regulations issued by the Rwanda Biomedical Centre (RBC) and the Ministry of Health.',
      ),
    ],
  );
}

void showPrivacyPolicy(BuildContext context) {
  _showLegalDialog(
    context: context,
    title: 'Privacy Policy',
    sections: const [
      _LegalSection(
        heading: 'Overview',
        body:
            'This Privacy Policy explains how Eleza collects, uses, stores, and protects information in connection with your use of the platform as a healthcare provider or administrator. '
            'Eleza is committed to responsible data stewardship in accordance with Rwanda\'s Law No. 058/2021 on the Protection of Personal Data and Privacy.',
      ),
      _LegalSection(
        heading: '1. Information We Collect About You',
        body:
            'When you use Eleza as a provider or administrator, we collect:\n'
            '• Account information: your name, email address, role, and facility association.\n'
            '• Authentication data: login timestamps, session tokens, and device configuration type.\n'
            '• Activity logs: actions you take within the platform (e.g., viewing a patient brief, updating a room, managing a doctor account) for audit and security purposes.',
      ),
      _LegalSection(
        heading: '2. Patient Data You Access',
        body:
            'In the course of your work, you will access patient-generated data including voice transcription texts, symptom summaries, triage priority scores, and session metadata. '
            'This data is collected from patients via the kiosk interface and processed using AI models to support your clinical workflow. '
            'You access this data as a data processor under your facility\'s data controller responsibilities. '
            'Eleza does not use patient clinical data for any purpose other than delivering the pre-consultation service to your facility.',
      ),
      _LegalSection(
        heading: '3. How We Use Your Information',
        body:
            'Your account and activity information is used to:\n'
            '• Authenticate you and enforce role-based access controls.\n'
            '• Maintain audit trails for security, compliance, and incident response.\n'
            '• Send you system notifications (e.g., account credentials via email).\n'
            '• Improve platform performance and reliability.\n'
            'We do not use your personal information for marketing or sell it to third parties.',
      ),
      _LegalSection(
        heading: '4. Data Storage & Security',
        body:
            'All data is stored in a PostgreSQL database hosted in a secured environment. '
            'Passwords are stored as salted bcrypt hashes and are never stored or transmitted in plain text. '
            'Access tokens are short-lived JWTs. Communications between the app and the server use encrypted connections. '
            'Access to the database is restricted to authorized backend processes only.',
      ),
      _LegalSection(
        heading: '5. Data Retention',
        body:
            'Your account data is retained for as long as your account is active or as required by law. '
            'Patient session data is retained in accordance with applicable Rwandan health records regulations. '
            'Audit logs are retained for a minimum period required for regulatory compliance. '
            'Upon account deactivation, personal account data may be anonymized or deleted at the request of your facility administrator.',
      ),
      _LegalSection(
        heading: '6. Sharing of Information',
        body:
            'Your data and patient data accessible through Eleza are not shared with third parties except:\n'
            '• Where required by Rwandan law or a lawful order from a competent authority.\n'
            '• With your facility administrator for account management purposes.\n'
            '• With third-party service providers (e.g., cloud infrastructure, email delivery) who are contractually bound to process data only on our instructions and in compliance with applicable law.\n'
            'AI processing (speech transcription and clinical NLP) is performed using third-party model providers (Google Gemini, OpenAI Whisper). Only de-identified or session-specific data necessary for the task is transmitted.',
      ),
      _LegalSection(
        heading: '7. Your Rights',
        body:
            'Under Rwandan data protection law, you have the right to:\n'
            '• Access the personal data we hold about you.\n'
            '• Request correction of inaccurate personal data.\n'
            '• Request deletion of your personal data where it is no longer necessary.\n'
            '• Object to processing in certain circumstances.\n'
            'To exercise these rights, contact your facility administrator or the Eleza platform team.',
      ),
      _LegalSection(
        heading: '8. Cookies & Local Storage',
        body:
            'The Eleza mobile/desktop application uses local device storage (SharedPreferences) solely to persist your session token and, if you enable "Remember me", your email address for convenience. '
            'No tracking cookies or third-party analytics scripts are used.',
      ),
      _LegalSection(
        heading: '9. Changes to This Policy',
        body:
            'This Privacy Policy may be updated to reflect changes in law or platform functionality. '
            'You will be notified of material changes upon your next login. Continued use constitutes acceptance.',
      ),
      _LegalSection(
        heading: '10. Contact',
        body:
            'For questions about this Privacy Policy or a data subject rights request, please contact your facility administrator or reach the Eleza platform team through your facility\'s designated support channel.',
      ),
    ],
  );
}

// ─── Internal helpers ────────────────────────────────────────────────────────

class _LegalSection {
  final String heading;
  final String body;
  const _LegalSection({required this.heading, required this.body});
}

void _showLegalDialog({
  required BuildContext context,
  required String title,
  required List<_LegalSection> sections,
}) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                color: Color(0xFFF0F4E8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined,
                      color: _green, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                    color: Colors.grey[600],
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final section in sections) ...[
                      Text(
                        section.heading,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        section.body,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
              child: SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
