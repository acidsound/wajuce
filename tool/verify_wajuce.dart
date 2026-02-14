import 'dart:io';

import '_wajuce_cli.dart';

const _allowedTargets = {'none', 'web', 'android', 'ios', 'macos', 'windows'};
const _allowedSources = {'auto', 'pub', 'path'};

Future<void> main(List<String> args) async {
  try {
    final options = parseLongOptions(
      args,
      defaults: <String, String>{
        'app-root': Directory.current.path,
        'target': 'none',
        'source': 'auto',
      },
      allowedKeys: <String>{'app-root', 'target', 'source', 'wajuce-path'},
    );

    if (options['help'] == 'true') {
      _printUsage();
      return;
    }

    final appRoot = absolutePath(options['app-root']!.trim());
    final target = options['target']!.trim().toLowerCase();
    final source = options['source']!.trim().toLowerCase();
    final wajucePathRaw = (options['wajuce-path'] ?? '').trim();
    final wajucePath = wajucePathRaw.isEmpty
        ? ''
        : absolutePath(options['wajuce-path']!.trim());

    if (!_allowedTargets.contains(target)) {
      throw CliException(
        'Invalid --target: $target (allowed: ${_allowedTargets.join(", ")})',
      );
    }
    if (!_allowedSources.contains(source)) {
      throw CliException(
        'Invalid --source: $source (allowed: ${_allowedSources.join(", ")})',
      );
    }

    _assertFlutterProject(appRoot);
    _assertHostTargetCompatibility(target);

    step('Check Flutter and Dart');
    await _runOrFail('flutter', ['--version'], cwd: appRoot);
    await _runOrFail('dart', ['--version'], cwd: appRoot);

    if (target == 'android' || target == 'windows') {
      await _runDoctorGate(appRoot, target);
    }

    step('Verify dependency in pubspec.yaml');
    _verifyPubspecHasWajuce(appRoot);

    step('Resolve packages');
    await _runOrFail('flutter', ['pub', 'get'], cwd: appRoot);

    step('Verify dependency graph');
    final depsResult = await runCommand(
      'flutter',
      ['pub', 'deps'],
      workingDirectory: appRoot,
      printOutput: false,
    );
    if (depsResult.exitCode != 0) {
      fail('`flutter pub deps` failed.');
    }
    if (!RegExp(r'\bwajuce\b').hasMatch(depsResult.combinedText)) {
      fail('Dependency graph does not include `wajuce`.');
    }
    info('Dependency graph includes `wajuce`.');

    final effectiveSource = _resolveEffectiveSource(appRoot, source);
    info('Detected source: $effectiveSource');

    if (effectiveSource == 'path') {
      if (wajucePath.isEmpty) {
        info(
            'Path source detected but --wajuce-path was not provided. Skip JUCE path checks.');
      } else {
        _verifyJuceModules(wajucePath);
      }
    }

    await _runBuildCheck(appRoot, target);

    info('Definition of Done');
    info('1) pubspec.yaml includes wajuce');
    info('2) flutter pub get succeeded');
    info('3) flutter pub deps includes wajuce');
    if (effectiveSource == 'path' && wajucePath.isNotEmpty) {
      info('4) local JUCE modules path exists');
    }
    if (target == 'none') {
      info('5) build check skipped (target=none)');
    } else {
      info('5) target build succeeded for $target');
    }
    stdout.writeln('[DONE] verify_wajuce completed.');
  } on CliException catch (e) {
    fail(e.message);
  } on ProcessException catch (e) {
    fail('Failed to run command: ${e.executable} ${e.message}');
  }
}

void _printUsage() {
  stdout.writeln('''
Verify wajuce installation in a Flutter app.

Usage:
  dart run tool/verify_wajuce.dart [options]

Options:
  --app-root <path>        Target Flutter app root (default: current directory)
  --target <name>          Optional build check target:
                           none|web|android|ios|macos|windows (default: none)
  --source <auto|pub|path> Install source hint (default: auto)
  --wajuce-path <path>     Optional local plugin path (required only for strict path validation)
  --help

Examples:
  dart run tool/verify_wajuce.dart --app-root /abs/new_app --target android
  dart run tool/verify_wajuce.dart --app-root C:\\work\\new_app --target windows
  dart run tool/verify_wajuce.dart --app-root /abs/new_app --source path --wajuce-path /abs/wajuce --target web
''');
}

void _assertFlutterProject(String appRoot) {
  final appDir = Directory(appRoot);
  if (!appDir.existsSync()) {
    fail('app-root does not exist: $appRoot');
  }
  final pubspec = File('$appRoot/pubspec.yaml');
  if (!pubspec.existsSync()) {
    fail('pubspec.yaml not found at app-root: $appRoot');
  }
}

void _assertHostTargetCompatibility(String target) {
  if (target == 'ios' && !Platform.isMacOS) {
    fail('iOS build check requires macOS host.');
  }
  if (target == 'macos' && !Platform.isMacOS) {
    fail('macOS build check requires macOS host.');
  }
  if (target == 'windows' && !Platform.isWindows) {
    fail('Windows build check requires Windows host.');
  }
}

void _verifyPubspecHasWajuce(String appRoot) {
  final pubspecText = File('$appRoot/pubspec.yaml').readAsStringSync();
  final hasWajuce =
      RegExp(r'^\s+wajuce\s*:', multiLine: true).hasMatch(pubspecText);
  if (!hasWajuce) {
    fail('`pubspec.yaml` does not include a `wajuce` dependency entry.');
  }
  info('pubspec.yaml includes `wajuce`.');
}

void _verifyJuceModules(String wajucePath) {
  final modulesPath = '$wajucePath/native/engine/vendor/JUCE/modules';
  if (!Directory(modulesPath).existsSync()) {
    fail('Missing JUCE modules: $modulesPath');
  }
  info('JUCE modules path exists: $modulesPath');
}

Future<void> _runOrFail(
  String exe,
  List<String> args, {
  required String cwd,
}) async {
  final result = await runCommand(exe, args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    fail('Command failed: $exe ${args.join(" ")}');
  }
}

String _resolveEffectiveSource(String appRoot, String sourceFlag) {
  if (sourceFlag != 'auto') {
    return sourceFlag;
  }

  final lockFile = File('$appRoot/pubspec.lock');
  if (!lockFile.existsSync()) {
    info('pubspec.lock is missing. Source detection fallback: pub');
    return 'pub';
  }

  final sourceFromLock =
      _detectWajuceSourceFromLock(lockFile.readAsStringSync());
  if (sourceFromLock == null) {
    info('Could not detect wajuce source from pubspec.lock. Fallback: pub');
    return 'pub';
  }

  if (sourceFromLock == 'path') {
    return 'path';
  }
  return 'pub';
}

String? _detectWajuceSourceFromLock(String lockText) {
  final lines = lockText.split('\n');
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    if (line.trim() != 'wajuce:' || !line.startsWith('  ')) {
      continue;
    }
    for (var j = i + 1; j < lines.length; j += 1) {
      final candidate = lines[j];
      final candidateTrimmed = candidate.trim();
      if (candidate.startsWith('  ') && !candidate.startsWith('    ')) {
        break;
      }
      if (candidateTrimmed.startsWith('source: ')) {
        return candidateTrimmed.substring('source: '.length).trim();
      }
    }
  }
  return null;
}

Future<void> _runDoctorGate(String appRoot, String target) async {
  step('Validate toolchain for target=$target');
  final doctor = await runCommand(
    'flutter',
    ['doctor', '-v'],
    workingDirectory: appRoot,
    printOutput: true,
  );
  if (doctor.exitCode != 0) {
    fail('`flutter doctor -v` failed.');
  }

  if (target == 'android') {
    final androidLine =
        findDoctorLine(doctor.combinedText, 'Android toolchain');
    if (androidLine == null) {
      fail('Could not find Android toolchain status in flutter doctor output.');
    }
    if (doctorLineIsFail(androidLine)) {
      fail('Android toolchain is not ready: $androidLine');
    }
    info('Android toolchain check passed: $androidLine');
  }

  if (target == 'windows') {
    final vsLine = findDoctorLine(doctor.combinedText, 'Visual Studio');
    if (vsLine == null) {
      fail('Could not find Visual Studio status in flutter doctor output.');
    }
    if (doctorLineIsFail(vsLine)) {
      fail('Visual Studio setup is not ready: $vsLine');
    }
    info('Windows desktop toolchain check passed: $vsLine');
  }
}

Future<void> _runBuildCheck(String appRoot, String target) async {
  if (target == 'none') {
    info('Skip build check: target=none');
    return;
  }

  step('Run build check for target=$target');
  switch (target) {
    case 'web':
      await _runOrFail('flutter', ['build', 'web'], cwd: appRoot);
      return;
    case 'android':
      await _runOrFail('flutter', ['build', 'apk', '--debug'], cwd: appRoot);
      return;
    case 'ios':
      await _runOrFail(
        'flutter',
        ['build', 'ios', '--debug', '--no-codesign'],
        cwd: appRoot,
      );
      return;
    case 'macos':
      await _runOrFail('flutter', ['build', 'macos', '--debug'], cwd: appRoot);
      return;
    case 'windows':
      await _runOrFail('flutter', ['build', 'windows', '--debug'],
          cwd: appRoot);
      return;
    default:
      fail('Unsupported target: $target');
  }
}
