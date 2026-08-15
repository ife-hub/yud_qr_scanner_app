import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../services/session_service.dart';
import '../config/app_config.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _keepLoggedIn = true;
  bool _obscurePassword = true;
  String? _error;
  bool _checking = true;
  bool _autoLoginDone = false;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final success = await SessionService.instance.tryAutoLogin();
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() {
        _checking = false;
        _autoLoginDone = true;
      });
    }
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _checking = true;
      _error = null;
    });

    final staff = await DatabaseHelper.instance.findStaffByCredentials(username, password);

    if (!mounted) return;

    if (staff == null) {
      setState(() {
        _checking = false;
        _error = 'Invalid username or password.';
      });
      return;
    }

    await SessionService.instance.login(staff, _keepLoggedIn);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_autoLoginDone) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Branding header bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(kOrgName, style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A), fontWeight: FontWeight.w600)),
                  Text(kEventName, style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A), fontWeight: FontWeight.w600)),
                ],
              ),
              const Spacer(flex: 2),
              const Text('Log Into', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w400, height: 1.2)),
              const Text('Your Account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 32),
              _LoginField(
                icon: Icons.alternate_email,
                hint: 'Username',
                controller: _usernameController,
              ),
              const SizedBox(height: 14),
              _LoginField(
                icon: Icons.lock_outline,
                hint: 'Password',
                controller: _passwordController,
                obscureText: _obscurePassword,
                trailing: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 22,
                      width: 22,
                      child: Checkbox(
                        value: _keepLoggedIn,
                        activeColor: Colors.black,
                        checkColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (v) => setState(() => _keepLoggedIn = v ?? true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('Keep me logged in', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  onPressed: _checking ? null : _submit,
                  child: _checking
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Log In', style: TextStyle(fontSize: 16)),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginField extends StatefulWidget {
  final IconData icon;
  final String hint;
  final TextEditingController controller;
  final bool obscureText;
  final Widget? trailing;
  // Optional override for the trailing icon's focused-state color.
  // Falls back to the default accent color when not supplied.
  final Color? trailingActiveColor;
  final void Function(String)? onSubmitted;

  const _LoginField({
    required this.icon,
    required this.hint,
    required this.controller,
    this.obscureText = false,
    this.trailing,
    this.trailingActiveColor,
    this.onSubmitted,
  });

  @override
  State<_LoginField> createState() => _LoginFieldState();
}

class _LoginFieldState extends State<_LoginField> {
  final FocusNode _focusNode = FocusNode();
  bool _hasFocus = false;

  static const _accentColor = Color(0xFFE53935);
  static const _inactiveBadgeColor = Color(0xFFDCDCDC);
  static const _inactiveIconColor = Color(0xFF6B6B6B);

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.trailingActiveColor ?? _accentColor;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _hasFocus ? activeColor : _inactiveBadgeColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.icon,
              size: 17,
              color: _hasFocus ? Colors.white : _inactiveIconColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              obscureText: widget.obscureText,
              onSubmitted: widget.onSubmitted,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: const TextStyle(color: Color(0xFF9A9A9A)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (widget.trailing != null)
            IconTheme(
              data: IconThemeData(color: _hasFocus ? activeColor : const Color(0xFF8A8A8A)),
              child: widget.trailing!,
            ),
        ],
      ),
    );
  }
}