import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../services/member_service.dart';
import '../../services/review_service.dart';

/// Bottom sheet for rating a past class.
/// Usage: `RateClassSheet.show(context, classId, gymId)`.
class RateClassSheet extends StatefulWidget {
  const RateClassSheet({
    super.key,
    required this.classId,
    required this.className,
    required this.gymId,
  });

  final String classId;
  final String className;
  final String gymId;

  static Future<void> show(
    BuildContext context, {
    required String classId,
    required String className,
    required String gymId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RateClassSheet(
        classId: classId,
        className: className,
        gymId: gymId,
      ),
    );
  }

  @override
  State<RateClassSheet> createState() => _RateClassSheetState();
}

class _RateClassSheetState extends State<RateClassSheet> {
  late final ReviewService _reviewService;
  late final MemberService _memberService;
  final _commentController = TextEditingController();
  int _rating = 4;
  bool _submitting = false;
  bool _alreadyReviewed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reviewService = ReviewService(gymId: widget.gymId);
    _memberService = MemberService(gymId: widget.gymId);
    _loadExisting();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final existing =
        await _reviewService.streamMyReview(widget.classId, uid).first;
    if (!mounted) return;
    if (existing != null) {
      setState(() {
        _alreadyReviewed = true;
        _rating = existing.rating;
        _commentController.text = existing.comment;
      });
    }
    setState(() => _loading = false);
  }

  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    setState(() => _submitting = true);
    try {
      AppUser? appUser;
      try {
        appUser = await _memberService.streamUser(uid).first;
      } catch (_) {}
      await _reviewService.submitReview(
        classId: widget.classId,
        userId: uid,
        memberName: appUser?.displayName ?? '',
        rating: _rating,
        comment: _commentController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('Review submitted. Thank you!'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${context.l10n.tr('Error')}: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: _loading
          ? SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Title
                Text(
                  _alreadyReviewed
                      ? context.l10n.tr('Update your review')
                      : context.l10n.tr('Rate this class'),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                ),
                SizedBox(height: 4),
                Text(
                  widget.className,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                ),
                SizedBox(height: 20),

                // Star selector
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return GestureDetector(
                      onTap: () => setState(() => _rating = star),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          star <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                          color: star <= _rating
                              ? Colors.amber.shade600
                              : cs.outlineVariant,
                          size: 40,
                        ),
                      ),
                    );
                  }),
                ),
                SizedBox(height: 8),
                Center(
                  child: Text(
                    _ratingLabel(context),
                    style: TextStyle(
                        color: Colors.amber.shade700,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(height: 16),

                // Comment
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: InputDecoration(
                    hintText:
                        context.l10n.tr('Add a comment (optional)…'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                SizedBox(height: 16),

                // Submit
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_alreadyReviewed
                            ? context.l10n.tr('Update review')
                            : context.l10n.tr('Submit review')),
                  ),
                ),
              ],
            ),
    );
  }

  String _ratingLabel(BuildContext context) {
    switch (_rating) {
      case 1:
        return context.l10n.tr('Poor');
      case 2:
        return context.l10n.tr('Fair');
      case 3:
        return context.l10n.tr('Good');
      case 4:
        return context.l10n.tr('Great');
      case 5:
        return context.l10n.tr('Excellent!');
      default:
        return '';
    }
  }
}
