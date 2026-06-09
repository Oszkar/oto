// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sources.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(sources)
final sourcesProvider = SourcesProvider._();

final class SourcesProvider
    extends $FunctionalProvider<List<Source>, List<Source>, List<Source>>
    with $Provider<List<Source>> {
  SourcesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourcesHash();

  @$internal
  @override
  $ProviderElement<List<Source>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<Source> create(Ref ref) {
    return sources(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Source> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Source>>(value),
    );
  }
}

String _$sourcesHash() => r'68809a56bd620122f39b7a69664f124934d8ea33';
