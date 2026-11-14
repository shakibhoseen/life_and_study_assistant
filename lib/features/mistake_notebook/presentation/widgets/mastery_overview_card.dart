import 'package:flutter/material.dart';

import '../../../../core/theme/fluent_tokens.dart';

class MasteryOverviewCard extends StatelessWidget {
  final int total;
  final int pending;
  final int mastered;
  final double rate;
  final bool isDark;
  final VoidCallback onNightlyReview;
  final VoidCallback onReDrill;

  const MasteryOverviewCard({
    super.key,
    required this.total,
    required this.pending,
    required this.mastered,
    required this.rate,
    required this.isDark,
    required this.onNightlyReview,
    required this.onReDrill,
  });

  static Widget _buildWhiteStatPill(
    String title,
    String value, {
    Color color = Colors.white,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: FluentSpacing.s,
          horizontal: FluentSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: FluentRadius.controlBorder,
        ),
        child: Column(
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.bodyStrong.copyWith(color: color),
            ),
            const SizedBox(height: FluentSpacing.xxs),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E1B4B), const Color(0xFF311042)]
              : [const Color(0xFF4338CA), const Color(0xFF6B21A8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(FluentSpacing.s),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: const Icon(
                  Icons.verified,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: FluentSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'মিস্টেক নোটবুক অ্যানালাইসিস',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.bodyStrong.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'ভুলগুলো চিহ্নিত করে রিভিশন দিন ও সম্পূর্ণ আয়ত্তে আনুন',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.s,
                  vertical: FluentSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: Text(
                  '${rate.toStringAsFixed(0)}% সলভড',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.m),

          // Stat counters
          Row(
            children: [
              _buildWhiteStatPill('মোট ভুল', '$total টি'),
              const SizedBox(width: FluentSpacing.s),
              _buildWhiteStatPill(
                'বাকি ভুল',
                '$pending টি',
                color: Colors.redAccent.shade100,
              ),
              const SizedBox(width: FluentSpacing.s),
              _buildWhiteStatPill(
                'আয়ত্তে এসেছে',
                '$mastered টি',
                color: Colors.greenAccent,
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.m),

          // Progress Bar
          ClipRRect(
            borderRadius: FluentRadius.controlBorder,
            child: LinearProgressIndicator(
              value: (rate / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Colors.greenAccent,
              ),
            ),
          ),
          const SizedBox(height: FluentSpacing.m),

          // Action Buttons: Nightly Review & Re-Drill
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      vertical: FluentSpacing.s,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  onPressed: onNightlyReview,
                  icon: const Icon(Icons.nightlight_round, size: 16),
                  label: Text(
                    'রাতের রিভিশন 🌙',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: FluentStroke.width,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: FluentSpacing.s,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  onPressed: onReDrill,
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: Text(
                    'রি-ড্রিল কুইজ ⚡',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
