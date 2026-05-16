import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:lumox/base_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lumox/logic/repositories/user_repository.dart';
import 'package:lumox/ui/animations/slide_morph_transitions.dart';
import 'package:lumox/ui/misc/ban_appeal_screen.dart';
import 'package:lumox/ui/misc/profile_image_picker.dart';
import 'package:lumox/ui/router/router.dart';

import '../../base_logic.dart';
import '../../logic/users/user_model.dart';
import '../theme/theme_ui_values.dart';

// ─────────────────────────────────────────────
// Auth mode
// ─────────────────────────────────────────────

enum _AuthMode { login, signup, recover }

// ─────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  // ── State ──────────────────────────────────

  _AuthMode _mode = _AuthMode.login;
  int _modeDirection = 1;
  int _modeVersion = 0;
  bool _isLoading = false;
  Type? _currentErrorType;
  String? _errorMessage;
  String? _successMessage;
  bool _isBanned = userBannedHint;
  String? _signedInUserId = lastUserProfileId ?? lastUserProfile?.id;
  UserProfile? _user = lastUserProfile;

  // ── Form ───────────────────────────────────

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // ── Animations ─────────────────────────────

  // Entry: fade + slide on first load
  late final AnimationController _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();

  late final Animation<double> _entryFade = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);

  late final Animation<Offset> _entrySlide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));

  // Shake on error
  late final AnimationController _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  late final Animation<double> _shakeAnim = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

  // Ban banner: slide in from top
  late final AnimationController _banController = AnimationController(value: userBannedHint ? 1 : 0, vsync: this, duration: const Duration(milliseconds: 350));

  late final Animation<double> _banFade = CurvedAnimation(parent: _banController, curve: Curves.easeOut);

  late final Animation<Offset> _banSlide = Tween<Offset>(
    begin: const Offset(0, -0.3),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _banController, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _entryController.dispose();
    _shakeController.dispose();
    _banController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────

  void _setError(String? msg, Type type) {
    setState(() {
      _errorMessage = msg;
      _currentErrorType = type;
      _successMessage = null;
    });
    if (msg != null) _shakeController.forward(from: 0);
  }
  
  void _clearError(Type type) {
    if(_currentErrorType == type) {
      setState(() {
        _errorMessage = null;
        _currentErrorType = null;
      });
    }
  }

  void _setSuccess(String msg) {
    setState(() {
      _successMessage = msg;
      _errorMessage = null;
    });
  }

  Future<void> _switchMode(_AuthMode mode) async {
    if (_mode == mode) return;
    setState(() {
      _modeDirection = _modeIndex(mode) > _modeIndex(_mode) ? 1 : -1;
      _mode = mode;
      _modeVersion++;
      _errorMessage = null;
      _successMessage = null;
    });
  }

  int _modeIndex(_AuthMode mode) => switch (mode) {
    _AuthMode.login => 0,
    _AuthMode.signup => 1,
    _AuthMode.recover => 2,
  };

  // ── Auth logic ─────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    switch (_mode) {
      case _AuthMode.login:
        await _doLogin();
      case _AuthMode.signup:
        await _doSignup();
      case _AuthMode.recover:
        await _doRecover();
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _doLogin() async {
    try {
      final response = await auth.signInWithPassword(email: _emailController.text.trim(), password: _passwordController.text);
      _signedInUserId = response.user?.id;
    } catch (e) {
      _setError("Unable to sign in. ${e is AuthException ? e.message : ''}", e.runtimeType);
      return;
    }

    if (_signedInUserId == null) {
      _setError("Unable to sign in.", AuthException);
      return;
    }

    try {
      _user = await userRepository.getUserSupabase(_signedInUserId!) ?? await userRepository.getOrCreateCurrentUser();

      if (_user == null) {
        await auth.signOut();
        return;
      }

      _completeLogin(false);
    } on BanAuthException catch (e) {
      setState(() => _isBanned = true);
      _banController.forward();
      _setError(e.message, e.runtimeType);
    } on AuthException catch (e) {
      _setError(e.message, e.runtimeType);
    } catch (e) {
      _setError("An unknown error occurred.", e.runtimeType);
    }
  }

  Future<void> _doSignup() async {
    try {
      final response = await auth.signUp(email: _emailController.text.trim(), password: _passwordController.text);
      _signedInUserId = response.user?.id;
      if (_signedInUserId == null) {
        _setError("Unable to create account.", AuthException);
        return;
      }

      if (!mounted) return;
      context.go('/signup-onboarding');
    } on AuthException catch (e) {
      _setError(e.message, e.runtimeType);
    } catch (e) {
      _setError("An unknown error occurred.", e.runtimeType);
    }
  }

  Future<void> _doRecover() async {
    try {
      await auth.resetPasswordForEmail(
        _emailController.text.trim(),
        redirectTo: kIsWeb
            ? 'https://riddleneon.github.io/lumox/#/reset-password'
            : 'https://riddleneon.github.io/lumox/#/reset-password', //todo app link
      );
      _setSuccess("Password reset email sent! Check your inbox.");
    } on AuthException catch (e) {
      _setError(e.message, e.runtimeType);
    } catch (e) {
      _setError("An error occurred.", e.runtimeType);
    }
  }

  void _completeLogin(bool firstTime) {
    assert(_user != null);
    onUserLogin(_user!, firstTime)
        .then((_) {
          if (mounted) routerConfig.push('/feed');
        })
        .catchError((e, st) {
          debugPrint('Post-login error: $e\n$st');
        });
  }

  Future<void> _openBanAppeal() async {
    if (_signedInUserId == null) {
      print("signed in user is null!");
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => BanAppealScreen(
        userId: _signedInUserId!,
        onAppealSuccess: () {
          setState(() => _isBanned = false);
          _banController.reverse();
          _setSuccess("Appeal successful! You are now unbanned.");
          _clearError(BanAuthException);
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: cs.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: SlideMorphTransitions.build(
                _entryFade,
                SlideTransition(
                  position: _entrySlide,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AnimatedBuilder(
                      animation: _shakeAnim,
                      builder: (context, child) => Transform.translate(offset: Offset(_shakeAnim.value, 0), child: child),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_buildHeader(cs, theme), const SizedBox(height: 40), _buildCard(cs, theme)],
                      ),
                    ),
                  ),
                ),
                beginOffset: const Offset(0, 0.06),
                beginScale: 0.985,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, ThemeData theme) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(context.uiRadiusMd), color: cs.primaryContainer),
          child: Icon(Icons.lightbulb, color: cs.onPrimaryContainer, size: 28),
        ),
        const SizedBox(height: 16),
        Text(
          'Lumox',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.5, color: cs.onSurface),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => _buildHorizontalClipTransition(child: child, animation: animation),
          child: Text(
            _modeSubtitle,
            key: _subtitleKey(),
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  String get _modeSubtitle => switch (_mode) {
    _AuthMode.login => 'Welcome back',
    _AuthMode.signup => 'Create your account',
    _AuthMode.recover => 'Reset your password',
  };

  Widget _buildCard(ColorScheme cs, ThemeData theme) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              reverseDuration: const Duration(milliseconds: 450),
              transitionBuilder: (child, animation) => _buildHorizontalClipTransition(child: child, animation: animation),
              layoutBuilder: (currentChild, previousChildren) => Stack(clipBehavior: Clip.hardEdge, children: [...previousChildren, ?currentChild]),
              child: _buildModeFormContent(cs, theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeFormContent(ColorScheme cs, ThemeData theme) {
    return KeyedSubtree(
      key: _modeContentKey(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_mode != _AuthMode.recover) _buildModeTabs(cs, theme),
          if (_mode != _AuthMode.recover) const SizedBox(height: 24),
          _buildBanBanner(cs, theme),
          _buildEmailField(cs, theme),
          if (_mode != _AuthMode.recover) ...[const SizedBox(height: 12), _buildPasswordField(cs, theme)],
          if (_mode == _AuthMode.signup) ...[const SizedBox(height: 12), _buildConfirmPasswordField(cs, theme)],
          if (_mode == _AuthMode.login) ...[const SizedBox(height: 8), _buildForgotLink(cs)],
          const SizedBox(height: 24),
          AnimatedSize(duration: const Duration(milliseconds: 250), curve: Curves.easeOut, child: _buildFeedback(cs, theme)),
          _buildSubmitButton(cs, theme),
          if (_mode == _AuthMode.recover) ...[const SizedBox(height: 16), _buildBackToLogin(cs)],
        ],
      ),
    );
  }

  Widget _buildHorizontalClipTransition({required Widget child, required Animation<double> animation}) {
    final isCurrent = child.key == _modeContentKey() || child.key == _subtitleKey();
    final enteringOffset = Offset(_modeDirection.toDouble(), 0);
    final exitingOffset = Offset(-_modeDirection.toDouble(), 0);
    // AnimatedSwitcher runs the outgoing child's animation in reverse (1→0).
    // Tween evaluates as lerp(begin, end, t), so for the outgoing child we need
    // begin=exitingOffset and end=Offset.zero so that at t=1.0 (start of exit)
    // the position is Offset.zero (center) and at t=0.0 (end of exit) it's
    // exitingOffset (off-screen). The incoming child's animation runs forward
    // (0→1) so begin=enteringOffset, end=Offset.zero works correctly.
    final tween = Tween<Offset>(begin: isCurrent ? enteringOffset : exitingOffset, end: Offset.zero);
    return ClipRect(
      child: SlideTransition(
        position: tween.animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    );
  }

  ValueKey<String> _modeContentKey() => ValueKey('mode-${_mode.name}-$_modeVersion');

  ValueKey<String> _subtitleKey() => ValueKey('subtitle-${_mode.name}-$_modeVersion');

  Widget _buildModeTabs(ColorScheme cs, ThemeData theme) {
    return Container(
      height: 42,
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(context.uiRadiusSm)),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: _mode == _AuthMode.signup ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(context.uiRadiusSm),
                  color: cs.surface,
                  border: Border.all(color: cs.outlineVariant),
                ),
              ),
            ),
          ),
          Row(children: [_modeTab('Sign in', _AuthMode.login, cs, theme), _modeTab('Sign up', _AuthMode.signup, cs, theme)]),
        ],
      ),
    );
  }

  Widget _modeTab(String label, _AuthMode mode, ColorScheme cs, ThemeData theme) {
    final active = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: Container(
          color: Colors.transparent, //needed to make the entire area tappable
          margin: const EdgeInsets.all(3),
          alignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
              color: active ? cs.primary : cs.onSurfaceVariant,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  Widget _buildBanBanner(ColorScheme cs, ThemeData theme) {
    return ClipRect(
      child: SlideTransition(
        position: _banSlide,
        child: SlideMorphTransitions.build(
          _banFade,
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: _isBanned
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(context.uiRadiusMd),
                        color: cs.errorContainer,
                        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.block_rounded, color: cs.onErrorContainer, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Account Suspended',
                                style: theme.textTheme.labelLarge?.copyWith(color: cs.onErrorContainer, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your account has been suspended. You can submit an appeal below.',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onErrorContainer.withValues(alpha: 0.8)),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.error.withValues(alpha: 0.15),
                              foregroundColor: cs.onErrorContainer,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.uiRadiusSm)),
                            ),
                            onPressed: _openBanAppeal,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.gavel_rounded, size: 16),
                                SizedBox(width: 6),
                                Text('Appeal Ban', style: TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          beginOffset: const Offset(0, -0.08),
          beginScale: 0.97,
        ),
      ),
    );
  }

  Widget _buildEmailField(ColorScheme cs, ThemeData theme) {
    return _AuthField(
      controller: _emailController,
      label: 'Email',
      icon: Icons.mail_outline_rounded,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      cs: cs,
      theme: theme,
      validator: (v) {
        if (v == null || v.isEmpty) return 'Please enter your email';
        if (!v.contains('@')) return 'Enter a valid email';
        return null;
      },
    );
  }

  Widget _buildPasswordField(ColorScheme cs, ThemeData theme) {
    return _AuthField(
      controller: _passwordController,
      label: 'Password',
      icon: Icons.lock_outline_rounded,
      obscureText: _obscurePassword,
      cs: cs,
      theme: theme,
      autofillHints: _mode == _AuthMode.login ? const [AutofillHints.password] : const [AutofillHints.newPassword],
      suffixIcon: IconButton(
        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
        color: cs.onSurfaceVariant,
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Please enter a password';
        if (_mode == _AuthMode.signup && v.length < 8) {
          return 'Password must be at least 8 characters';
        }
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField(ColorScheme cs, ThemeData theme) {
    return _AuthField(
      controller: _confirmPasswordController,
      label: 'Confirm Password',
      icon: Icons.lock_outline_rounded,
      obscureText: _obscureConfirm,
      cs: cs,
      theme: theme,
      autofillHints: const [AutofillHints.newPassword],
      suffixIcon: IconButton(
        icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
        color: cs.onSurfaceVariant,
        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
      ),
      validator: (v) {
        if (v != _passwordController.text) {
          return 'Passwords do not match';
        }
        return null;
      },
    );
  }

  Widget _buildForgotLink(ColorScheme cs) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _switchMode(_AuthMode.recover),
        child: Text(
          'Forgot password?',
          style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildFeedback(ColorScheme cs, ThemeData theme) {
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _FeedbackBanner(message: _errorMessage!, isError: true, cs: cs, theme: theme),
      );
    }
    if (_successMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _FeedbackBanner(message: _successMessage!, isError: false, cs: cs, theme: theme),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSubmitButton(ColorScheme cs, ThemeData theme) {
    final label = switch (_mode) {
      _AuthMode.login => 'Sign in',
      _AuthMode.signup => 'Create Account',
      _AuthMode.recover => 'Send Reset Email',
    };

    return SizedBox(
      height: 50,
      child: FilledButton(
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.uiRadiusMd))),
        onPressed: _isLoading ? null : _submit,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) => SlideMorphTransitions.switcher(child, animation, beginOffset: const Offset(0, 0.14), beginScale: 0.9),
          child: _isLoading
              ? SizedBox(
                  key: const ValueKey('loader'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary),
                )
              : Text(
                  label,
                  key: ValueKey(label),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
        ),
      ),
    );
  }

  Widget _buildBackToLogin(ColorScheme cs) {
    return Center(
      child: TextButton(
        onPressed: () => _switchMode(_AuthMode.login),
        child: RichText(
          text: TextSpan(
            text: 'Remembered it?  ',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            children: [
              TextSpan(
                text: 'Sign in',
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Reusable field
// ─────────────────────────────────────────────

class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.cs,
    required this.theme,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.suffixIcon,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final ColorScheme cs;
  final ThemeData theme;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;

    return TextFormField(
      controller: widget.controller,
      focusNode: _focus,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      autofillHints: widget.autofillHints,
      validator: widget.validator,
      style: widget.theme.textTheme.bodyLarge?.copyWith(color: cs.onSurface),
      cursorColor: cs.primary,
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(color: _focused ? cs.primary : cs.onSurfaceVariant),
        prefixIcon: Icon(widget.icon, color: _focused ? cs.primary : cs.onSurfaceVariant, size: 20),
        suffixIcon: widget.suffixIcon,
        filled: true,
        fillColor: _focused ? cs.primaryContainer.withValues(alpha: 0.25) : cs.surfaceContainerHighest,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uiRadiusMd),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uiRadiusMd),
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uiRadiusMd),
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uiRadiusMd),
          borderSide: BorderSide(color: cs.error, width: 1.5),
        ),
        errorStyle: TextStyle(color: cs.error, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Feedback banner
// ─────────────────────────────────────────────

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message, required this.isError, required this.cs, required this.theme});

  final String message;
  final bool isError;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bgColor = isError ? cs.errorContainer : cs.secondaryContainer;
    final fgColor = isError ? cs.onErrorContainer : cs.onSecondaryContainer;
    final icon = isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(context.uiRadiusMd), color: bgColor),
      child: Row(
        children: [
          Icon(icon, color: fgColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: fgColor, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

enum _UsernameAvailability { idle, checking, available, taken }

class SignupOnboardingScreen extends StatefulWidget {
  const SignupOnboardingScreen({super.key});

  @override
  State<SignupOnboardingScreen> createState() => _SignupOnboardingScreenState();
}

class _SignupOnboardingScreenState extends State<SignupOnboardingScreen> with TickerProviderStateMixin {
  static const int _totalSteps = 6;

  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();

  int _step = 0;
  int _direction = 1;
  int _version = 0;
  int _usernameCheckToken = 0;
  bool _loading = false;
  bool _usernameEditedByUser = false;
  bool _syncingUsername = false;
  String? _error;
  String? _info;
  String? _selectedAvatarUrl;
  String _normalizedUsername = '';
  bool _acceptedEula = false;
  bool _acceptedDataProcessing = false;
  _UsernameAvailability _usernameAvailability = _UsernameAvailability.idle;
  Timer? _usernameDebounce;

  late final AnimationController _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
  late final Animation<double> _entryFade = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
  late final Animation<Offset> _entrySlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
      .animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    final authUser = auth.currentUser;
    final fallback = (authUser?.userMetadata?['full_name'] as String?) ?? authUser?.email?.split('@').first ?? 'newuser';
    _displayNameController.text = fallback;
    _setUsername(_normalizeUsernameCandidate(fallback));
    _selectedAvatarUrl = createUserProfileImageUrl(_usernameController.text);
    _displayNameController.addListener(_onDisplayNameChanged);
    _usernameController.addListener(_onUsernameChanged);
    _checkUsernameAvailability(immediate: true);
  }

  @override
  void dispose() {
    _entryController.dispose();
    _displayNameController.removeListener(_onDisplayNameChanged);
    _usernameController.removeListener(_onUsernameChanged);
    _usernameDebounce?.cancel();
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _setUsername(String value) {
    _syncingUsername = true;
    _usernameController.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    _syncingUsername = false;
  }

  void _onDisplayNameChanged() {
    if (_usernameEditedByUser) return;
    final generated = _normalizeUsernameCandidate(_displayNameController.text);
    if (generated.isNotEmpty && generated != _usernameController.text) {
      _setUsername(generated);
    }
  }

  void _onUsernameChanged() {
    if (!_syncingUsername) {
      _usernameEditedByUser = true;
    }
    setState(() {
      _normalizedUsername = _normalizeUsernameCandidate(_usernameController.text);
      _error = null;
    });
    _checkUsernameAvailability();
  }

  Future<void> _checkUsernameAvailability({bool immediate = false}) async {
    _usernameDebounce?.cancel();
    final candidate = _normalizeUsernameCandidate(_usernameController.text);
    if (candidate.isEmpty) {
      if (mounted) {
        setState(() => _usernameAvailability = _UsernameAvailability.idle);
      }
      return;
    }

    Future<Null> run() async {
      final token = ++_usernameCheckToken;
      if (mounted) setState(() => _usernameAvailability = _UsernameAvailability.checking);
      final available = await userRepository.isUsernameAvailable(candidate, excludingUserId: auth.currentUser?.id);
      if (!mounted || token != _usernameCheckToken) return;
      setState(() {
        _usernameAvailability = available ? _UsernameAvailability.available : _UsernameAvailability.taken;
      });
    }

    if (immediate) {
      await run();
      return;
    }

    _usernameDebounce = Timer(const Duration(milliseconds: 260), run);
  }

  String _normalizeUsernameCandidate(String raw) {
    final lower = raw.toLowerCase().trim();
    final normalized = lower.replaceAll(RegExp(r'[^a-z0-9_.]'), '_').replaceAll(RegExp(r'_+'), '_');
    final trimmed = normalized.replaceAll(RegExp(r'^[_\.]+|[_\.]+$'), '');
    if (trimmed.isEmpty) return '';
    return trimmed.length <= 30 ? trimmed : trimmed.substring(0, 30);
  }

  Future<void> _pickAvatar() async {
    final picked = await showProfileImagePicker(context, persistToCurrentUser: false);
    if (picked == null || !mounted) return;
    setState(() {
      _selectedAvatarUrl = picked;
      _info = 'Great pick. Your avatar has been added.';
    });
  }

  void _randomizeAvatar() {
    setState(() {
      _selectedAvatarUrl = createUserProfileImageUrl(_normalizedUsername.isEmpty ? _displayNameController.text : _normalizedUsername);
      _info = null;
    });
  }

  Future<void> _next() async {
    setState(() {
      _error = null;
      _info = null;
    });

    if (_step == 1) {
      final displayName = _displayNameController.text.trim();
      final rawUsername = _usernameController.text.trim();
      final normalized = _normalizeUsernameCandidate(rawUsername);

      if (displayName.isEmpty || displayName.length < 3) {
        setState(() => _error = 'Display name should be at least 3 characters.');
        return;
      }
      if (normalized.isEmpty) {
        setState(() => _error = 'Please choose a valid username.');
        return;
      }
      if (normalized != rawUsername) {
        _setUsername(normalized);
        setState(() => _info = 'Username normalized to @$normalized.');
      }

      final available = await userRepository.isUsernameAvailable(normalized, excludingUserId: auth.currentUser?.id);
      if (!mounted) return;
      if (!available) {
        final suggested = await userRepository.suggestUniqueUsername(normalized, excludingUserId: auth.currentUser?.id);
        if (!mounted) return;
        _setUsername(suggested);
        setState(() {
          _usernameAvailability = _UsernameAvailability.available;
          _info = 'That username was taken. We reserved @$suggested for you.';
        });
      } else {
        setState(() => _usernameAvailability = _UsernameAvailability.available);
      }
    }

    if (_step == _totalSteps - 1) {
      await _finishOnboarding();
      return;
    }

    setState(() {
      _direction = 1;
      _step++;
      _version++;
    });
  }

  void _back() {
    if (_step == 0 || _loading) return;
    setState(() {
      _direction = -1;
      _step--;
      _version++;
      _error = null;
      _info = null;
    });
  }

  Future<void> _finishOnboarding() async {
    if (!_acceptedEula || !_acceptedDataProcessing) {
      setState(() => _error = 'Please accept both agreements to continue.');
      return;
    }

    setState(() => _loading = true);
    try {
      final user = await userRepository.completeCurrentUserOnboarding(
        displayName: _displayNameController.text,
        requestedUsername: _usernameController.text,
        avatarUrl: _selectedAvatarUrl,
        bio: _bioController.text,
        acceptedEula: _acceptedEula,
        acceptedDataProcessing: _acceptedDataProcessing,
      );

      await onUserLogin(user, true);
      if (!mounted) return;
      context.go('/feed');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to complete onboarding right now.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAgreement(String title, String body) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: SingleChildScrollView(
            child: MarkdownBody(data: body),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  ValueKey<String> _stepContentKey() => ValueKey('onboarding-step-${_step}_$_version');

  ValueKey<String> _headerContentKey() => ValueKey('onboarding-header-${_step}_$_version');

  String get _stepHeadline => switch (_step) {
    0 => 'Welcome to Lumox',
    1 => 'Choose your identity',
    2 => 'Style your avatar',
    3 => 'Add your vibe',
    4 => 'Final review',
    _ => 'Before you start',
  };

  String get _stepSubheadline => switch (_step) {
    0 => 'Build your profile with a quick personalized setup.',
    1 => 'Pick a display name and a unique @username.',
    2 => 'Select an avatar that represents you.',
    3 => 'Write a short optional bio for your profile.',
    4 => 'Accept agreements and continue.',
    _ => 'Important prototype information.',
  };

  IconData get _stepHeaderIcon => switch (_step) {
    0 => Icons.auto_awesome_rounded,
    1 => Icons.badge_outlined,
    2 => Icons.photo_camera_front_outlined,
    3 => Icons.edit_note_rounded,
    4 => Icons.verified_user_outlined,
    _ => Icons.info_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    if (auth.currentSession == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final progress = (_step + 1) / _totalSteps;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: cs.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: _buildMotionBackground(cs, progress)),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: SlideMorphTransitions.build(
                    _entryFade,
                    SlideTransition(
                      position: _entrySlide,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeader(cs, theme),
                            const SizedBox(height: 26),
                            _buildCard(cs, theme),
                            const SizedBox(height: 14),
                            _buildStepPills(cs),
                            const SizedBox(height: 8),
                            Text('Step ${_step + 1} of $_totalSteps', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: (_step == 0 || _loading) ? null : _back,
                                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                                    label: const Text('Back'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _loading ? null : _next,
                                    icon: _loading
                                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                                        : Icon(_step == _totalSteps - 1 ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 18),
                                    label: Text(_step == _totalSteps - 1 ? 'Finish setup' : 'Next step'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    beginOffset: const Offset(0, 0.06),
                    beginScale: 0.985,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, ThemeData theme) {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 430),
          reverseDuration: const Duration(milliseconds: 320),
          transitionBuilder: (child, animation) {
            final currentKey = _headerContentKey();
            final isIncoming = child.key == currentKey;
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            final begin = isIncoming ? Offset(0, _direction > 0 ? 0.22 : -0.22) : Offset(0, _direction > 0 ? -0.14 : 0.14);
            return SlideTransition(
              position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
          child: Column(
            key: _headerContentKey(),
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(context.uiRadiusLg), color: cs.primaryContainer),
                child: Icon(_stepHeaderIcon, color: cs.onPrimaryContainer, size: 30),
              ),
              const SizedBox(height: 14),
              Text(_stepHeadline, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
              const SizedBox(height: 6),
              Text(_stepSubheadline, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMotionBackground(ColorScheme cs, double progress) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 460),
              curve: Curves.easeOutCubic,
              top: -90 + progress * 50,
              left: -70 + (_step * 7),
              child: Transform.rotate(
                angle: (_direction * 0.04) + (progress * 0.06),
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [cs.primary.withValues(alpha: 0.16), cs.primary.withValues(alpha: 0)]),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutQuart,
              bottom: -110 + progress * 65,
              right: -80 + (_step * 6),
              child: Transform.rotate(
                angle: math.pi * 0.03 * _direction,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [cs.tertiary.withValues(alpha: 0.12), cs.tertiary.withValues(alpha: 0)]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(ColorScheme cs, ThemeData theme) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.uiRadiusLg), side: BorderSide(color: cs.outlineVariant)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 360),
        padding: const EdgeInsets.all(28),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 430),
          reverseDuration: const Duration(milliseconds: 360),
          layoutBuilder: (currentChild, previousChildren) => Stack(children: [...previousChildren, ?currentChild]),
          transitionBuilder: (child, animation) {
            final currentKey = _stepContentKey();
            final isIncoming = child.key == currentKey;
            final begin = isIncoming ? Offset(_direction.toDouble() * 0.28, 0.02) : Offset(-_direction.toDouble() * 0.14, -0.01);
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            final rotateTween = Tween<double>(begin: isIncoming ? _direction * 0.02 : -_direction * 0.012, end: 0);
            final tiltTween = Tween<double>(begin: isIncoming ? -_direction * 0.02 : _direction * 0.01, end: 0);
            return ClipRect(
              child: SlideTransition(
                position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
                child: AnimatedBuilder(
                  animation: curved,
                  child: FadeTransition(
                    opacity: curved,
                    child: ScaleTransition(scale: Tween<double>(begin: isIncoming ? 0.96 : 1.0, end: 1.0).animate(curved), child: child),
                  ),
                  builder: (context, transitionedChild) => Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateZ(rotateTween.evaluate(curved))
                      ..rotateY(tiltTween.evaluate(curved)),
                    child: transitionedChild,
                  ),
                ),
              ),
            );
          },
          child: KeyedSubtree(key: _stepContentKey(), child: _buildStepContent(cs, theme)),
        ),
      ),
    );
  }

  Widget _buildStepPills(ColorScheme cs) {
    return Row(
      children: List.generate(_totalSteps, (index) {
        final active = index <= _step;
        final isCurrent = index == _step;
        return Expanded(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            scale: isCurrent ? 1.08 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              margin: EdgeInsets.only(right: index == _totalSteps - 1 ? 0 : 8),
              height: isCurrent ? 8 : 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: isCurrent
                    ? LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.centerLeft, end: Alignment.centerRight)
                    : null,
                color: isCurrent ? null : (active ? cs.primary.withValues(alpha: 0.58) : cs.surfaceContainerHighest),
              ),
            ),
          ),
        );
      }),
    );
  }

  List<String> _usernameSuggestions() {
    final base = _normalizeUsernameCandidate(_displayNameController.text);
    if (base.isEmpty) return const [];
    return [base, '${base}_official', '${base}x'];
  }

  Widget _buildUsernameStatus(ColorScheme cs, ThemeData theme) {
    final (IconData icon, Color color, String text) = switch (_usernameAvailability) {
      _UsernameAvailability.idle => (Icons.info_outline_rounded, cs.onSurfaceVariant, 'Pick a username (letters, digits, . and _)'),
      _UsernameAvailability.checking => (Icons.hourglass_top_rounded, cs.primary, 'Checking availability...'),
      _UsernameAvailability.available => (Icons.check_circle_outline_rounded, cs.primary, '@$_normalizedUsername is available'),
      _UsernameAvailability.taken => (Icons.error_outline_rounded, cs.error, '@$_normalizedUsername is taken'),
    };

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600))),
      ],
    );
  }

  Widget _buildStepContent(ColorScheme cs, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_step == 0) ...[
          Text('You\'re almost ready.', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            'We\'ll tailor your profile in a few quick steps.',
            style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(context.uiRadiusMd)),
            child: Row(
              children: [
                Icon(Icons.shield_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Your data stays tied to your account and can be changed later in profile settings.', style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        ],
        if (_step == 1) ...[
          Text('How should people see you?', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _AuthField(
            controller: _displayNameController,
            label: 'Display Name',
            icon: Icons.badge_outlined,
            cs: cs,
            theme: theme,
            autofillHints: const [AutofillHints.name],
            validator: (_) => null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _usernameController,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]'))],
            decoration: InputDecoration(
              labelText: 'Username',
              prefixText: '@',
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.uiRadiusMd), borderSide: BorderSide(color: cs.outlineVariant)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(context.uiRadiusMd), borderSide: BorderSide(color: cs.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 8),
          _buildUsernameStatus(cs, theme),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _usernameSuggestions()
                .map(
                  (candidate) => ActionChip(
                    label: Text('@$candidate'),
                    onPressed: () {
                      _setUsername(candidate);
                      _checkUsernameAvailability(immediate: true);
                    },
                  ),
                )
                .toList(),
          ),
        ],
        if (_step == 2) ...[
          Text('Pick your avatar', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Center(
            child: Hero(
              tag: 'signup-avatar-preview',
              child: Container(
                width: 126,
                height: 126,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surfaceContainerHighest, border: Border.all(color: cs.outlineVariant)),
                child: ClipOval(
                  child: Image.network(
                    _selectedAvatarUrl ?? createUserProfileImageUrl(_normalizedUsername.isEmpty ? _displayNameController.text : _normalizedUsername),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _pickAvatar, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Choose')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _randomizeAvatar, icon: const Icon(Icons.casino_outlined), label: const Text('Randomize')),
          const SizedBox(height: 8),
          Text('You can change this later anytime in your profile.', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
        ],
        if (_step == 3) ...[
          Text('Write a short bio', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextFormField(
            controller: _bioController,
            maxLength: 150,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Bio (optional)',
              hintText: 'Tell people what you are into...',
              alignLabelWithHint: true,
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.uiRadiusMd), borderSide: BorderSide(color: cs.outlineVariant)),
            ),
          ),
        ],
        if (_step == 4) ...[
          Text('Almost done', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Please review and accept both agreements to continue.', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _acceptedEula,
            onChanged: (v) => setState(() => _acceptedEula = v ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text('I accept the EULA.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _showAgreement('EULA', _EULA),
              child: const Text('Read EULA'),
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _acceptedDataProcessing,
            onChanged: (v) => setState(() => _acceptedDataProcessing = v ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text('I accept the data processing agreement.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _showAgreement('Data Processing Agreement', _dataProcessingAgreement),
              child: const Text('Read data processing agreement'),
            ),
          ),
        ],
        if (_step == 5) ...[
          Text('Thanks for trying Lumox!', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(context.uiRadiusMd),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              "This app is currently in a prototype stage, so you may encounter bugs or missing features.\n\n"
              "If something doesn’t work as expected, I’d really appreciate your feedback to help me improve this app.\n\n"
              "Ive currently implemented 2 different kinds of video players, the youtube one being the default. It uses youtube videos to fill in some content. \n It uses the youtube IFrame API, because otherwise it would violate youtubes TOS. However that provides some limitations, so its a bit unstable. "
              "some videos might not play, there might be some latency and i also cant really do anything about the ads and play overlays. \n"
              "The main video player (which can be activated in the advanced settings) uses direct video urls and a custom-built video player. \n It is more stable and has more features, but is limited to pixabay videos for now, since i dont have any licenses to use other video sources. \n\n"
              "All credit goes to their respective creators! Their name is the same on youtube / pixabay, so go check out their channels if you like their content! \n\n"
              "Thanks for your understanding – and enjoy using Lumox!",
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 10),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: _error != null
              ? _FeedbackBanner(message: _error!, isError: true, cs: cs, theme: theme)
              : _info != null
                  ? _FeedbackBanner(message: _info!, isError: false, cs: cs, theme: theme)
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _success;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  final supabase = Supabase.instance.client;

  late final AnimationController _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();

  late final Animation<double> _fade = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));

  late final AnimationController _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  late final Animation<double> _shake = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

  @override
  void dispose() {
    _entryController.dispose();
    _shakeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _setError(String msg) {
    setState(() {
      _error = msg;
      _success = null;
    });
    _shakeController.forward(from: 0);
  }

  void _setSuccess(String msg) {
    setState(() {
      _success = msg;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      await supabase.auth.updateUser(UserAttributes(password: _passwordController.text));

      _setSuccess("Password updated successfully!");

      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) context.go('/login');
    } on AuthException catch (e) {
      if (e.message == "Auth session missing!") {
        _setError(
          "Auth session is missing! Please use this link on the same device and browser where you requested the password reset. Redirecting to login. you can request the code again from there.",
        );
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) context.go('/login');
        });
        return;
      }

      _setError(e.message);
    } catch (_) {
      _setError("Something went wrong.");
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: cs.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: SlideMorphTransitions.build(
                _fade,
                SlideTransition(
                  position: _slide,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AnimatedBuilder(
                      animation: _shake,
                      builder: (context, child) => Transform.translate(offset: Offset(_shake.value, 0), child: child),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_buildHeader(cs, theme), const SizedBox(height: 40), _buildCard(cs, theme)],
                      ),
                    ),
                  ),
                ),
                beginOffset: const Offset(0, 0.06),
                beginScale: 0.985,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, ThemeData theme) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(context.uiRadiusMd), color: cs.primaryContainer),
          child: Icon(Icons.lock_reset_rounded, color: cs.onPrimaryContainer, size: 28),
        ),
        const SizedBox(height: 16),
        Text('Reset Password', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        Text('Enter a new password for your account', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildCard(ColorScheme cs, ThemeData theme) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uiRadiusLg),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPasswordField(cs, theme),
              const SizedBox(height: 12),
              _buildConfirmField(cs, theme),
              const SizedBox(height: 24),
              if (_error != null) _FeedbackBanner(message: _error!, isError: true, cs: cs, theme: theme),
              if (_success != null) _FeedbackBanner(message: _success!, isError: false, cs: cs, theme: theme),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Update Password", style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(ColorScheme cs, ThemeData theme) {
    return _AuthField(
      controller: _passwordController,
      label: 'New Password',
      icon: Icons.lock_outline_rounded,
      obscureText: _obscurePassword,
      cs: cs,
      theme: theme,
      suffixIcon: IconButton(
        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
      validator: (v) {
        if (v == null || v.length < 8) {
          return 'Min. 8 characters required';
        }
        return null;
      },
    );
  }

  Widget _buildConfirmField(ColorScheme cs, ThemeData theme) {
    return _AuthField(
      controller: _confirmController,
      label: 'Confirm Password',
      icon: Icons.lock_outline_rounded,
      obscureText: _obscureConfirm,
      cs: cs,
      theme: theme,
      suffixIcon: IconButton(
        icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
      ),
      validator: (v) {
        if (v != _passwordController.text) {
          return 'Passwords do not match';
        }
        return null;
      },
    );
  }
}



// ignore: constant_identifier_names
const String _EULA = '''
# End User License Agreement (EULA)

**Effective Date:** May 16, 2026
**App Name:** Lumox 
**Operator:** RiddleNeon 

## 1. Acceptance of Terms
By accessing or using the App, you agree to this EULA and all applicable laws. If you do not agree, do not use the App.

## 2. Eligibility; Minors
The App is intended for students and may be used by minors where permitted. If you are under the age of digital consent in your jurisdiction (or under 13 in the United States), you may use the App only with verifiable consent from a parent or legal guardian. Parents/guardians are responsible for the minor’s use of the App and for supervising content shared, including videos, comments, and messages. We may require age verification or parental consent at any time and may suspend accounts that do not meet these requirements.

## 3. License Grant
We grant you a limited, non-exclusive, non-transferable, revocable license to use the App for personal, educational purposes only, subject to this EULA.

## 4. Prohibited Uses
You agree not to, and not to assist others to:

- Violate any local, national, or international laws or regulations.
- Use the App for illegal purposes, including fraud, identity theft, or harassment.
- Engage in hate speech, racism, antisemitism, or discrimination based on protected characteristics.
- Post, request, or distribute NSFW, sexually explicit, or pornographic content.
- Attempt to jailbreak, bypass, or override AI safety controls or system limitations.
- Use AI features for non-educational purposes, harmful content, or unlawful activity.
- Impersonate any person or entity or misrepresent your affiliation.
- Attempt to access, scrape, or steal content or data that you do not own or have rights to use.
- Violate the privacy or rights of others (including doxxing or unauthorized collection of personal data).
- Upload or distribute malware, exploit code, or attempt to interfere with the App’s security.
- Reverse engineer, decompile, or tamper with the App except as allowed by law.
- Circumvent access controls, rate limits, or usage restrictions.

## 5. Third-Party AI and Services
The App integrates third-party AI services (for example, OpenRouter and underlying model providers). You must not:

- Attempt to “jailbreak” the AI or solicit prohibited content.
- Use AI outputs for illegal, harmful, or abusive purposes.
- Rely on AI outputs as professional advice (legal, medical, financial, etc.).

## 6. User Content and Conduct
You are responsible for content you post or share (for example, videos, comments, messages). You represent that you have the rights to upload or share content and that it does not violate any laws or third-party rights.

### 6.5 Minor Safety and School Use
Users must not solicit or share personal contact information from minors, and must not attempt to identify, track, or contact minors outside the App. If the App is used in a school or classroom setting, educators and administrators are responsible for ensuring use complies with applicable school policies and laws.

## 7. No Ownership of Displayed Media
Media shown in the App may be sourced from third parties. The App does not claim ownership of such media. You may not copy, download, redistribute, or otherwise use third-party content unless you have the lawful right to do so.

## 8. Moderation and Enforcement
We may remove content, limit visibility, or suspend/terminate accounts for violations, with or without notice where permitted by law.

## 9. Intellectual Property
The App and its original content, features, and design are owned by Lumox and protected by intellectual property laws. You may not use our trademarks without permission.

## 10. Privacy
Your use of the App is subject to our Privacy Policy and DPA (where applicable).

## 11. Disclaimers
The App is provided “as is” and “as available.” We do not guarantee accuracy, reliability, or availability. AI outputs may be incorrect or biased.

## 12. Limitation of Liability
To the maximum extent permitted by law, Lumox is not liable for indirect, incidental, special, or consequential damages, or loss of data, profits, or goodwill.

## 13. Indemnification
You agree to indemnify and hold harmless Lumox from claims arising out of your use of the App or violation of this EULA.

## 14. Termination
We may terminate or suspend access at any time for violations. Sections that should survive termination will do so.

## 15. Changes
We may update this EULA from time to time. Continued use after changes means you accept the updated terms.
''';

const String _dataProcessingAgreement = '''
# Data Processing Agreement (DPA)

**Effective Date:** May 16, 2026
**Controller:** Lumox  
**Processor:** Lumox (if you act as processor for business customers)  

## 1. Scope
This DPA describes how we process personal data in connection with the App and in compliance with applicable data protection laws (for example, GDPR, UK GDPR, CCPA/CPRA as applicable).

## 2. Roles
- **Controller:** Lumox determines the purposes and means of processing.
- **Processors/Subprocessors:** Third-party service providers (for example, Supabase, OpenRouter, YouTube) may process data on our behalf.

## 3. Categories of Data
We may process:

- Account data (username, email, hashed password)
- User-generated content (videos, comments, messages)
- Usage data (logs, device info, analytics)
- Support communications
- AI interaction data (prompts, outputs) where applicable

## 4. Purposes of Processing
- Provide and improve App functionality
- Enable social features (comments, chats, follows)
- Content moderation and safety
- Security, fraud prevention, and abuse detection
- AI feature operation and troubleshooting
- Legal compliance

## 5. Data Selling and Sharing
We do not sell user data. We share data only with service providers necessary to operate the App, or as required by law.

## 6. Subprocessors
We use third-party services, including:

- Supabase (hosting, database, auth, storage)
- OpenRouter / AI Providers (AI processing)
- YouTube (embedded content and related APIs)

We require subprocessors to protect data and not sell or misuse it. Supabase and other providers may have technical access but are not permitted to use data for their own purposes beyond service delivery.

## 7. International Transfers
Data may be processed in countries other than your own. We use legal safeguards (for example, SCCs) where required.

## 8. Security Measures
We apply reasonable technical and organizational measures, including:

- Encryption in transit (TLS)
- Access controls and least-privilege policies
- Monitoring and abuse detection
- Regular backups and incident response procedures

## 9. Data Retention
We retain data only as long as needed for the purposes stated, or as required by law. Users may request deletion of their data where applicable.

## 10. User Rights
Depending on your jurisdiction, you may have rights to access, correct, delete, or export your data, and to object or restrict processing.

## 11. Children’s Data
The App is designed for students and may be used by minors. We process children’s data only as necessary to provide the App and comply with applicable law. Where required (for example, COPPA in the U.S. or local digital consent laws), we obtain verifiable parental consent before collecting personal data from children. We do not knowingly permit targeted advertising to minors and do not sell children’s data.

### 11.1 Data Minimization for Minors
We limit the collection and use of minors’ data to what is necessary for App functionality and safety. We do not require unnecessary personal information from minors to access core learning features.

## 12. Data Breach Notification
We will notify users and regulators of a breach when legally required and without undue delay.

## 13. AI Data Handling
AI inputs/outputs may be processed by third-party providers to deliver features. We do not use AI interaction data to sell user data. Some AI providers may retain data to improve services; refer to their policies where applicable.

## 14. Content and Third-Party Media
User-uploaded content remains the user’s responsibility. Third-party media displayed in the App is subject to their respective terms.

## 15. Changes to This DPA
We may update this DPA. Material changes will be communicated as required.
''';

