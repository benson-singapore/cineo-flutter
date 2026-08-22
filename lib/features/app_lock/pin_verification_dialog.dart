import 'dart:async';

import 'package:flutter/material.dart';

import 'app_lock_controller.dart';
import 'app_lock_service.dart';
import 'pin_pad.dart';

class PinVerificationDialog extends StatefulWidget {
  const PinVerificationDialog({required this.controller, super.key});

  final AppLockController controller;

  @override
  State<PinVerificationDialog> createState() => _PinVerificationDialogState();
}

class _PinVerificationDialogState extends State<PinVerificationDialog> {
  String _pin = '';
  String? _message;
  Duration _remaining = Duration.zero;
  Timer? _timer;
  bool _checking = false;

  void _onChanged(String value) {
    if (_checking || _remaining > Duration.zero) return;
    setState(() {
      _pin = value;
      _message = null;
    });
    if (value.length == 6) Future<void>.microtask(_submit);
  }

  Future<void> _submit() async {
    if (_pin.length != 6 || _checking) return;
    setState(() => _checking = true);
    final result = await widget.controller.verifyPin(_pin);
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _pin = '';
      _remaining = result.remainingLockout;
      _message = switch (result.status) {
        PinVerificationStatus.invalidPin => 'PIN 不正确，请重试',
        PinVerificationStatus.temporarilyLocked => '尝试次数过多，请稍后再试',
        PinVerificationStatus.notConfigured => '应用锁尚未设置',
        PinVerificationStatus.success => null,
      };
    });
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    if (_remaining <= Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining -= const Duration(seconds: 1);
        if (_remaining <= Duration.zero) {
          _remaining = Duration.zero;
          _message = null;
        }
      });
      if (_remaining <= Duration.zero) _timer?.cancel();
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
    return AlertDialog(
      title: const Text('验证 PIN'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请输入当前 PIN 以启用成人标记'),
            const SizedBox(height: 22),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            PinPad(
              value: _pin,
              onChanged: _onChanged,
              enabled: !_checking && !locked,
            ),
            if (_checking) ...[
              const SizedBox(height: 16),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
