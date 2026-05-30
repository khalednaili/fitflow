import 'package:fit_flow/utils/crash_logger.dart';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/gym_class.dart';
import '../../services/booking_service.dart';
import '../../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main Scanner Screen
// ─────────────────────────────────────────────────────────────────────────────

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key, this.gymClass, this.gymId = ''});

  /// When opened from a class detail page, pass the class for context display.
  final GymClass? gymClass;

  /// The gym (tenant) ID — used to validate the QR token against the correct
  /// tenant's settings document.
  final String gymId;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with TickerProviderStateMixin {
  late final _bookingService = BookingService(
    gymId: widget.gymClass?.gymId.isNotEmpty == true
        ? widget.gymClass!.gymId
        : widget.gymId,
  );
  bool _processing = false;
  // status: ''=scanning, 'success', 'already', 'error', 'pick'
  String _status = '';
  String _message = '';
  String _classTitle = '';
  List<Map<String, dynamic>> _pickClasses = [];
  MobileScannerController? _controller;
  bool _torchOn = false;

  // Scanning line animation
  late final AnimationController _scanLineCtrl;
  late final Animation<double> _scanLineAnim;

  // Corner pulse animation
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Result entrance animation
  late final AnimationController _resultCtrl;
  late final Animation<double> _resultScale;
  late final Animation<double> _resultOpacity;

  // Success countdown animation (3 s)
  late final AnimationController _countdownCtrl;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );

    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scanLineAnim =
        CurvedAnimation(parent: _scanLineCtrl, curve: Curves.easeInOut);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _resultCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 450),
    );
    _resultScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _resultCtrl, curve: Curves.easeOutBack),
    );
    _resultOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _resultCtrl, curve: Curves.easeOut),
    );

    _countdownCtrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _scanLineCtrl.dispose();
    _pulseCtrl.dispose();
    _resultCtrl.dispose();
    _countdownCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _handleScan(String raw) async {
    if (_processing) return;

    final l10n = context.l10n;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'fitflow') {
      _setError(
          l10n.tr('Invalid QR code.\nPlease scan a FitFlow check-in QR.'));
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _setError(l10n.tr('You are not signed in.'));
      return;
    }

    setState(() {
      _processing = true;
      _status = '';
    });
    _scanLineCtrl.stop();
    _pulseCtrl.stop();
    await _controller?.stop();

    try {
      Map<String, dynamic> result;

      if (uri.host == 'class') {
        final parts = uri.pathSegments;
        if (parts.isEmpty) {
          _setError(l10n.tr('Malformed QR code.'));
          return;
        }
        result = await _bookingService.checkInByClassQr(
            classId: parts[0], userId: userId);
      } else if (uri.host == 'gym') {
        final parts = uri.pathSegments;
        if (parts.isEmpty) {
          _setError(l10n.tr('Malformed QR code.'));
          return;
        }
        result = await _bookingService.checkInByGymQr(
            gymToken: parts[0], userId: userId);
      } else {
        _setError(l10n.tr('Unrecognised QR code type.'));
        return;
      }

      if (!mounted) return;
      _applyResult(result);
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'scanCheckInQr');
      if (!mounted) return;
      _setError(l10n.tr('Something went wrong.\nPlease try again.'));
    }
  }

  void _setError(String msg) {
    setState(() {
      _processing = false;
      _status = 'error';
      _message = msg;
    });
    _resultCtrl.forward(from: 0);
  }

  void _applyResult(Map<String, dynamic> result) {
    final status = result['status'] as String;
    if (status == 'success') {
      setState(() {
        _processing = false;
        _status = 'success';
        _classTitle = (result['classTitle'] ?? '') as String;
      });
      _resultCtrl.forward(from: 0);
      _countdownCtrl.forward(from: 0);
      Future.delayed(Duration(seconds: 3), () {
        if (mounted) Navigator.of(context).pop();
      });
    } else if (status == 'already_checked_in') {
      setState(() {
        _processing = false;
        _status = 'already';
        _classTitle = (result['classTitle'] ?? '') as String;
      });
      _resultCtrl.forward(from: 0);
    } else if (status == 'pick') {
      setState(() {
        _processing = false;
        _status = 'pick';
        _pickClasses =
            List<Map<String, dynamic>>.from(result['classes'] as List);
      });
      _resultCtrl.forward(from: 0);
    } else {
      _setError(
          (result['message'] ?? context.l10n.tr('Unknown error.')) as String);
    }
  }

  Future<void> _pickAndCheckIn(Map<String, dynamic> cls) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    setState(() {
      _processing = true;
      _status = '';
    });
    _resultCtrl.reverse();
    try {
      final result = await _bookingService.checkInForClass(
          classId: cls['classId'] as String, userId: userId);
      if (mounted) _applyResult(result);
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'pickAndCheckIn');
      if (mounted) {
        _setError(context.l10n.tr('Something went wrong. Please try again.'));
      }
    }
  }

  Future<void> _retry() async {
    await _resultCtrl.reverse();
    setState(() {
      _status = '';
      _message = '';
      _classTitle = '';
      _pickClasses = [];
      _processing = false;
    });
    _scanLineCtrl.repeat(reverse: true);
    _pulseCtrl.repeat(reverse: true);
    await _controller?.start();
  }

  void _toggleTorch() {
    setState(() => _torchOn = !_torchOn);
    _controller?.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final frameSize = (size.width * 0.72).clamp(220.0, 300.0);
    final isScanning = _status.isEmpty && !_processing;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(context.l10n.tr('Check In'),
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        actions: [
          if (isScanning)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: _TorchButton(isOn: _torchOn, onToggle: _toggleTorch),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera feed ─────────────────────────────────────────────────
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) _handleScan(barcode!.rawValue!);
            },
          ),

          // ── Dark vignette with hole ──────────────────────────────────
          if (isScanning)
            CustomPaint(
              painter: _VignettePainter(frameSize: frameSize),
            ),

          // ── Animated scan line ───────────────────────────────────────
          if (isScanning)
            Center(
              child: SizedBox(
                width: frameSize,
                height: frameSize,
                child: AnimatedBuilder(
                  animation: _scanLineAnim,
                  builder: (_, __) => CustomPaint(
                    painter: _ScanLinePainter(_scanLineAnim.value),
                  ),
                ),
              ),
            ),

          // ── Pulsating corner brackets ────────────────────────────────
          if (isScanning)
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Transform.scale(
                  scale: _pulseAnim.value,
                  child: CustomPaint(
                    size: Size(frameSize, frameSize),
                    painter: _CornerBracketPainter(
                        color:
                            _torchOn ? Color(0xFFFFD54F) : Color(0xFF26C6DA)),
                  ),
                ),
              ),
            ),

          // ── Top context card (class info) ────────────────────────────
          if (isScanning && widget.gymClass != null)
            Positioned(
              top: kToolbarHeight + MediaQuery.paddingOf(context).top + 12,
              left: 20,
              right: 20,
              child: _ClassContextCard(gymClass: widget.gymClass!),
            ),

          // ── Bottom hint ──────────────────────────────────────────────
          if (isScanning)
            Positioned(
              bottom: 60,
              left: 24,
              right: 24,
              child: Column(
                children: [
                  _PulsingDot(),
                  SizedBox(height: 10),
                  Text(
                    context.l10n.tr('Align the QR code inside the frame'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    context.l10n
                        .tr('Scan the code displayed at the front desk'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

          // ── Processing ───────────────────────────────────────────────
          if (_processing)
            Container(
              color: Colors.black.withValues(alpha: 0.88),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        color: Color(0xFF26C6DA),
                        strokeWidth: 3.5,
                      ),
                    ),
                    SizedBox(height: 28),
                    Text(context.l10n.tr('Verifying…'),
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 6),
                    Text(context.l10n.tr('Checking you in'),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13)),
                  ],
                ),
              ),
            ),

          // ── Result overlay ───────────────────────────────────────────
          if (_status == 'success' ||
              _status == 'already' ||
              _status == 'error')
            FadeTransition(
              opacity: _resultOpacity,
              child: ScaleTransition(
                scale: _resultScale,
                child: _ResultOverlay(
                  status: _status,
                  title: _status == 'success'
                      ? context.l10n.tr('Checked In! 🎉')
                      : _status == 'already'
                          ? context.l10n.tr('Already Checked In')
                          : context.l10n.tr('Check-in Failed'),
                  subtitle: _status == 'error'
                      ? _message
                      : _classTitle.isNotEmpty
                          ? _classTitle
                          : null,
                  actionLabel: _status == 'error'
                      ? context.l10n.tr('Try Again')
                      : context.l10n.tr('Done'),
                  onAction: _status == 'error'
                      ? _retry
                      : () => Navigator.of(context).pop(),
                  countdownAnim: _status == 'success' ? _countdownCtrl : null,
                ),
              ),
            ),

          // ── Pick class overlay ───────────────────────────────────────
          if (_status == 'pick')
            FadeTransition(
              opacity: _resultOpacity,
              child: ScaleTransition(
                scale: _resultScale,
                child: _PickClassOverlay(
                  classes: _pickClasses,
                  onPick: _pickAndCheckIn,
                  onCancel: _retry,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Torch toggle button
// ─────────────────────────────────────────────────────────────────────────────

class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.isOn, required this.onToggle});
  final bool isOn;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: isOn
            ? Color(0xFFFFD54F).withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOn
              ? Color(0xFFFFD54F).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: IconButton(
        icon: Icon(
          isOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
          color: isOn ? Color(0xFFFFD54F) : Colors.white70,
          size: 20,
        ),
        onPressed: onToggle,
        tooltip: isOn
            ? context.l10n.tr('Turn off flash')
            : context.l10n.tr('Turn on flash'),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        constraints: BoxConstraints(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Class context card (shown when opened from class detail)
// ─────────────────────────────────────────────────────────────────────────────

class _ClassContextCard extends StatelessWidget {
  const _ClassContextCard({required this.gymClass});
  final GymClass gymClass;

  @override
  Widget build(BuildContext context) {
    final timeLabel = '${DateFormat('HH:mm').format(gymClass.startTime)} – '
        '${DateFormat('HH:mm').format(gymClass.endTime)}';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFF26C6DA).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xFF26C6DA).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.fitness_center_rounded,
                color: Color(0xFF26C6DA), size: 18),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  gymClass.title,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(timeLabel,
                    style: TextStyle(color: Color(0xFF26C6DA), fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Color(0xFF26C6DA).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(context.l10n.tr('Booked'),
                style: TextStyle(
                    color: Color(0xFF26C6DA),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing "ready" dot
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(Color(0xFF26C6DA),
                  Color(0xFF26C6DA).withValues(alpha: 0.3), _ctrl.value),
            ),
          ),
          SizedBox(width: 6),
          Text(
            context.l10n.tr('Scanning…'),
            style: TextStyle(
              color: Color.lerp(Colors.white,
                  Colors.white.withValues(alpha: 0.5), _ctrl.value),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cut-out vignette overlay
// ─────────────────────────────────────────────────────────────────────────────

class _VignettePainter extends CustomPainter {
  const _VignettePainter({required this.frameSize});
  final double frameSize;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final half = frameSize / 2;

    final outer = Rect.fromLTWH(0, 0, size.width, size.height);
    final hole = RRect.fromRectAndRadius(
      Rect.fromLTRB(cx - half, cy - half, cx + half, cy + half),
      Radius.circular(20),
    );
    final path = Path()
      ..addRect(outer)
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
        path, Paint()..color = Colors.black.withValues(alpha: 0.68));
  }

  @override
  bool shouldRepaint(_VignettePainter old) => old.frameSize != frameSize;
}

// ─────────────────────────────────────────────────────────────────────────────
// Corner bracket painter
// ─────────────────────────────────────────────────────────────────────────────

class _CornerBracketPainter extends CustomPainter {
  const _CornerBracketPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const len = 32.0;
    const r = 14.0;
    const strokeW = 4.0;

    // Outer glow
    final glow = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = strokeW + 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6);

    // Main stroke
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final corners = [
      // Top-left
      Path()
        ..moveTo(0, len)
        ..lineTo(0, r)
        ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
        ..lineTo(len, 0),
      // Top-right
      Path()
        ..moveTo(w - len, 0)
        ..lineTo(w - r, 0)
        ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
        ..lineTo(w, len),
      // Bottom-right
      Path()
        ..moveTo(w, h - len)
        ..lineTo(w, h - r)
        ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
        ..lineTo(w - len, h),
      // Bottom-left
      Path()
        ..moveTo(len, h)
        ..lineTo(r, h)
        ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
        ..lineTo(0, h - len),
    ];

    for (final path in corners) {
      canvas.drawPath(path, glow);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_CornerBracketPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated scan line
// ─────────────────────────────────────────────────────────────────────────────

class _ScanLinePainter extends CustomPainter {
  const _ScanLinePainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = 6 + (size.height - 12) * progress;

    // Glow layer
    final glowRect = Rect.fromLTWH(0, y - 6, size.width, 12);
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.transparent,
          Color(0xFF26C6DA).withValues(alpha: 0.2),
          Colors.transparent,
        ]).createShader(glowRect),
    );

    // Main line
    final lineRect = Rect.fromLTWH(0, y - 1.5, size.width, 3);
    canvas.drawRect(
      lineRect,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.transparent,
          Color(0xFF26C6DA),
          Color(0xFFFFFFFF),
          Color(0xFF26C6DA),
          Colors.transparent,
        ]).createShader(lineRect),
    );
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Result overlay (success / already / error)
// ─────────────────────────────────────────────────────────────────────────────

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({
    required this.status,
    required this.title,
    this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.countdownAnim,
  });

  final String status;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final AnimationController? countdownAnim;

  bool get _isSuccess => status == 'success' || status == 'already';
  bool get _isAlready => status == 'already';

  @override
  Widget build(BuildContext context) {
    final accent = _isSuccess ? Color(0xFF4CAF50) : Color(0xFFEF5350);
    final bgTop = _isSuccess ? Color(0xFF071A10) : Color(0xFF1A0707);
    final bgBot = Color(0xFF080808);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bgTop, bgBot],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Icon with countdown ring ─────────────────────────────
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.08),
                      ),
                    ),
                    // Countdown ring (only on auto-close success)
                    if (countdownAnim != null)
                      SizedBox(
                        width: 112,
                        height: 112,
                        child: AnimatedBuilder(
                          animation: countdownAnim!,
                          builder: (_, __) => CustomPaint(
                            painter: _CountdownRingPainter(
                              progress: 1 - countdownAnim!.value,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                    // Inner circle
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.14),
                        border: Border.all(
                            color: accent.withValues(alpha: 0.4), width: 2),
                      ),
                      child: Icon(
                        _isSuccess
                            ? (_isAlready
                                ? Icons.check_circle_outline_rounded
                                : Icons.check_circle_rounded)
                            : Icons.cancel_rounded,
                        size: 52,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 28),

              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),

              if (subtitle != null && subtitle!.isNotEmpty) ...[
                SizedBox(height: 14),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
              ],

              if (status == 'success') ...[
                SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.7),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      context.l10n.tr('Attendance recorded · Closing in 3s'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],

              SizedBox(height: 44),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(actionLabel,
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Countdown ring painter
// ─────────────────────────────────────────────────────────────────────────────

class _CountdownRingPainter extends CustomPainter {
  const _CountdownRingPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CountdownRingPainter old) =>
      old.progress != progress || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pick-class overlay (multiple active bookings)
// ─────────────────────────────────────────────────────────────────────────────

class _PickClassOverlay extends StatelessWidget {
  const _PickClassOverlay({
    required this.classes,
    required this.onPick,
    required this.onCancel,
  });
  final List<Map<String, dynamic>> classes;
  final void Function(Map<String, dynamic>) onPick;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.94),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Color(0xFF26C6DA).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Color(0xFF26C6DA).withValues(alpha: 0.3),
                      width: 1.5),
                ),
                child: Icon(Icons.fitness_center_rounded,
                    size: 30, color: Color(0xFF26C6DA)),
              ),
              SizedBox(height: 20),
              Text(
                context.l10n.tr('Which class?'),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text(
                context.l10n.tr(
                    'Multiple classes are happening now.\nSelect the one to check in to.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    height: 1.4),
              ),
              SizedBox(height: 28),
              ...classes.map((cls) {
                final start = cls['startTime'] as DateTime;
                return Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () => onPick(cls),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Color(0xFF26C6DA).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color:
                                    Color(0xFF26C6DA).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.fitness_center_rounded,
                                  color: Color(0xFF26C6DA), size: 18),
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    cls['title'] as String,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    DateFormat('HH:mm').format(start),
                                    style: TextStyle(
                                        color: Color(0xFF26C6DA), fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 22,
                                color: Colors.white.withValues(alpha: 0.3)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              SizedBox(height: 10),
              TextButton(
                onPressed: onCancel,
                child: Text(context.l10n.tr('Cancel'),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
