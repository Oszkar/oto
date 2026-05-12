// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'greeting.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Demo provider — calls the Rust `greet` function over the FRB bridge.
///
/// Once real Sonos providers exist this can go away. It exists in the scaffold
/// to prove that Riverpod, the FRB bridge, and `ConsumerWidget` are wired up
/// end-to-end.

@ProviderFor(greeting)
const greetingProvider = GreetingFamily._();

/// Demo provider — calls the Rust `greet` function over the FRB bridge.
///
/// Once real Sonos providers exist this can go away. It exists in the scaffold
/// to prove that Riverpod, the FRB bridge, and `ConsumerWidget` are wired up
/// end-to-end.

final class GreetingProvider extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// Demo provider — calls the Rust `greet` function over the FRB bridge.
  ///
  /// Once real Sonos providers exist this can go away. It exists in the scaffold
  /// to prove that Riverpod, the FRB bridge, and `ConsumerWidget` are wired up
  /// end-to-end.
  const GreetingProvider._({
    required GreetingFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'greetingProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$greetingHash();

  @override
  String toString() {
    return r'greetingProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    final argument = this.argument as String;
    return greeting(ref, name: argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GreetingProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$greetingHash() => r'a81499f0a73237e1ff3b8d87e33c9b5c6ef1ae85';

/// Demo provider — calls the Rust `greet` function over the FRB bridge.
///
/// Once real Sonos providers exist this can go away. It exists in the scaffold
/// to prove that Riverpod, the FRB bridge, and `ConsumerWidget` are wired up
/// end-to-end.

final class GreetingFamily extends $Family
    with $FunctionalFamilyOverride<String, String> {
  const GreetingFamily._()
    : super(
        retry: null,
        name: r'greetingProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Demo provider — calls the Rust `greet` function over the FRB bridge.
  ///
  /// Once real Sonos providers exist this can go away. It exists in the scaffold
  /// to prove that Riverpod, the FRB bridge, and `ConsumerWidget` are wired up
  /// end-to-end.

  GreetingProvider call({required String name}) =>
      GreetingProvider._(argument: name, from: this);

  @override
  String toString() => r'greetingProvider';
}
