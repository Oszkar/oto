import 'package:build_tool/src/builder.dart';
import 'package:build_tool/src/cargo.dart';
import 'package:build_tool/src/options.dart';
import 'package:build_tool/src/rustup.dart';
import 'package:build_tool/src/target.dart';
import 'package:build_tool/src/util.dart';

Future<void> main() async {
  const pinned = '1.99.1-x86_64-pc-windows-msvc';
  const target = 'x86_64-pc-windows-msvc';
  late List<TestRunCommandArgs> calls;

  void setUp() {
    calls = [];
    testRunCommandOverride = (args) {
      calls.add(args);
      final command = args.arguments.join(' ');
      return TestRunCommandResult(
          stdout: switch (command) {
        'toolchain list' => 'stable-$target (default)\n$pinned (active)\n',
        'show active-toolchain' =>
          '$pinned (overridden by rust-toolchain.toml)\n',
        _ => '$target\n',
      });
    };
  }

  RustBuilder builder(CargokitCrateOptions options) => RustBuilder(
        target: Target(rust: target),
        environment: BuildEnvironment(
          configuration: BuildConfiguration.debug,
          crateOptions: options,
          targetTempDir: 'build',
          manifestDir: 'repo/native',
          crateInfo: CrateInfo(packageName: 'oto_native'),
          isAndroid: false,
        ),
      );

  setUp();
  try {
    final rustup = Rustup();
    final build = builder(CargokitCrateOptions());
    build.prepare(rustup);
    await build.build();
    final resolution = calls.singleWhere(
        (args) => args.arguments.join(' ') == 'show active-toolchain');
    if (resolution.workingDirectory != 'repo/native') {
      throw StateError('wrong toolchain resolution directory');
    }
    if (calls.last.arguments.take(3).join(' ') != 'run $pinned cargo') {
      throw StateError('repository compiler pin ignored');
    }
    if (calls.any((args) => args.arguments.contains('install'))) {
      throw StateError('installed numbered toolchain not recognized');
    }
    calls.clear();
    final explicitBuild = builder(CargokitCrateOptions(cargo: {
      BuildConfiguration.debug:
          CargoBuildOptions(toolchain: Toolchain.stable, flags: []),
    }));
    await explicitBuild.build();
    if (calls.single.arguments.take(3).join(' ') != 'run stable cargo') {
      throw StateError('explicit compiler override ignored');
    }
    print('Cargokit toolchain checks passed');
  } finally {
    testRunCommandOverride = null;
  }
}
