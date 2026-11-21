import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_ui_kit.dart';
import '../../data/models/exam_application.dart';
import '../../data/services/exam_vault_service.dart';

class ExamCredentialCard extends StatefulWidget {
  final ExamApplication application;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onStatusChanged;

  const ExamCredentialCard({
    super.key,
    required this.application,
    required this.onEdit,
    required this.onDelete,
    required this.onStatusChanged,
  });

  @override
  State<ExamCredentialCard> createState() => _ExamCredentialCardState();
}

class _ExamCredentialCardState extends State<ExamCredentialCard> {
  bool _obscurePassword = true;

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label ক্লিপবোর্ডে কপি করা হয়েছে!'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'admitIssued':
        return Colors.indigo;
      case 'examScheduled':
        return const Color(0xFFF59E0B);
      case 'completed':
        return const Color(0xFF10B981);
      case 'passed':
        return Colors.purple;
      case 'paid':
        return Colors.teal;
      case 'applied':
      default:
        return Colors.blueGrey;
    }
  }

  void _showSmsSheet(BuildContext context) {
    final sms = widget.application.rawSms ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sms_rounded, color: Colors.teal),
                    const SizedBox(width: FluentSpacing.s),
                    Text(
                      'সংরক্ষিত SMS ও পেমেন্ট তথ্য',
                      style: FluentType.bodyStrong.copyWith(fontSize: 16),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.m),
            if (widget.application.transactionId != null) ...[
              Container(
                padding: const EdgeInsets.all(FluentSpacing.s),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, size: 16, color: Colors.teal),
                    const SizedBox(width: FluentSpacing.s),
                    Text(
                      'Transaction ID: ${widget.application.transactionId}',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () => _copyToClipboard(
                        context,
                        widget.application.transactionId!,
                        'TxID',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade100,
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: FluentStroke.card(Theme.of(context).brightness),
                ),
              ),
              child: SelectableText(
                sms.isNotEmpty ? sms : 'কোনো এসএমএস টেক্সট সেভ করা নেই।',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: FluentSpacing.l),
            if (sms.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('সম্পূর্ণ SMS কপি করুন'),
                  onPressed: () {
                    _copyToClipboard(context, sms, 'SMS');
                    Navigator.pop(ctx);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.application;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceMuted = onSurface.withValues(alpha: 0.65);
    final statusColor = _getStatusColor(app.status);

    return Container(
      margin: const EdgeInsets.only(bottom: FluentSpacing.m),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E202E) : Colors.white,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
        boxShadow: FluentElevation.card(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header: Organization & Status Badge
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              FluentSpacing.l,
              FluentSpacing.m,
              FluentSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.postName,
                        style: FluentType.bodyStrong.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: FluentSpacing.xs - 2),
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_outlined,
                            size: 14,
                            color: onSurfaceMuted,
                          ),
                          const SizedBox(width: FluentSpacing.xs),
                          Expanded(
                            child: Text(
                              app.organization,
                              style: FluentType.caption.copyWith(
                                color: onSurfaceMuted,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Status Popup Menu & Badge
                PopupMenuButton<String>(
                  initialValue: app.status,
                  tooltip: 'স্ট্যাটাস পরিবর্তন করুন',
                  onSelected: widget.onStatusChanged,
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'applied',
                      child: Text('📝 আবেদন সম্পন্ন (Applied)'),
                    ),
                    const PopupMenuItem(
                      value: 'paid',
                      child: Text('💳 ফি পরিশোধিত (Paid)'),
                    ),
                    const PopupMenuItem(
                      value: 'admitIssued',
                      child: Text('🎟️ অ্যাডমিট এসেছে (Admit Issued)'),
                    ),
                    const PopupMenuItem(
                      value: 'examScheduled',
                      child: Text('⏳ তারিখ নির্ধারিত (Exam Scheduled)'),
                    ),
                    const PopupMenuItem(
                      value: 'completed',
                      child: Text('✅ পরীক্ষা সম্পন্ন (Completed)'),
                    ),
                    const PopupMenuItem(
                      value: 'passed',
                      child: Text('🏆 উত্তীর্ণ / ভাইভা (Passed)'),
                    ),
                  ],
                  child: PremiumTag(
                    label: app.statusLabelBn,
                    color: statusColor,
                    icon: Icons.flag_rounded,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: FluentSpacing.m),

          // Core Credentials Box (User ID & Password)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.l),
            child: Container(
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(
                  color: FluentStroke.card(brightness),
                  width: FluentStroke.width,
                ),
              ),
              child: Column(
                children: [
                  // User ID Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_pin,
                          size: 16,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Text(
                        'User ID:',
                        style: FluentType.caption.copyWith(
                          color: onSurfaceMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: SelectableText(
                          app.userId,
                          style: FluentType.bodyStrong.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _copyToClipboard(
                          context,
                          app.userId,
                          'User ID',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Copy',
                                style: FluentType.caption.copyWith(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: FluentSpacing.m),

                  // Password Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lock_rounded,
                          size: 16,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Text(
                        'Password:',
                        style: FluentType.caption.copyWith(
                          color: onSurfaceMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: SelectableText(
                          _obscurePassword ? '••••••••' : app.password,
                          style: FluentType.bodyStrong.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            letterSpacing: _obscurePassword ? 2.0 : 0.5,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 16,
                          color: onSurfaceMuted,
                        ),
                        onPressed: () => setState(() {
                          _obscurePassword = !_obscurePassword;
                        }),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _copyToClipboard(
                          context,
                          app.password,
                          'Password',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Copy',
                                style: FluentType.caption.copyWith(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Roll Number Row (if available)
                  if (app.rollNo != null && app.rollNo!.isNotEmpty) ...[
                    const Divider(height: FluentSpacing.m),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.badge_rounded,
                            size: 16,
                            color: Colors.purple,
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Text(
                          'Roll No:',
                          style: FluentType.caption.copyWith(
                            color: onSurfaceMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: SelectableText(
                            app.rollNo!,
                            style: FluentType.bodyStrong.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _copyToClipboard(
                            context,
                            app.rollNo!,
                            'Roll Number',
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.copy_rounded,
                                  size: 14,
                                  color: Colors.purple,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Copy',
                                  style: FluentType.caption.copyWith(
                                    color: Colors.purple,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Exam Countdown & Venue Note (if scheduled)
          if (app.examDate != null || app.venueAndSeat != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FluentSpacing.l,
                FluentSpacing.m,
                FluentSpacing.l,
                0,
              ),
              child: Container(
                padding: const EdgeInsets.all(FluentSpacing.s + 2),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: isDark ? 0.2 : 0.08),
                  borderRadius: FluentRadius.controlBorder,
                  border: Border.all(
                    color: Colors.indigo.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_available_rounded,
                      size: 18,
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (app.examDate != null)
                            Text(
                              'পরীক্ষা: ${app.examDate!.day}/${app.examDate!.month}/${app.examDate!.year}${app.examTime != null ? ' (${app.examTime})' : ''}'
                              '${app.daysUntilExam != null ? ' • ${app.daysUntilExam! >= 0 ? "আর ${app.daysUntilExam} দিন বাকি ⏳" : "অতিক্রান্ত"}' : ''}',
                              style: FluentType.caption.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.indigo.shade200
                                    : Colors.indigo.shade900,
                              ),
                            ),
                          if (app.venueAndSeat != null &&
                              app.venueAndSeat!.isNotEmpty)
                            Text(
                              'কেন্দ্র: ${app.venueAndSeat}',
                              style: FluentType.caption.copyWith(
                                color: onSurfaceMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Attachments & Quick Action Chips
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              FluentSpacing.m,
              FluentSpacing.l,
              FluentSpacing.xs,
            ),
            child: Wrap(
              spacing: FluentSpacing.s,
              runSpacing: FluentSpacing.s,
              children: [
                // Applicant Copy PDF Chip
                if (app.hasApplicantCopy)
                  ActionChip(
                    avatar: const Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 16,
                      color: Colors.red,
                    ),
                    label: const Text('Applicant Copy'),
                    labelStyle: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    onPressed: () async {
                      final res = await ExamVaultService.instance
                          .openDocument(app.applicantCopyPdfPath!);
                      if (res.type != ResultType.done && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: ${res.message}')),
                        );
                      }
                    },
                  ),

                // Admit Card PDF Chip
                if (app.hasAdmitCard)
                  ActionChip(
                    avatar: const Icon(
                      Icons.assignment_ind_rounded,
                      size: 16,
                      color: Colors.teal,
                    ),
                    label: const Text('Admit Card 🎟️'),
                    labelStyle: FluentType.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                    onPressed: () async {
                      final res = await ExamVaultService.instance
                          .openDocument(app.admitCardPdfPath!);
                      if (res.type != ResultType.done && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: ${res.message}')),
                        );
                      }
                    },
                  ),

                // View SMS Button
                if (app.rawSms != null && app.rawSms!.trim().isNotEmpty)
                  ActionChip(
                    avatar: const Icon(
                      Icons.sms_rounded,
                      size: 16,
                      color: Colors.blue,
                    ),
                    label: const Text('View SMS'),
                    labelStyle: FluentType.caption,
                    onPressed: () => _showSmsSheet(context),
                  ),

                // Open Portal URL Button
                if (app.portalUrl != null && app.portalUrl!.trim().isNotEmpty)
                  ActionChip(
                    avatar: const Icon(
                      Icons.open_in_browser_rounded,
                      size: 16,
                      color: Colors.indigo,
                    ),
                    label: const Text('Portal'),
                    labelStyle: FluentType.caption,
                    onPressed: () async {
                      final uri = Uri.tryParse(app.portalUrl!);
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
              ],
            ),
          ),

          // Bottom Controls: Edit & Delete Row
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              0,
              FluentSpacing.m,
              FluentSpacing.s,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'সম্পাদনা করুন',
                  onPressed: widget.onEdit,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  tooltip: 'মুছে ফেলুন',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('আবেদন রেকর্ড মুছে ফেলবেন?'),
                        content: Text(
                          '${app.postName} (${app.organization})-এর সংরক্ষিত তথ্য স্থায়ীভাবে মুছে যাবে।',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      widget.onDelete();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
