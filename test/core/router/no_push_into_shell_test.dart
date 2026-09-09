import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against `context.push` to a route that lives inside a
/// `StatefulShellRoute`.
///
/// Pushing a shell-branch route makes go_router build a SECOND copy of that
/// shell as a new page. The shell's `GlobalKey<NavigatorState>` is then in the
/// widget tree twice, and Flutter throws:
///
///     A GlobalKey was used multiple times inside one widget's child list.
///     The offending GlobalKey was: [LabeledGlobalKey<NavigatorState>#...]
///     The parent of the widgets with that key was: HeroControllerScope
///
/// which replaces the entire app with a red error screen. `go` is correct for
/// these: it moves to the location, entering the existing shell with the right
/// branch selected. The router says as much in a comment on its
/// StatefulShellRoute — push routes live OUTSIDE the shell.
///
/// This is a source-level test rather than a widget test on purpose: the crash
/// happens at build time in whatever screen holds the bad call, so the only way
/// to catch every one is to look at every call site. Three real instances
/// existed when this was written, two of them long-standing (the HR home
/// "Reviews" tile and the location heatmap's "View employees" button).
void main() {
  test('no context.push targets a StatefulShellRoute branch', () {
    final routerFile = File('lib/core/router/app_router.dart');
    expect(routerFile.existsSync(), isTrue,
        reason: 'router moved — update this test');
    final routerSrc = routerFile.readAsStringSync();

    // Collect every `path: AppRoutes.x` that sits inside a
    // StatefulShellRoute(...) block. Brace-depth tracking rather than a regex,
    // because these blocks nest branches several levels deep.
    final branchRoutes = <String>{};
    var depth = 0;
    var shellDepth = -1;
    for (final line in routerSrc.split('\n')) {
      if (line.contains('StatefulShellRoute') && shellDepth == -1) {
        shellDepth = depth;
      }
      if (shellDepth != -1) {
        final m = RegExp(r'path:\s*AppRoutes\.(\w+)').firstMatch(line);
        if (m != null) branchRoutes.add(m.group(1)!);
      }
      depth += RegExp(r'[({\[]').allMatches(line).length;
      depth -= RegExp(r'[)}\]]').allMatches(line).length;
      if (shellDepth != -1 && depth <= shellDepth) shellDepth = -1;
    }

    expect(branchRoutes, isNotEmpty,
        reason:
            'found no shell-branch routes — the parser is broken, not the app');

    // Every Dart file under lib/, scanned for pushes to those routes.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('.push(')) continue;
        for (final route in branchRoutes) {
          // Match `push(AppRoutes.hrEmployees)` but not
          // `push(AppRoutes.hrEmployeeDetail(...))`, which is a different,
          // non-branch route that merely shares a prefix.
          if (RegExp('\\.push\\(\\s*AppRoutes\\.$route\\s*[),]')
              .hasMatch(line)) {
            offenders.add('${entity.path}:${i + 1} -> AppRoutes.$route');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These push into a StatefulShellRoute branch and will crash the '
          'frame with a duplicate GlobalKey<NavigatorState>. Use context.go '
          'instead:\n  ${offenders.join('\n  ')}',
    );
  });
}
