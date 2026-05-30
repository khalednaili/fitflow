import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl =
        AnimationController(vsync: this, duration: Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _switchMode() {
    _animCtrl.reverse().then((_) {
      setState(() => _isSignUp = !_isSignUp);
      _animCtrl.forward();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_isSignUp) {
        await _authService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          displayName: _nameController.text.trim(),
        );
      } else {
        await _authService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString();
      final message =
          raw.replaceAll(RegExp(r'\[firebase_auth/[^\]]+\]\s*'), '');
      messenger.showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _authService.signInWithGoogle();
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString();
      final message =
          raw.replaceAll(RegExp(r'\[firebase_auth/[^\]]+\]\s*'), '');
      messenger.showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ));
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isLoading = _isLoading || _isGoogleLoading;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary.withValues(alpha: 0.06),
              cs.surface,
              cs.surface,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 440),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Logo / brand ────────────────────────────────────
                      Container(
                        padding: EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              cs.primary,
                              cs.primary.withValues(alpha: 0.7)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(Icons.fitness_center,
                            color: Colors.white, size: 36),
                      ),
                      SizedBox(height: 20),
                      Text(
                        _isSignUp
                            ? l10n.tr('Create your account')
                            : l10n.tr('Welcome back'),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 6),
                      Text(
                        _isSignUp
                            ? l10n.tr('Join and start your fitness journey')
                            : l10n.tr('Sign in to continue to FitFlow'),
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                      SizedBox(height: 28),

                      // ── Google button ───────────────────────────────────
                      _GoogleSignInButton(
                        isLoading: _isGoogleLoading,
                        disabled: isLoading,
                        onTap: _signInWithGoogle,
                      ),

                      // ── Divider ─────────────────────────────────────────
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Row(
                          children: [
                            Expanded(child: Divider(color: cs.outlineVariant)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text(context.l10n.tr('or'),
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12)),
                            ),
                            Expanded(child: Divider(color: cs.outlineVariant)),
                          ],
                        ),
                      ),

                      // ── Email / password form ───────────────────────────
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            if (_isSignUp) ...[
                              TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: l10n.tr('Full name'),
                                  prefixIcon: Icon(Icons.person_outline),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? l10n.tr('Enter your name')
                                        : null,
                              ),
                              SizedBox(height: 12),
                            ],
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: l10n.tr('Email'),
                                prefixIcon: Icon(Icons.email_outlined),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return l10n.tr('Email is required');
                                }
                                if (!v.contains('@')) {
                                  return l10n.tr('Enter a valid email address');
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: l10n.tr('Password'),
                                prefixIcon: Icon(Icons.lock_outline),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return l10n.tr('Password is required');
                                }
                                if (_isSignUp && v.length < 6) {
                                  return l10n.tr(
                                      'Password must be at least 6 characters');
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 20),

                      // ── Submit button ───────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: isLoading ? null : _submit,
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  _isSignUp
                                      ? l10n.tr('Create account')
                                      : l10n.tr('Sign in'),
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),

                      SizedBox(height: 12),

                      // ── Switch mode ─────────────────────────────────────
                      TextButton(
                        onPressed: isLoading ? null : _switchMode,
                        child: Text(
                          _isSignUp
                              ? l10n.tr('Already have an account? Sign in')
                              : l10n.tr('Need an account? Sign up'),
                          style: TextStyle(
                              color: cs.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Google Sign-In Button ─────────────────────────────────────────────────────

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.onTap,
    required this.isLoading,
    required this.disabled,
  });

  final VoidCallback onTap;
  final bool isLoading;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: cs.outlineVariant, width: 1.5),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? cs.surfaceContainerLow
              : Colors.white,
        ),
        onPressed: disabled ? null : onTap,
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: cs.primary),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google "G" logo using coloured letters
                  _GoogleLogo(),
                  SizedBox(width: 10),
                  Text(
                    context.l10n.tr('Continue with Google'),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Draw coloured arcs for the G logo
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.38;

    // Red (top)
    paint.color = Color(0xFFEA4335);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.62),
        -1.57, 2.07, false, paint);

    // Yellow (right)
    paint.color = Color(0xFFFBBC05);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.62),
        0.5, 1.57, false, paint);

    // Green (bottom)
    paint.color = Color(0xFF34A853);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.62),
        2.07, 1.57, false, paint);

    // Blue (left)
    paint.color = Color(0xFF4285F4);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.62),
        3.64, 1.23, false, paint);

    // White horizontal bar for the "G" cut
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    canvas.drawRect(
        Rect.fromLTWH(cx - 0.5, cy - r * 0.2, r * 0.62 + 0.5, r * 0.4), paint);

    // Blue fill for horizontal bar
    paint.color = Color(0xFF4285F4);
    canvas.drawRect(Rect.fromLTWH(cx, cy - r * 0.18, r * 0.6, r * 0.36), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
