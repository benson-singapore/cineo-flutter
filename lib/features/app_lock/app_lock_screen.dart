import 'dart:async';

import 'package:flutter/material.dart';

import 'app_lock_controller.dart';
import 'app_lock_service.dart';
import 'pin_pad.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({required this.controller, super.key});

  final AppLockController controller;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  String? _message;
  Duration _remaining = Duration.zero;
  Timer? _timer;
  bool _checking = false;

  void _onChanged(String value) {
    if (_checking || _remaining > Duration.zero) {
      return;
    }
    setState(() {
      _pin = value;
      _message = null;
    });
    if (value.length == 6) {
      Future<void>.microtask(_submit);
    }
  }

  Future<void> _submit() async {
    if (_pin.length != 6 || _checking) {
      return;
    }
    setState(() => _checking = true);
    final result = await widget.controller.verifyPin(_pin);
    if (!mounted) {
      return;
    }
    setState(() => _checking = false);
    if (result.isSuccess) {
      setState(() => _pin = '');
      return;
    }
    setState(() {
      _pin = '';
      _message = switch (result.status) {
        PinVerificationStatus.invalidPin => 'PIN 不正确，请重试',
        PinVerificationStatus.temporarilyLocked => '尝试次数过多，请稍后再试',
        PinVerificationStatus.notConfigured => '应用锁尚未设置',
        PinVerificationStatus.success => null,
      };
      _remaining = result.remainingLockout;
    });
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    if (_remaining <= Duration.zero) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _remaining -= const Duration(seconds: 1);
        if (_remaining <= Duration.zero) {
          _remaining = Duration.zero;
          _message = null;
        }
      });
      if (_remaining <= Duration.zero) {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _remaining > Duration.zero;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.lock, size: 44),
                const SizedBox(height: 24),
                Text('Cineo 已锁定',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                    locked
                        ? '请等待 ${_remaining.inSeconds + 1} 秒'
                        : '输入 PIN 继续使用',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 30),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(_message!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                PinPad(
                    value: _pin,
                    onChanged: _onChanged,
                    enabled: !_checking && !locked),
                if (_checking) ...[
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
