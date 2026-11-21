import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../data/models/exam_application.dart';
import '../../data/services/exam_vault_service.dart';
import '../providers/exam_vault_provider.dart';

class ExamApplicationEditScreen extends ConsumerStatefulWidget {
  final ExamApplication? existingApplication;

  const ExamApplicationEditScreen({super.key, this.existingApplication});

  @override
  ConsumerState<ExamApplicationEditScreen> createState() =>
      _ExamApplicationEditScreenState();
}

class _ExamApplicationEditScreenState
    extends ConsumerState<ExamApplicationEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _postNameController;
  late TextEditingController _organizationController;
  late TextEditingController _userIdController;
  late TextEditingController _passwordController;
  late TextEditingController _rollNoController;
  late TextEditingController _trackingNoController;
  late TextEditingController _portalUrlController;
  late TextEditingController _feeAmountController;
  late TextEditingController _txIdController;
  late TextEditingController _rawSmsController;
  late TextEditingController _venueController;
  late TextEditingController _notesController;

  String _status = 'applied';
  bool _isPaid = true;
  DateTime? _applicationDate;
  DateTime? _examDate;
  TimeOfDay? _examTimeOfDay;

  String? _applicantCopyPath;
  String? _admitCardPath;
  bool _obscurePassword = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final app = widget.existingApplication;

    _postNameController = TextEditingController(text: app?.postName ?? '');
    _organizationController =
        TextEditingController(text: app?.organization ?? '');
    _userIdController = TextEditingController(text: app?.userId ?? '');
    _passwordController = TextEditingController(text: app?.password ?? '');
    _rollNoController = TextEditingController(text: app?.rollNo ?? '');
    _trackingNoController = TextEditingController(text: app?.trackingNo ?? '');
    _portalUrlController = TextEditingController(text: app?.portalUrl ?? '');
    _feeAmountController = TextEditingController(
      text: app?.feeAmount != null ? app!.feeAmount!.toStringAsFixed(0) : '',
    );
    _txIdController = TextEditingController(text: app?.transactionId ?? '');
    _rawSmsController = TextEditingController(text: app?.rawSms ?? '');
    _venueController = TextEditingController(text: app?.venueAndSeat ?? '');
    _notesController = TextEditingController(text: app?.notes ?? '');

    _status = app?.status ?? 'applied';
    _isPaid = app?.isPaid ?? true;
    _applicationDate = app?.applicationDate ?? DateTime.now();
    _examDate = app?.examDate;
    _applicantCopyPath = app?.applicantCopyPdfPath;
    _admitCardPath = app?.admitCardPdfPath;
  }

  @override
  void dispose() {
    _postNameController.dispose();
    _organizationController.dispose();
    _userIdController.dispose();
    _passwordController.dispose();
    _rollNoController.dispose();
    _trackingNoController.dispose();
    _portalUrlController.dispose();
    _feeAmountController.dispose();
    _txIdController.dispose();
    _rawSmsController.dispose();
    _venueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Intelligently parses Post Name, Organization, User ID, Password/PIN, TxID, Fee, and URL from SMS
  void _extractFromSms(String text) {
    if (text.isEmpty) return;

    final extractedFields = <String>[];

    // 1. Post Name and Organization
    final postOrgMatch = RegExp(
      r'(?:completed\s+for|charged\s+for|applied\s+for|received\s+for|fee\s+received\s+for|for)\s+(.+?)(?:\s+post)?\s+of\s+([A-Za-z0-9\s&.-]+?)(?:\s*[\.,]|through|\.|\n|$)',
      caseSensitive: false,
    ).firstMatch(text);

    if (postOrgMatch != null) {
      final post = postOrgMatch.group(1)!.trim();
      final org = postOrgMatch.group(2)!.trim();
      if (_postNameController.text.trim().isEmpty && post.isNotEmpty) {
        _postNameController.text = post;
        extractedFields.add('পদের নাম');
      }
      if (_organizationController.text.trim().isEmpty && org.isNotEmpty) {
        _organizationController.text = org;
        extractedFields.add('প্রতিষ্ঠান');
      }
    } else {
      // Fallback 1: 'for <post>, <org>'
      final postCommaMatch = RegExp(
        r'(?:for)\s+([A-Za-z0-9\s()&.-]+?),\s*([A-Za-z0-9\s()&.-]+?)(?:\.|\n|$)',
        caseSensitive: false,
      ).firstMatch(text);
      if (postCommaMatch != null) {
        final post = postCommaMatch.group(1)!.trim();
        final org = postCommaMatch.group(2)!.trim();
        if (_postNameController.text.trim().isEmpty && post.isNotEmpty) {
          _postNameController.text = post;
          extractedFields.add('পদের নাম');
        }
        if (_organizationController.text.trim().isEmpty && org.isNotEmpty) {
          _organizationController.text = org;
          extractedFields.add('প্রতিষ্ঠান');
        }
      } else {
        // Fallback 2: 'for <Exam/Post>' (e.g. BCS or solitary exam name)
        final postSoloMatch = RegExp(
          r'(?:completed\s+for|charged\s+for|applied\s+for|received\s+for|fee\s+received\s+for|for)\s+([A-Za-z0-9\s()&.-]+?)(?:\.|\n|User|Pass|Roll|$)',
          caseSensitive: false,
        ).firstMatch(text);
        if (postSoloMatch != null) {
          final post = postSoloMatch.group(1)!.trim();
          if (_postNameController.text.trim().isEmpty && post.isNotEmpty) {
            _postNameController.text = post;
            extractedFields.add('পদের নাম');
          }
          if (_organizationController.text.trim().isEmpty) {
            if (post.toLowerCase().contains('bcs')) {
              _organizationController.text = 'BPSC';
              extractedFields.add('প্রতিষ্ঠান');
            }
          }
        }
      }
    }

    // Candidate / Applicant Name
    final nameMatch = RegExp(
          r'(?:Congrats!\s+|Congratulations!\s+)([A-Za-z\s.]+?),\s*(?:payment|fee|User)',
          caseSensitive: false,
        ).firstMatch(text) ??
        RegExp(
          r'(?:^|\n)([A-Za-z\s.]+?),\s*(?:Tk\.?\s*\d|payment|fee)',
          caseSensitive: false,
        ).firstMatch(text.trim());
    if (nameMatch != null && _notesController.text.trim().isEmpty) {
      final candidateName = nameMatch.group(1)!.trim();
      if (candidateName.isNotEmpty) {
        _notesController.text = 'প্রার্থী: $candidateName';
        extractedFields.add('প্রার্থীর নাম');
      }
    }

    // 2. User ID / User:
    final userMatch = RegExp(r'User(?:\s*ID)?[:\s]+([A-Za-z0-9_-]+)',
            caseSensitive: false)
        .firstMatch(text);
    if (userMatch != null && _userIdController.text.trim().isEmpty) {
      _userIdController.text = userMatch.group(1)!.trim();
      extractedFields.add('User ID');
    }

    // 3. Password / Pass / PIN
    final passMatch = RegExp(
            r'(?:Password|Pass)[:\s]+([A-Za-z0-9_@#!]+)',
            caseSensitive: false)
        .firstMatch(text);
    if (passMatch != null && _passwordController.text.trim().isEmpty) {
      _passwordController.text = passMatch.group(1)!.trim();
      extractedFields.add('Password');
    } else {
      final pinMatch = RegExp(
              r'PIN(?:\s*is)?[:\s]+([A-Za-z0-9_@#!]+)',
              caseSensitive: false)
          .firstMatch(text);
      if (pinMatch != null && _passwordController.text.trim().isEmpty) {
        _passwordController.text = pinMatch.group(1)!.trim();
        extractedFields.add('PIN');
      }
    }

    // 4. Tracking ID
    final trackMatch = RegExp(
            r'Tracking(?:\s*ID|No)?[:\s]+([A-Za-z0-9_-]+)',
            caseSensitive: false)
        .firstMatch(text);
    if (trackMatch != null && _trackingNoController.text.trim().isEmpty) {
      _trackingNoController.text = trackMatch.group(1)!.trim();
      extractedFields.add('Tracking No');
    }

    // 5. Fee / Tk.
    final feeMatch = RegExp(
            r'Tk\.?\s*([0-9]+(?:\.[0-9]+)?)',
            caseSensitive: false)
        .firstMatch(text);
    if (feeMatch != null && _feeAmountController.text.trim().isEmpty) {
      _feeAmountController.text = feeMatch.group(1)!.trim();
      extractedFields.add('ফি');
    }

    // 6. Portal URL
    final urlMatch = RegExp(r'(https?://[^\s,]+)', caseSensitive: false)
        .firstMatch(text);
    if (urlMatch != null && _portalUrlController.text.trim().isEmpty) {
      _portalUrlController.text = urlMatch.group(1)!.trim();
      extractedFields.add('ওয়েবসাইট লিঙ্ক');
    }

    // 7. TxID
    final txMatch = RegExp(
            r'(?:TxID|Transaction\s*ID|Txn\s*ID)[:\s]+([A-Za-z0-9_-]+)',
            caseSensitive: false)
        .firstMatch(text);
    if (txMatch != null && _txIdController.text.trim().isEmpty) {
      _txIdController.text = txMatch.group(1)!.trim();
      extractedFields.add('TxID');
    }

    // 8. Roll No
    final rollMatch =
        RegExp(r'Roll(?:\s*No)?[:\s]+([0-9]+)', caseSensitive: false)
            .firstMatch(text);
    if (rollMatch != null && _rollNoController.text.trim().isEmpty) {
      _rollNoController.text = rollMatch.group(1)!.trim();
      extractedFields.add('Roll No');
      setState(() {
        _status = 'admitIssued';
      });
    }

    // 9. Payment Status Auto-Detection
    final lower = text.toLowerCase();
    if (lower.contains('payment completed') || lower.contains('fee received')) {
      setState(() {
        _isPaid = true;
        if (_status == 'applied') {
          _status = 'paid';
        }
      });
    }

    if (extractedFields.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SMS থেকে ${extractedFields.join(", ")} স্বয়ংক্রিয়ভাবে পূরণ হয়েছে!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickPdf(bool isAdmitCard) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
    );

    if (picked.isNotEmpty && picked.first.path != null) {
      setState(() {
        if (isAdmitCard) {
          _admitCardPath = picked.first.path;
          if (_status == 'applied' || _status == 'paid') {
            _status = 'admitIssued';
          }
        } else {
          _applicantCopyPath = picked.first.path;
        }
      });
    }
  }

  Future<void> _saveApplication() async {
    if (!_formKey.currentState!.validate()) return;

    final formattedTime = _examTimeOfDay != null
        ? _examTimeOfDay!.format(context)
        : widget.existingApplication?.examTime;

    setState(() => _isSaving = true);
    try {
      final examId = widget.existingApplication?.id ??
          'exam_${DateTime.now().millisecondsSinceEpoch}';

      // Copy applicant copy to vault if it's a newly picked local path
      String? savedApplicantPath = _applicantCopyPath;
      if (_applicantCopyPath != null &&
          !_applicantCopyPath!.contains('exam_vault')) {
        savedApplicantPath = await ExamVaultService.instance.copyDocumentToVault(
          sourcePath: _applicantCopyPath!,
          examId: examId,
          docType: 'applicant_copy',
        );
      }

      // Copy admit card to vault if newly picked
      String? savedAdmitPath = _admitCardPath;
      if (_admitCardPath != null && !_admitCardPath!.contains('exam_vault')) {
        savedAdmitPath = await ExamVaultService.instance.copyDocumentToVault(
          sourcePath: _admitCardPath!,
          examId: examId,
          docType: 'admit_card',
        );
      }

      final fee = double.tryParse(_feeAmountController.text.trim());

      final app = ExamApplication(
        id: examId,
        postName: _postNameController.text.trim(),
        organization: _organizationController.text.trim(),
        userId: _userIdController.text.trim(),
        password: _passwordController.text.trim(),
        rollNo: _rollNoController.text.trim().isNotEmpty
            ? _rollNoController.text.trim()
            : null,
        trackingNo: _trackingNoController.text.trim().isNotEmpty
            ? _trackingNoController.text.trim()
            : null,
        portalUrl: _portalUrlController.text.trim().isNotEmpty
            ? _portalUrlController.text.trim()
            : null,
        feeAmount: fee,
        isPaid: _isPaid,
        transactionId: _txIdController.text.trim().isNotEmpty
            ? _txIdController.text.trim()
            : null,
        rawSms: _rawSmsController.text.trim().isNotEmpty
            ? _rawSmsController.text.trim()
            : null,
        applicantCopyPdfPath: savedApplicantPath,
        admitCardPdfPath: savedAdmitPath,
        applicantCopyDriveFileId:
            widget.existingApplication?.applicantCopyDriveFileId,
        admitCardDriveFileId: widget.existingApplication?.admitCardDriveFileId,
        status: _status,
        applicationDate: _applicationDate,
        examDate: _examDate,
        examTime: formattedTime,
        venueAndSeat: _venueController.text.trim().isNotEmpty
            ? _venueController.text.trim()
            : null,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        createdAt: widget.existingApplication?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (widget.existingApplication != null) {
        await ref.read(examVaultProvider.notifier).updateApplication(app);
      } else {
        await ref.read(examVaultProvider.notifier).addApplication(app);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('আবেদন ও ক্রেডেনশিয়াল সফলভাবে সংরক্ষিত হয়েছে!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('সংরক্ষণ ব্যর্থ: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final isEditing = widget.existingApplication != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'আবেদন তথ্য সম্পাদনা' : 'নতুন পরীক্ষা ও আবেদন যোগ'),
        actions: [
          TextButton.icon(
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Save'),
            onPressed: _isSaving ? null : _saveApplication,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(FluentSpacing.l),
          children: [
            // Magic SMS Auto-Fill Box
            Container(
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: isDark ? 0.2 : 0.08),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome,
                              size: 18, color: Colors.blue),
                          const SizedBox(width: FluentSpacing.s),
                          Text(
                            'SMS থেকে দ্রুত অটো-ফিল',
                            style: FluentType.bodyStrong.copyWith(
                              color: isDark ? Colors.blue.shade200 : Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.paste_rounded, size: 14),
                        label: const Text('Paste'),
                        onPressed: () async {
                          final data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          if (data != null && data.text != null) {
                            _rawSmsController.text = data.text!;
                            _extractFromSms(data.text!);
                          }
                        },
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _rawSmsController,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText:
                          'টেলিটক বা ব্যাংক থেকে পাওয়া কনফার্মেশন SMS এখানে পেস্ট করুন...',
                      isDense: true,
                      filled: true,
                      fillColor: isDark ? Colors.black26 : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: FluentRadius.controlBorder,
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => _extractFromSms(val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.l),

            // Section 1: Post & Organization
            Text(
              '১. পরীক্ষা ও প্রতিষ্ঠান',
              style: FluentType.bodyStrong.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: FluentSpacing.s),
            TextFormField(
              controller: _postNameController,
              decoration: const InputDecoration(
                labelText: 'পদের নাম / পরীক্ষার নাম *',
                hintText: 'e.g. 46th BCS, Senior Officer (IT), Assistant Director',
                prefixIcon: Icon(Icons.work_outline),
              ),
              validator: (val) =>
                  (val == null || val.trim().isEmpty) ? 'পদের নাম লিখুন' : null,
            ),
            const SizedBox(height: FluentSpacing.m),
            TextFormField(
              controller: _organizationController,
              decoration: const InputDecoration(
                labelText: 'প্রতিষ্ঠান / মন্ত্রণালয় / বোর্ড *',
                hintText: 'e.g. BPSC, Bangladesh Bank, NSI, Railway',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
              validator: (val) =>
                  (val == null || val.trim().isEmpty) ? 'প্রতিষ্ঠানের নাম লিখুন' : null,
            ),
            const SizedBox(height: FluentSpacing.xl),

            // Section 2: Core Credentials (User ID & Password)
            Text(
              '২. ইউজার আইডি ও পাসওয়ার্ড (Core Credentials)',
              style: FluentType.bodyStrong.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: FluentSpacing.s),
            TextFormField(
              controller: _userIdController,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'User ID / Registration No. *',
                hintText: 'e.g. BBSO98471, BPSC8872',
                prefixIcon: Icon(Icons.person_pin_outlined),
              ),
              validator: (val) =>
                  (val == null || val.trim().isEmpty) ? 'User ID লিখুন' : null,
            ),
            const SizedBox(height: FluentSpacing.m),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Password / PIN *',
                hintText: 'e.g. ABC98XYZ',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (val) =>
                  (val == null || val.trim().isEmpty) ? 'পাসওয়ার্ড লিখুন' : null,
            ),
            const SizedBox(height: FluentSpacing.m),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _rollNoController,
                    decoration: const InputDecoration(
                      labelText: 'Roll Number (যদি থাকে)',
                      hintText: 'e.g. 109823',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: TextFormField(
                    controller: _txIdController,
                    decoration: const InputDecoration(
                      labelText: 'Transaction ID / TxID',
                      hintText: 'e.g. TX987BXZ',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.xl),

            // Section 3: Status & Portal URL
            Text(
              '৩. আবেদনের অবস্থা ও পোর্টাল',
              style: FluentType.bodyStrong.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: FluentSpacing.s),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'আবেদনের বর্তমান অবস্থা',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'applied', child: Text('📝 আবেদন সম্পন্ন (Applied)')),
                DropdownMenuItem(value: 'paid', child: Text('💳 ফি পরিশোধিত (Paid)')),
                DropdownMenuItem(value: 'admitIssued', child: Text('🎟️ অ্যাডমিট এসেছে (Admit Issued)')),
                DropdownMenuItem(value: 'examScheduled', child: Text('⏳ পরীক্ষার তারিখ নির্ধারিত (Exam Scheduled)')),
                DropdownMenuItem(value: 'completed', child: Text('✅ পরীক্ষা সম্পন্ন (Completed)')),
                DropdownMenuItem(value: 'passed', child: Text('🏆 উত্তীর্ণ / ভাইভা (Passed)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _status = val);
              },
            ),
            const SizedBox(height: FluentSpacing.m),
            TextFormField(
              controller: _portalUrlController,
              decoration: const InputDecoration(
                labelText: 'আবেদন / অ্যাডমিট ডাউনলোড ওয়েবসাইট লিঙ্ক',
                hintText: 'e.g. http://bpsc.teletalk.com.bd',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: FluentSpacing.xs),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: const Text('bpsc.teletalk'),
                  onPressed: () => _portalUrlController.text =
                      'http://bpsc.teletalk.com.bd',
                ),
                ActionChip(
                  label: const Text('erecruitment.bb'),
                  onPressed: () => _portalUrlController.text =
                      'https://erecruitment.bb.org.bd',
                ),
                ActionChip(
                  label: const Text('alljobs.teletalk'),
                  onPressed: () => _portalUrlController.text =
                      'http://alljobs.teletalk.com.bd',
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.xl),

            // Section 4: PDF Documents
            Text(
              '৪. ডকুমেন্টস ও পিডিএফ সংরক্ষণ',
              style: FluentType.bodyStrong.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: FluentSpacing.s),
            // Applicant Copy
            _buildFilePickerTile(
              label: 'Applicant Copy (আবেদনপত্র কপি)',
              filePath: _applicantCopyPath,
              icon: Icons.picture_as_pdf_rounded,
              color: Colors.red,
              onPick: () => _pickPdf(false),
              onClear: () => setState(() => _applicantCopyPath = null),
            ),
            const SizedBox(height: FluentSpacing.m),
            // Admit Card
            _buildFilePickerTile(
              label: 'Admit Card (প্রবেশপত্র কপি 🎟️)',
              filePath: _admitCardPath,
              icon: Icons.assignment_ind_rounded,
              color: Colors.teal,
              onPick: () => _pickPdf(true),
              onClear: () => setState(() => _admitCardPath = null),
            ),
            const SizedBox(height: FluentSpacing.xl),

            // Section 5: Exam Schedule & Venue
            Text(
              '৫. পরীক্ষার তারিখ ও সিট প্ল্যান',
              style: FluentType.bodyStrong.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: FluentSpacing.s),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text(
                      _examDate == null
                          ? 'পরীক্ষার তারিখ বাছুন'
                          : '${_examDate!.day}/${_examDate!.month}/${_examDate!.year}',
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _examDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() {
                          _examDate = picked;
                          if (_status == 'applied' || _status == 'paid') {
                            _status = 'examScheduled';
                          }
                        });
                      }
                    },
                  ),
                ),
                if (_examDate != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _examDate = null),
                  ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.access_time_rounded, size: 16),
                    label: Text(
                      _examTimeOfDay == null
                          ? 'সময় বাছুন'
                          : _examTimeOfDay!.format(context),
                    ),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _examTimeOfDay ??
                            const TimeOfDay(hour: 10, minute: 0),
                      );
                      if (picked != null) {
                        setState(() => _examTimeOfDay = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.m),
            TextFormField(
              controller: _venueController,
              decoration: const InputDecoration(
                labelText: 'পরীক্ষা কেন্দ্র ও সিট প্ল্যান নোট',
                hintText: 'e.g. ঢাকা কলেজ, কলা ভবন, কক্ষ ৩০২, সিট নং ২৫',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'অতিরিক্ত নোট (ঐচ্ছিক)',
                hintText: 'সিলেবাস, জরুরি নির্দেশনা বা অন্য কোনো তথ্য...',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: FluentSpacing.xxl),

            // Submit Button
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  isEditing ? 'আপডেট করুন' : 'ভল্টে সংরক্ষণ করুন',
                  style: FluentType.bodyStrong.copyWith(color: Colors.white),
                ),
                onPressed: _isSaving ? null : _saveApplication,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePickerTile({
    required String label,
    required String? filePath,
    required IconData icon,
    required Color color,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final hasFile = filePath != null && filePath.isNotEmpty;
    final fileName = hasFile ? filePath.split(Platform.pathSeparator).last : '';

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: hasFile
            ? color.withValues(alpha: 0.08)
            : Theme.of(context).cardTheme.color,
        borderRadius: FluentRadius.controlBorder,
        border: Border.all(
          color: hasFile
              ? color.withValues(alpha: 0.4)
              : FluentStroke.card(Theme.of(context).brightness),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: FluentSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: FluentType.bodyStrong.copyWith(fontSize: 13),
                ),
                Text(
                  hasFile ? fileName : 'কোনো ফাইল যুক্ত নেই',
                  style: FluentType.caption.copyWith(
                    color: hasFile ? color : Colors.grey,
                    fontWeight: hasFile ? FontWeight.bold : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (hasFile)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: onClear,
            )
          else
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file, size: 14),
              label: const Text('Add PDF'),
              onPressed: onPick,
            ),
        ],
      ),
    );
  }
}
