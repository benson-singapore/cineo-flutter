import 'package:flutter/material.dart';

import 'app_lock_controller.dart';
import 'pin_pad.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({
    required this.controller,
    this.onComplete,
    super.key,
  });

  final AppLockController controller;
  final VoidCallback? onComplete;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _pin = '';
  String? _firstPin;
  String? _message;
  bool _saving = false;

  String get _title => _firstPin == null ? '设置应用锁' : '再次输入 PIN';
  String get _subtitle =>
      _firstPin == null ? '设置 6 位数字 PIN，保护本机数据' : '请再次输入 PIN 以确认';

  void _onChanged(String value) {
    if (_saving) {
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
                PinPad(value: _pin, onChanged: _onChanged, enabled: !_saving),
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
