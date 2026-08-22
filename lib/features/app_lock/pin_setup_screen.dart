import 'package:flutter/material.dart';

import 'app_lock_controller.dart';
import 'app_lock_service.dart';
import 'pin_pad.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({
    required this.controller,
    this.onComplete,
    this.requireCurrentPin = false,
    super.key,
  });

  final AppLockController controller;
  final VoidCallback? onComplete;
  final bool requireCurrentPin;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _pin = '';
  String _currentPin = '';
  String? _firstPin;
  String? _message;
  bool _saving = false;
  bool _currentPinVerified = false;

  bool get _needsCurrentPin =>
      widget.requireCurrentPin &&
      widget.controller.hasPin &&
      !_currentPinVerified;

  String get _title {
    if (_needsCurrentPin) {
      return '验证当前 PIN';
    }
    return _firstPin == null ? '设置应用锁' : '再次输入 PIN';
  }

  String get _subtitle {
    if (_needsCurrentPin) {
      return '请输入当前 PIN 后继续';
    }
    return _firstPin == null ? '设置 6 位数字 PIN，保护本机数据' : '请再次输入 PIN 以确认';
  }

  void _onChanged(String value) {
    if (_saving) {
      return;
    }
    setState(() {
      if (_needsCurrentPin) {
        _currentPin = value;
      } else {
        _pin = value;
      }
      _message = null;
    });
    if (value.length == 6) {
      Future<void>.microtask(
        _needsCurrentPin ? _verifyCurrentPin : _submit,
      );
    }
  }

  Future<void> _verifyCurrentPin() async {
    if (_currentPin.length != 6 || _saving) {
      return;
    }
    setState(() => _saving = true);
    final result = await widget.controller.verifyPin(_currentPin);
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _currentPin = '';
      if (result.isSuccess) {
        _currentPinVerified = true;
        _message = null;
      } else {
        _message = switch (result.status) {
          PinVerificationStatus.invalidPin => 'PIN 不正确，请重试',
          PinVerificationStatus.temporarilyLocked => '尝试次数过多，请稍后再试',
          PinVerificationStatus.notConfigured => '应用锁尚未设置',
          PinVerificationStatus.success => null,
        };
      }
    });
  }

  Future<void> _submit() async {
    if (_pin.length != 6 || _saving) {
      return;
    }
    if (_firstPin == null) {
      setState(() {
        _firstPin = _pin;
        _pin = '';
      });
      return;
    }
    if (_pin != _firstPin) {
      setState(() {
        _pin = '';
        _message = '两次输入不一致，请重新输入';
      });
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.setupPin(_pin);
      if (mounted) {
        widget.onComplete?.call();
        // This screen is normally pushed from Settings. maybePop also keeps
        // it safe when a caller embeds it without adding a navigator route.
        await Navigator.of(context).maybePop();
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _message = error.message?.toString() ?? 'PIN 设置失败';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('应用锁')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.lock_outline, size: 42),
                const SizedBox(height: 24),
                Text(_title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(_subtitle, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 32),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(_message!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                PinPad(
                  value: _needsCurrentPin ? _currentPin : _pin,
                  onChanged: _onChanged,
                  enabled: !_saving,
                ),
                if (_saving) ...[
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
