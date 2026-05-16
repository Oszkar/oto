// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DiscoveryError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiscoveryError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DiscoveryError()';
}


}

/// @nodoc
class $DiscoveryErrorCopyWith<$Res>  {
$DiscoveryErrorCopyWith(DiscoveryError _, $Res Function(DiscoveryError) __);
}


/// Adds pattern-matching-related methods to [DiscoveryError].
extension DiscoveryErrorPatterns on DiscoveryError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DiscoveryError_Network value)?  network,TResult Function( DiscoveryError_NoDevicesFound value)?  noDevicesFound,TResult Function( DiscoveryError_Sdk value)?  sdk,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DiscoveryError_Network() when network != null:
return network(_that);case DiscoveryError_NoDevicesFound() when noDevicesFound != null:
return noDevicesFound(_that);case DiscoveryError_Sdk() when sdk != null:
return sdk(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DiscoveryError_Network value)  network,required TResult Function( DiscoveryError_NoDevicesFound value)  noDevicesFound,required TResult Function( DiscoveryError_Sdk value)  sdk,}){
final _that = this;
switch (_that) {
case DiscoveryError_Network():
return network(_that);case DiscoveryError_NoDevicesFound():
return noDevicesFound(_that);case DiscoveryError_Sdk():
return sdk(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DiscoveryError_Network value)?  network,TResult? Function( DiscoveryError_NoDevicesFound value)?  noDevicesFound,TResult? Function( DiscoveryError_Sdk value)?  sdk,}){
final _that = this;
switch (_that) {
case DiscoveryError_Network() when network != null:
return network(_that);case DiscoveryError_NoDevicesFound() when noDevicesFound != null:
return noDevicesFound(_that);case DiscoveryError_Sdk() when sdk != null:
return sdk(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  network,TResult Function()?  noDevicesFound,TResult Function( String field0)?  sdk,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DiscoveryError_Network() when network != null:
return network(_that.field0);case DiscoveryError_NoDevicesFound() when noDevicesFound != null:
return noDevicesFound();case DiscoveryError_Sdk() when sdk != null:
return sdk(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  network,required TResult Function()  noDevicesFound,required TResult Function( String field0)  sdk,}) {final _that = this;
switch (_that) {
case DiscoveryError_Network():
return network(_that.field0);case DiscoveryError_NoDevicesFound():
return noDevicesFound();case DiscoveryError_Sdk():
return sdk(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  network,TResult? Function()?  noDevicesFound,TResult? Function( String field0)?  sdk,}) {final _that = this;
switch (_that) {
case DiscoveryError_Network() when network != null:
return network(_that.field0);case DiscoveryError_NoDevicesFound() when noDevicesFound != null:
return noDevicesFound();case DiscoveryError_Sdk() when sdk != null:
return sdk(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class DiscoveryError_Network extends DiscoveryError {
  const DiscoveryError_Network(this.field0): super._();
  

 final  String field0;

/// Create a copy of DiscoveryError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiscoveryError_NetworkCopyWith<DiscoveryError_Network> get copyWith => _$DiscoveryError_NetworkCopyWithImpl<DiscoveryError_Network>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiscoveryError_Network&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DiscoveryError.network(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DiscoveryError_NetworkCopyWith<$Res> implements $DiscoveryErrorCopyWith<$Res> {
  factory $DiscoveryError_NetworkCopyWith(DiscoveryError_Network value, $Res Function(DiscoveryError_Network) _then) = _$DiscoveryError_NetworkCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$DiscoveryError_NetworkCopyWithImpl<$Res>
    implements $DiscoveryError_NetworkCopyWith<$Res> {
  _$DiscoveryError_NetworkCopyWithImpl(this._self, this._then);

  final DiscoveryError_Network _self;
  final $Res Function(DiscoveryError_Network) _then;

/// Create a copy of DiscoveryError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DiscoveryError_Network(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DiscoveryError_NoDevicesFound extends DiscoveryError {
  const DiscoveryError_NoDevicesFound(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiscoveryError_NoDevicesFound);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DiscoveryError.noDevicesFound()';
}


}




/// @nodoc


class DiscoveryError_Sdk extends DiscoveryError {
  const DiscoveryError_Sdk(this.field0): super._();
  

 final  String field0;

/// Create a copy of DiscoveryError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiscoveryError_SdkCopyWith<DiscoveryError_Sdk> get copyWith => _$DiscoveryError_SdkCopyWithImpl<DiscoveryError_Sdk>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiscoveryError_Sdk&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'DiscoveryError.sdk(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DiscoveryError_SdkCopyWith<$Res> implements $DiscoveryErrorCopyWith<$Res> {
  factory $DiscoveryError_SdkCopyWith(DiscoveryError_Sdk value, $Res Function(DiscoveryError_Sdk) _then) = _$DiscoveryError_SdkCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$DiscoveryError_SdkCopyWithImpl<$Res>
    implements $DiscoveryError_SdkCopyWith<$Res> {
  _$DiscoveryError_SdkCopyWithImpl(this._self, this._then);

  final DiscoveryError_Sdk _self;
  final $Res Function(DiscoveryError_Sdk) _then;

/// Create a copy of DiscoveryError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DiscoveryError_Sdk(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
