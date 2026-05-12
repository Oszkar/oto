import 'dart:convert';
import 'dart:io';

const generatedPathspecs = [
  'app/lib/src/rust',
  'native/src/frb_generated.rs',
  'native/src/frb_generated.io.rs',
  'native/src/frb_generated.web.rs',
  ':(glob)**/*.g.dart',
  ':(glob)**/*.freezed.dart',
];

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.path;

  await _run('flutter_rust_bridge_codegen', [
    'generate',
  ], workingDirectory: '$root/app');
  await _run('dart', [
    'run',
    'build_runner',
    'build',
  ], workingDirectory: '$root/app');
  await _run(
    'git',
    ['diff', '--exit-code', '--', ...generatedPathspecs],
    workingDirectory: root,
    failureMessage:
        'Generated files changed. Review and stage the generated output.',
  );

  final untracked = await Process.run(
    'git',
    ['ls-files', '--others', '--exclude-standard', '--', ...generatedPathspecs],
    workingDirectory: root,
    runInShell: Platform.isWindows,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  if (untracked.exitCode != 0) {
    stdout.write(untracked.stdout);
    stderr.write(untracked.stderr);
    exit(untracked.exitCode);
  }

  final untrackedFiles = (untracked.stdout as String).trim();
  if (untrackedFiles.isNotEmpty) {
    stderr.writeln(
      'Generated files are untracked. Stage them before committing:',
    );
    stderr.writeln(untrackedFiles);
    exit(1);
  }
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  String? failureMessage,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );

  process.stdout.listen(stdout.add);
  process.stderr.listen(stderr.add);

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    if (failureMessage != null) {
      stderr.writeln(failureMessage);
    }
    exit(exitCode);
  }
}
