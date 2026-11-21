/// Represents a competitive or job examination application record.
class ExamApplication {
  final String id;
  final String postName;
  final String organization;
  final String userId;
  final String password;
  final String? rollNo;
  final String? trackingNo;
  final String? portalUrl;
  final double? feeAmount;
  final bool isPaid;
  final String? transactionId;
  final String? rawSms;
  final String? applicantCopyPdfPath;
  final String? admitCardPdfPath;
  final String status; // 'applied', 'paid', 'admitIssued', 'examScheduled', 'completed', 'passed'
  final DateTime? applicationDate;
  final DateTime? examDate;
  final String? examTime;
  final String? venueAndSeat;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ExamApplication({
    required this.id,
    required this.postName,
    required this.organization,
    required this.userId,
    required this.password,
    this.rollNo,
    this.trackingNo,
    this.portalUrl,
    this.feeAmount,
    this.isPaid = true,
    this.transactionId,
    this.rawSms,
    this.applicantCopyPdfPath,
    this.admitCardPdfPath,
    this.status = 'applied',
    this.applicationDate,
    this.examDate,
    this.examTime,
    this.venueAndSeat,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  String get statusLabelBn {
    switch (status) {
      case 'paid':
        return 'ফি পরিশোধিত';
      case 'admitIssued':
        return 'অ্যাডমিট এসেছে 🎟️';
      case 'examScheduled':
        return 'তারিখ নির্ধারিত ⏳';
      case 'completed':
        return 'পরীক্ষা সম্পন্ন ✓';
      case 'passed':
        return 'উত্তীর্ণ / ভাইভা 🏆';
      case 'applied':
      default:
        return 'আবেদন সম্পন্ন';
    }
  }

  /// Returns days remaining until exam, or null if examDate is not set.
  int? get daysUntilExam {
    if (examDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exam = DateTime(examDate!.year, examDate!.month, examDate!.day);
    return exam.difference(today).inDays;
  }

  bool get hasApplicantCopy =>
      applicantCopyPdfPath != null && applicantCopyPdfPath!.isNotEmpty;

  bool get hasAdmitCard =>
      admitCardPdfPath != null && admitCardPdfPath!.isNotEmpty;

  ExamApplication copyWith({
    String? id,
    String? postName,
    String? organization,
    String? userId,
    String? password,
    String? rollNo,
    String? trackingNo,
    String? portalUrl,
    double? feeAmount,
    bool? isPaid,
    String? transactionId,
    String? rawSms,
    String? applicantCopyPdfPath,
    bool clearApplicantCopy = false,
    String? admitCardPdfPath,
    bool clearAdmitCard = false,
    String? status,
    DateTime? applicationDate,
    DateTime? examDate,
    bool clearExamDate = false,
    String? examTime,
    String? venueAndSeat,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExamApplication(
      id: id ?? this.id,
      postName: postName ?? this.postName,
      organization: organization ?? this.organization,
      userId: userId ?? this.userId,
      password: password ?? this.password,
      rollNo: rollNo ?? this.rollNo,
      trackingNo: trackingNo ?? this.trackingNo,
      portalUrl: portalUrl ?? this.portalUrl,
      feeAmount: feeAmount ?? this.feeAmount,
      isPaid: isPaid ?? this.isPaid,
      transactionId: transactionId ?? this.transactionId,
      rawSms: rawSms ?? this.rawSms,
      applicantCopyPdfPath: clearApplicantCopy
          ? null
          : (applicantCopyPdfPath ?? this.applicantCopyPdfPath),
      admitCardPdfPath:
          clearAdmitCard ? null : (admitCardPdfPath ?? this.admitCardPdfPath),
      status: status ?? this.status,
      applicationDate: applicationDate ?? this.applicationDate,
      examDate: clearExamDate ? null : (examDate ?? this.examDate),
      examTime: examTime ?? this.examTime,
      venueAndSeat: venueAndSeat ?? this.venueAndSeat,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'postName': postName,
        'organization': organization,
        'userId': userId,
        'password': password,
        'rollNo': rollNo,
        'trackingNo': trackingNo,
        'portalUrl': portalUrl,
        'feeAmount': feeAmount,
        'isPaid': isPaid,
        'transactionId': transactionId,
        'rawSms': rawSms,
        'applicantCopyPdfPath': applicantCopyPdfPath,
        'admitCardPdfPath': admitCardPdfPath,
        'status': status,
        'applicationDate': applicationDate?.toIso8601String(),
        'examDate': examDate?.toIso8601String(),
        'examTime': examTime,
        'venueAndSeat': venueAndSeat,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ExamApplication.fromJson(Map<String, dynamic> json) =>
      ExamApplication(
        id: json['id'] as String,
        postName: json['postName'] as String? ?? '',
        organization: json['organization'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        password: json['password'] as String? ?? '',
        rollNo: json['rollNo'] as String?,
        trackingNo: json['trackingNo'] as String?,
        portalUrl: json['portalUrl'] as String?,
        feeAmount: (json['feeAmount'] as num?)?.toDouble(),
        isPaid: json['isPaid'] as bool? ?? true,
        transactionId: json['transactionId'] as String?,
        rawSms: json['rawSms'] as String?,
        applicantCopyPdfPath: json['applicantCopyPdfPath'] as String?,
        admitCardPdfPath: json['admitCardPdfPath'] as String?,
        status: json['status'] as String? ?? 'applied',
        applicationDate: json['applicationDate'] != null
            ? DateTime.tryParse(json['applicationDate'] as String)
            : null,
        examDate: json['examDate'] != null
            ? DateTime.tryParse(json['examDate'] as String)
            : null,
        examTime: json['examTime'] as String?,
        venueAndSeat: json['venueAndSeat'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
      );
}
