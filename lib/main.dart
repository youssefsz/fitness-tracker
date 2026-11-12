import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/branding.dart';
import 'app/navigation.dart';
import 'app/providers.dart';
import 'app/theme.dart';
import 'shared/domain/training.dart';
import 'shared/widgets/ui.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  var ready = false;
  void release() {
    if (ready) return;
    ready = true;
    binding.allowFirstFrame();
  }

  // Leave the native launch screen as soon as storage is ready. If opening
  // stalls, surface the in-app loading state and its eventual retry instead.
  final deadline = Timer(const Duration(seconds: 2), release);
  runApp(
    ProviderScope(
      child: FitnessApp(
        onReady: () {
          deadline.cancel();
          release();
        },
      ),
    ),
  );
}

class FitnessApp extends ConsumerStatefulWidget {
  const FitnessApp({this.onReady, super.key});

  final VoidCallback? onReady;

  @override
  ConsumerState<FitnessApp> createState() => _FitnessAppState();
}

class _FitnessAppState extends ConsumerState<FitnessApp> {
  final _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opening = ref.watch(bootstrapProvider);
    final preferences = opening.hasValue
        ? ref.watch(preferencesProvider)
        : const AsyncLoading<Preferences>();
    if ((opening.hasValue && preferences.hasValue) ||
        opening.hasError ||
        preferences.hasError) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onReady?.call(),
      );
    }
    final mode = switch (preferences.value?.appearance ?? Appearance.system) {
      Appearance.light => ThemeMode.light,
      Appearance.dark => ThemeMode.dark,
      Appearance.system => ThemeMode.system,
    };

    return MaterialApp.router(
      title: Branding.name,
      debugShowCheckedModeBanner: false,
      theme: trackerTheme(Brightness.light),
      darkTheme: trackerTheme(Brightness.dark),
      themeMode: mode,
      themeAnimationDuration: Duration.zero,
      routerConfig: _router,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: trackerBars(Theme.of(context).brightness),
        child: opening.hasValue && preferences.hasValue
            ? child!
            : opening.hasError || preferences.hasError
            ? Scaffold(
                body: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: EmptyBlock(
                          title: 'Couldn’t open your records',
                          message: 'Try opening the local database again.',
                          action: 'Try again',
                          onAction: () {
                            ref.invalidate(repositoryProvider);
                            ref.invalidate(bootstrapProvider);
                            ref.invalidate(preferencesProvider);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : Scaffold(
                body: Center(
                  child: Semantics(
                    label: 'Opening your records',
                    child: Image.asset(
                      Branding.mark,
                      width: 78,
                      height: 78,
                      color: context.colors.ink,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
