import 'dart:convert';
import 'dart:io';

class CliException implements Exception {
  CliException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CommandResult {
  CommandResult({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;

  String get combinedText => '$stdoutText\n$stderrText';
}

Map<String, String> parseLongOptions(
  List<String> args, {
  required Map<String, String> defaults,
  required Set<String> allowedKeys,
}) {
  final parsed = <String, String>{...defaults};
  var i = 0;
  while (i < args.length) {
    final token = args[i];
    if (!token.startsWith('--')) {
      throw CliException('Unexpected argument: $token');
    }
    if (token == '--help') {
      parsed['help'] = 'true';
      i += 1;
      continue;
    }

    final eq = token.indexOf('=');
    if (eq != -1) {
      final key = token.substring(2, eq).trim();
      final value = token.substring(eq + 1).trim();
      if (!allowedKeys.contains(key)) {
        throw CliException('Unknown option: --$key');
      }
      if (value.isEmpty) {
        throw CliException('Missing value for --$key');
      }
      parsed[key] = value;
      i += 1;
      continue;
    }

    final key = token.substring(2).trim();
    if (!allowedKeys.contains(key)) {
      throw CliException('Unknown option: --$key');
    }
    if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
      throw CliException('Missing value for --$key');
    }
    parsed[key] = args[i + 1];
    i += 2;
  }
  return parsed;
}

String absolutePath(String path) {
  if (path.isEmpty) {
    return Directory.current.absolute.path;
  }
  return Directory(path).absolute.path;
}

Future<CommandResult> runCommand(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  bool printOutput = true,
}) async {
  stdout.writeln('\$ ${_displayCommand(executable, arguments)}');

  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: true,
  );

  final outBuffer = StringBuffer();
  final errBuffer = StringBuffer();

  final stdoutDone = process.stdout.transform(utf8.decoder).listen((chunk) {
    outBuffer.write(chunk);
    if (printOutput) {
      stdout.write(chunk);
    }
  }).asFuture<void>();

  final stderrDone = process.stderr.transform(utf8.decoder).listen((chunk) {
    errBuffer.write(chunk);
    if (printOutput) {
      stderr.write(chunk);
    }
  }).asFuture<void>();

  final exitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);

  return CommandResult(
    exitCode: exitCode,
    stdoutText: outBuffer.toString(),
    stderrText: errBuffer.toString(),
  );
}

String? findDoctorLine(String doctorText, String contains) {
  for (final rawLine in doctorText.split('\n')) {
    final line = rawLine.trimRight();
    if (line.contains(contains)) {
      return line;
    }
  }
  return null;
}

bool doctorLineIsFail(String line) {
  return line.contains('[x]') || line.contains('[!]');
}

Never fail(String message) {
  stderr.writeln('[FAIL] $message');
  exit(1);
}

void info(String message) {
  stdout.writeln('[INFO] $message');
}

void step(String message) {
  stdout.writeln('[STEP] $message');
}

String _displayCommand(String executable, List<String> arguments) {
  final pieces = <String>[executable, ...arguments];
  return pieces.map(_shellQuote).join(' ');
}

String _shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  final safe = RegExp(r'^[a-zA-Z0-9_./:\\-]+$');
  if (safe.hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", r"'\''")}'";
}
