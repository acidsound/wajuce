import 'dart:io';

import '_wajuce_cli.dart';

const _allowedSources = {'pub', 'path'};
const _allowedTargets = {'none', 'web', 'android', 'ios', 'macos', 'windows'};

Future<void> main(List<String> args) async {
  try {
    final options = parseLongOptions(
      args,
      defaults: <String, String>{
        'app-root': Directory.current.path,
        'source': 'pub',
        'target': 'none',
      },
      allowedKeys: <String>{'app-root', 'source', 'target', 'wajuce-path'},
    );

    if (options['help'] == 'true') {
      _printUsage();
      return;
    }

    final appRoot = absolutePath(options['app-root']!.trim());
    final source = options['source']!.trim().toLowerCase();
    final target = options['target']!.trim().toLowerCase();
    final wajucePathRaw = (options['wajuce-path'] ?? '').trim();
    final wajucePath = wajucePathRaw.isEmpty
        ? ''
        : absolutePath(options['wajuce-path']!.trim());

    if (!_allowedSources.contains(source)) {
      throw CliException(
        'Invalid --source: $source (allowed: ${_allowedSources.join(", ")})',
      );
    }
    if (!_allowedTargets.contains(target)) {
      throw CliException(
        'Invalid --target: $target (allowed: ${_allowedTargets.join(", ")})',
      );
    }

    _assertHostTargetCompatibility(target);
    _assertFlutterProject(appRoot);

    step('Check Flutter and Dart');
    await _runOrFail('flutter', ['--version'], cwd: appRoot);
    await _runOrFail('dart', ['--version'], cwd: appRoot);

    if (source == 'path') {
      if (wajucePath.isEmpty) {
        fail('When --source=path, --wajuce-path is required.');
      }
      await _preparePathSource(wajucePath);
    }

    if (target == 'android' || target == 'windows') {
      await _runDoctorGate(appRoot, target);
    }

    step('Add wajuce dependency');
    if (source == 'pub') {
      await _runOrFail('flutter', ['pub', 'add', 'wajuce'], cwd: appRoot);
    } else {
      await _runOrFail(
        'flutter',
        ['pub', 'add', 'wajuce', '--path', wajucePath],
        cwd: appRoot,
      );
    }

    step('Resolve packages');
    await _runOrFail('flutter', ['pub', 'get'], cwd: appRoot);

    step('Verify dependency in pubspec.yaml');
    _verifyPubspecHasWajuce(appRoot);

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

    await _runBuildCheck(appRoot, target);

    info('Definition of Done');
    info('1) pubspec.yaml includes wajuce');
    info('2) flutter pub get succeeded');
    info('3) flutter pub deps includes wajuce');
    if (target == 'none') {
      info('4) build check skipped (target=none)');
    } else {
      info('4) target build succeeded for $target');
    }
    stdout.writeln('[DONE] install_wajuce completed.');
  } on CliException catch (e) {
    fail(e.message);
  } on ProcessException catch (e) {
    fail('Failed to run command: ${e.executable} ${e.message}');
  }
}

void _printUsage() {
  stdout.writeln('''
Install wajuce in a Flutter app with deterministic checks.

Usage:
  dart run tool/install_wajuce.dart [options]

Options:
  --app-root <path>        Target Flutter app root (default: current directory)
  --source <pub|path>      Dependency source (default: pub)
  --wajuce-path <path>     Required only when --source=path
  --target <name>          Optional build check target:
                           none|web|android|ios|macos|windows (default: none)
  --help

Examples:
  dart run tool/install_wajuce.dart --app-root /abs/new_app --source pub --target android
  dart run tool/install_wajuce.dart --app-root C:\\work\\new_app --source pub --target windows
  dart run tool/install_wajuce.dart --app-root /abs/new_app --source path --wajuce-path /abs/wajuce --target web
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

Future<void> _preparePathSource(String wajucePath) async {
  final root = Directory(wajucePath);
  if (!root.existsSync()) {
    fail('wajuce-path does not exist: $wajucePath');
  }

  final juceModules =
      Directory('$wajucePath/native/engine/vendor/JUCE/modules');
  if (juceModules.existsSync()) {
    info('JUCE modules found: ${juceModules.path}');
    return;
  }

  final gitMetadataType = FileSystemEntity.typeSync('$wajucePath/.git');
  if (gitMetadataType == FileSystemEntityType.notFound) {
    fail(
      'Missing JUCE modules and no git metadata at $wajucePath. '
      'Provide a wajuce checkout with JUCE vendored/submodules initialized.',
    );
  }

  info('JUCE modules missing. Trying: git submodule update --init --recursive');
  final result = await runCommand(
    'git',
    ['-C', wajucePath, 'submodule', 'update', '--init', '--recursive'],
    workingDirectory: wajucePath,
  );
  if (result.exitCode != 0) {
    fail('Failed to initialize JUCE submodule in $wajucePath.');
  }

  if (!juceModules.existsSync()) {
    fail(
        'JUCE modules still missing after submodule update: ${juceModules.path}');
  }
  info('JUCE modules initialized: ${juceModules.path}');
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
