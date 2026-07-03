#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint oto_native.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'oto_native'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI build shim for the oto Rust core.'
  s.description      = <<-DESC
Builds and links the oto Rust core for Flutter targets.
                       DESC
  s.homepage         = 'https://github.com/oszkar/oto'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Oszkar' => 'oszkar@users.noreply.github.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # First argument is relative path to the `rust` folder, second is name of rust library
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../../native oto_native',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    # Let XCode know that the static library referenced in -force_load below is
    # created by this build step.
    :output_files => ["${BUILT_PRODUCTS_DIR}/liboto_native.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # liboto_native pulls the `system_configuration` crate (via reqwest, for
    # proxy detection); its SC*/kSC* symbols live in
    # SystemConfiguration.framework. A Rust staticlib can't carry that link
    # directive, so link the framework here - without it the macOS Runner fails
    # to link (undefined _SCDynamicStore*, _SCNetwork*, _kSCNetworkInterface*).
    # See LOCAL_PATCHES.md #3.
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/liboto_native.a -framework SystemConfiguration',
  }
end