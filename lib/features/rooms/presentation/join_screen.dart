import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../application/room_providers.dart';

/// Landing target for invite links (`synk://app/join/ABC234`).
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({required this.code, super.key});

  final String code;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() => _error = null);
    try {
      final roomId = await ref.read(roomRepositoryProvider).resolveCode(widget.code);
      if (mounted) context.go(Routes.room(roomId));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: CircleBackButton(
          icon: Icons.close_rounded,
          tooltip: 'Close',
          onPressed: () => context.go(Routes.home),
        ),
      ),
      body: Center(
        child: _error == null ? const CircularProgressIndicator() : ErrorState(error: _error!, onRetry: _resolve),
      ),
    );
  }
}
