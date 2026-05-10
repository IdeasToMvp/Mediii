class PrescriptionMedication {
  PrescriptionMedication({
    required this.name,
    this.dosage,
    this.frequency,
    this.duration,
    this.instructions,
  });

  final String name;
  final String? dosage;
  final String? frequency;
  final String? duration;
  final String? instructions;

  factory PrescriptionMedication.fromJson(dynamic json) {
    final m = Map<String, dynamic>.from(json as Map);
    return PrescriptionMedication(
      name: (m['name'] ?? '').toString(),
      dosage: _str(m['dosage']),
      frequency: _str(m['frequency']),
      duration: _str(m['duration']),
      instructions: _str(m['instructions']),
    );
  }

  Map<String, dynamic> toApiMap() => {
        'name': name,
        'dosage': dosage,
        'frequency': frequency,
        'duration': duration,
        'instructions': instructions,
      };

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

class Prescription {
  Prescription({
    required this.id,
    required this.source,
    this.title,
    this.patientName,
    this.doctorName,
    this.prescriptionDate,
    this.diagnosis,
    this.generalInstructions,
    this.extractionNotes,
    required this.medications,
    this.rawAnalysis,
    required this.createdAt,
  });

  final String id;
  final String source;
  final String? title;
  final String? patientName;
  final String? doctorName;
  final String? prescriptionDate;
  final String? diagnosis;
  final String? generalInstructions;
  final String? extractionNotes;
  final List<Map<String, dynamic>> medications;
  final Map<String, dynamic>? rawAnalysis;
  final DateTime? createdAt;

  factory Prescription.fromJson(Map<String, dynamic> m) {
    final medsDynamic = m['medications'];
    final medsList = medsDynamic is List
        ? medsDynamic.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    return Prescription(
      id: m['id'].toString(),
      source: (m['source'] ?? '').toString(),
      title: _opt(m['title']),
      patientName: _opt(m['patient_name']),
      doctorName: _opt(m['doctor_name']),
      prescriptionDate: _opt(m['prescription_date']),
      diagnosis: _opt(m['diagnosis']),
      generalInstructions: _opt(m['general_instructions']),
      extractionNotes: _opt(m['extraction_notes']),
      medications: medsList,
      rawAnalysis: m['raw_analysis'] is Map ? Map<String, dynamic>.from(m['raw_analysis'] as Map) : null,
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
    );
  }

  static String? _opt(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
