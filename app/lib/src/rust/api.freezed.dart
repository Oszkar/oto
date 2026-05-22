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
mixin _$ChangeEventDto {

 String get speakerId;
/// Create a copy of ChangeEventDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangeEventDtoCopyWith<ChangeEventDto> get copyWith => _$ChangeEventDtoCopyWithImpl<ChangeEventDto>(this as ChangeEventDto, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeEventDto&&(identical(other.speakerId, speakerId) || other.speakerId == speakerId));
}


@override
int get hashCode => Object.hash(runtimeType,speakerId);

@override
String toString() {
  return 'ChangeEventDto(speakerId: $speakerId)';
}


}

/// @nodoc
abstract mixin class $ChangeEventDtoCopyWith<$Res>  {
  factory $ChangeEventDtoCopyWith(ChangeEventDto value, $Res Function(ChangeEventDto) _then) = _$ChangeEventDtoCopyWithImpl;
@useResult
$Res call({
 String speakerId
});




}
/// @nodoc
class _$ChangeEventDtoCopyWithImpl<$Res>
    implements $ChangeEventDtoCopyWith<$Res> {
  _$ChangeEventDtoCopyWithImpl(this._self, this._then);

  final ChangeEventDto _self;
  final $Res Function(ChangeEventDto) _then;

/// Create a copy of ChangeEventDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? speakerId = null,}) {
  return _then(_self.copyWith(
speakerId: null == speakerId ? _self.speakerId : speakerId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ChangeEventDto].
extension ChangeEventDtoPatterns on ChangeEventDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ChangeEventDto_Volume value)?  volume,TResult Function( ChangeEventDto_SubscriptionError value)?  subscriptionError,TResult Function( ChangeEventDto_SubscriptionRecovered value)?  subscriptionRecovered,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ChangeEventDto_Volume() when volume != null:
return volume(_that);case ChangeEventDto_SubscriptionError() when subscriptionError != null:
return subscriptionError(_that);case ChangeEventDto_SubscriptionRecovered() when subscriptionRecovered != null:
return subscriptionRecovered(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ChangeEventDto_Volume value)  volume,required TResult Function( ChangeEventDto_SubscriptionError value)  subscriptionError,required TResult Function( ChangeEventDto_SubscriptionRecovered value)  subscriptionRecovered,}){
final _that = this;
switch (_that) {
case ChangeEventDto_Volume():
return volume(_that);case ChangeEventDto_SubscriptionError():
return subscriptionError(_that);case ChangeEventDto_SubscriptionRecovered():
return subscriptionRecovered(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ChangeEventDto_Volume value)?  volume,TResult? Function( ChangeEventDto_SubscriptionError value)?  subscriptionError,TResult? Function( ChangeEventDto_SubscriptionRecovered value)?  subscriptionRecovered,}){
final _that = this;
switch (_that) {
case ChangeEventDto_Volume() when volume != null:
return volume(_that);case ChangeEventDto_SubscriptionError() when subscriptionError != null:
return subscriptionError(_that);case ChangeEventDto_SubscriptionRecovered() when subscriptionRecovered != null:
return subscriptionRecovered(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String speakerId,  int volume)?  volume,TResult Function( String speakerId,  String message)?  subscriptionError,TResult Function( String speakerId)?  subscriptionRecovered,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ChangeEventDto_Volume() when volume != null:
return volume(_that.speakerId,_that.volume);case ChangeEventDto_SubscriptionError() when subscriptionError != null:
return subscriptionError(_that.speakerId,_that.message);case ChangeEventDto_SubscriptionRecovered() when subscriptionRecovered != null:
return subscriptionRecovered(_that.speakerId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String speakerId,  int volume)  volume,required TResult Function( String speakerId,  String message)  subscriptionError,required TResult Function( String speakerId)  subscriptionRecovered,}) {final _that = this;
switch (_that) {
case ChangeEventDto_Volume():
return volume(_that.speakerId,_that.volume);case ChangeEventDto_SubscriptionError():
return subscriptionError(_that.speakerId,_that.message);case ChangeEventDto_SubscriptionRecovered():
return subscriptionRecovered(_that.speakerId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String speakerId,  int volume)?  volume,TResult? Function( String speakerId,  String message)?  subscriptionError,TResult? Function( String speakerId)?  subscriptionRecovered,}) {final _that = this;
switch (_that) {
case ChangeEventDto_Volume() when volume != null:
return volume(_that.speakerId,_that.volume);case ChangeEventDto_SubscriptionError() when subscriptionError != null:
return subscriptionError(_that.speakerId,_that.message);case ChangeEventDto_SubscriptionRecovered() when subscriptionRecovered != null:
return subscriptionRecovered(_that.speakerId);case _:
  return null;

}
}

}

/// @nodoc


class ChangeEventDto_Volume extends ChangeEventDto {
  const ChangeEventDto_Volume({required this.speakerId, required this.volume}): super._();
  

@override final  String speakerId;
 final  int volume;

/// Create a copy of ChangeEventDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangeEventDto_VolumeCopyWith<ChangeEventDto_Volume> get copyWith => _$ChangeEventDto_VolumeCopyWithImpl<ChangeEventDto_Volume>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeEventDto_Volume&&(identical(other.speakerId, speakerId) || other.speakerId == speakerId)&&(identical(other.volume, volume) || other.volume == volume));
}


@override
int get hashCode => Object.hash(runtimeType,speakerId,volume);

@override
String toString() {
  return 'ChangeEventDto.volume(speakerId: $speakerId, volume: $volume)';
}


}

/// @nodoc
abstract mixin class $ChangeEventDto_VolumeCopyWith<$Res> implements $ChangeEventDtoCopyWith<$Res> {
  factory $ChangeEventDto_VolumeCopyWith(ChangeEventDto_Volume value, $Res Function(ChangeEventDto_Volume) _then) = _$ChangeEventDto_VolumeCopyWithImpl;
@override @useResult
$Res call({
 String speakerId, int volume
});




}
/// @nodoc
class _$ChangeEventDto_VolumeCopyWithImpl<$Res>
    implements $ChangeEventDto_VolumeCopyWith<$Res> {
  _$ChangeEventDto_VolumeCopyWithImpl(this._self, this._then);

  final ChangeEventDto_Volume _self;
  final $Res Function(ChangeEventDto_Volume) _then;

/// Create a copy of ChangeEventDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? speakerId = null,Object? volume = null,}) {
  return _then(ChangeEventDto_Volume(
speakerId: null == speakerId ? _self.speakerId : speakerId // ignore: cast_nullable_to_non_nullable
as String,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ChangeEventDto_SubscriptionError extends ChangeEventDto {
  const ChangeEventDto_SubscriptionError({required this.speakerId, required this.message}): super._();
  

@override final  String speakerId;
 final  String message;

/// Create a copy of ChangeEventDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangeEventDto_SubscriptionErrorCopyWith<ChangeEventDto_SubscriptionError> get copyWith => _$ChangeEventDto_SubscriptionErrorCopyWithImpl<ChangeEventDto_SubscriptionError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeEventDto_SubscriptionError&&(identical(other.speakerId, speakerId) || other.speakerId == speakerId)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,speakerId,message);

@override
String toString() {
  return 'ChangeEventDto.subscriptionError(speakerId: $speakerId, message: $message)';
}


}

/// @nodoc
abstract mixin class $ChangeEventDto_SubscriptionErrorCopyWith<$Res> implements $ChangeEventDtoCopyWith<$Res> {
  factory $ChangeEventDto_SubscriptionErrorCopyWith(ChangeEventDto_SubscriptionError value, $Res Function(ChangeEventDto_SubscriptionError) _then) = _$ChangeEventDto_SubscriptionErrorCopyWithImpl;
@override @useResult
$Res call({
 String speakerId, String message
});




}
/// @nodoc
class _$ChangeEventDto_SubscriptionErrorCopyWithImpl<$Res>
    implements $ChangeEventDto_SubscriptionErrorCopyWith<$Res> {
  _$ChangeEventDto_SubscriptionErrorCopyWithImpl(this._self, this._then);

  final ChangeEventDto_SubscriptionError _self;
  final $Res Function(ChangeEventDto_SubscriptionError) _then;

/// Create a copy of ChangeEventDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? speakerId = null,Object? message = null,}) {
  return _then(ChangeEventDto_SubscriptionError(
speakerId: null == speakerId ? _self.speakerId : speakerId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ChangeEventDto_SubscriptionRecovered extends ChangeEventDto {
  const ChangeEventDto_SubscriptionRecovered({required this.speakerId}): super._();
  

@override final  String speakerId;

/// Create a copy of ChangeEventDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChangeEventDto_SubscriptionRecoveredCopyWith<ChangeEventDto_SubscriptionRecovered> get copyWith => _$ChangeEventDto_SubscriptionRecoveredCopyWithImpl<ChangeEventDto_SubscriptionRecovered>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChangeEventDto_SubscriptionRecovered&&(identical(other.speakerId, speakerId) || other.speakerId == speakerId));
}


@override
int get hashCode => Object.hash(runtimeType,speakerId);

@override
String toString() {
  return 'ChangeEventDto.subscriptionRecovered(speakerId: $speakerId)';
}


}

/// @nodoc
abstract mixin class $ChangeEventDto_SubscriptionRecoveredCopyWith<$Res> implements $ChangeEventDtoCopyWith<$Res> {
  factory $ChangeEventDto_SubscriptionRecoveredCopyWith(ChangeEventDto_SubscriptionRecovered value, $Res Function(ChangeEventDto_SubscriptionRecovered) _then) = _$ChangeEventDto_SubscriptionRecoveredCopyWithImpl;
@override @useResult
$Res call({
 String speakerId
});




}
/// @nodoc
class _$ChangeEventDto_SubscriptionRecoveredCopyWithImpl<$Res>
    implements $ChangeEventDto_SubscriptionRecoveredCopyWith<$Res> {
  _$ChangeEventDto_SubscriptionRecoveredCopyWithImpl(this._self, this._then);

  final ChangeEventDto_SubscriptionRecovered _self;
  final $Res Function(ChangeEventDto_SubscriptionRecovered) _then;

/// Create a copy of ChangeEventDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? speakerId = null,}) {
  return _then(ChangeEventDto_SubscriptionRecovered(
speakerId: null == speakerId ? _self.speakerId : speakerId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$CommandError {

 String get field0;
/// Create a copy of CommandError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandErrorCopyWith<CommandError> get copyWith => _$CommandErrorCopyWithImpl<CommandError>(this as CommandError, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'CommandError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $CommandErrorCopyWith<$Res>  {
  factory $CommandErrorCopyWith(CommandError value, $Res Function(CommandError) _then) = _$CommandErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$CommandErrorCopyWithImpl<$Res>
    implements $CommandErrorCopyWith<$Res> {
  _$CommandErrorCopyWithImpl(this._self, this._then);

  final CommandError _self;
  final $Res Function(CommandError) _then;

/// Create a copy of CommandError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field0 = null,}) {
  return _then(_self.copyWith(
field0: null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CommandError].
extension CommandErrorPatterns on CommandError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CommandError_NotFound value)?  notFound,TResult Function( CommandError_Network value)?  network,TResult Function( CommandError_Sonos value)?  sonos,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CommandError_NotFound() when notFound != null:
return notFound(_that);case CommandError_Network() when network != null:
return network(_that);case CommandError_Sonos() when sonos != null:
return sonos(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CommandError_NotFound value)  notFound,required TResult Function( CommandError_Network value)  network,required TResult Function( CommandError_Sonos value)  sonos,}){
final _that = this;
switch (_that) {
case CommandError_NotFound():
return notFound(_that);case CommandError_Network():
return network(_that);case CommandError_Sonos():
return sonos(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CommandError_NotFound value)?  notFound,TResult? Function( CommandError_Network value)?  network,TResult? Function( CommandError_Sonos value)?  sonos,}){
final _that = this;
switch (_that) {
case CommandError_NotFound() when notFound != null:
return notFound(_that);case CommandError_Network() when network != null:
return network(_that);case CommandError_Sonos() when sonos != null:
return sonos(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  notFound,TResult Function( String field0)?  network,TResult Function( String field0)?  sonos,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CommandError_NotFound() when notFound != null:
return notFound(_that.field0);case CommandError_Network() when network != null:
return network(_that.field0);case CommandError_Sonos() when sonos != null:
return sonos(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  notFound,required TResult Function( String field0)  network,required TResult Function( String field0)  sonos,}) {final _that = this;
switch (_that) {
case CommandError_NotFound():
return notFound(_that.field0);case CommandError_Network():
return network(_that.field0);case CommandError_Sonos():
return sonos(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  notFound,TResult? Function( String field0)?  network,TResult? Function( String field0)?  sonos,}) {final _that = this;
switch (_that) {
case CommandError_NotFound() when notFound != null:
return notFound(_that.field0);case CommandError_Network() when network != null:
return network(_that.field0);case CommandError_Sonos() when sonos != null:
return sonos(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class CommandError_NotFound extends CommandError {
  const CommandError_NotFound(this.field0): super._();
  

@override final  String field0;

/// Create a copy of CommandError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandError_NotFoundCopyWith<CommandError_NotFound> get copyWith => _$CommandError_NotFoundCopyWithImpl<CommandError_NotFound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandError_NotFound&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'CommandError.notFound(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $CommandError_NotFoundCopyWith<$Res> implements $CommandErrorCopyWith<$Res> {
  factory $CommandError_NotFoundCopyWith(CommandError_NotFound value, $Res Function(CommandError_NotFound) _then) = _$CommandError_NotFoundCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$CommandError_NotFoundCopyWithImpl<$Res>
    implements $CommandError_NotFoundCopyWith<$Res> {
  _$CommandError_NotFoundCopyWithImpl(this._self, this._then);

  final CommandError_NotFound _self;
  final $Res Function(CommandError_NotFound) _then;

/// Create a copy of CommandError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(CommandError_NotFound(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CommandError_Network extends CommandError {
  const CommandError_Network(this.field0): super._();
  

@override final  String field0;

/// Create a copy of CommandError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandError_NetworkCopyWith<CommandError_Network> get copyWith => _$CommandError_NetworkCopyWithImpl<CommandError_Network>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandError_Network&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'CommandError.network(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $CommandError_NetworkCopyWith<$Res> implements $CommandErrorCopyWith<$Res> {
  factory $CommandError_NetworkCopyWith(CommandError_Network value, $Res Function(CommandError_Network) _then) = _$CommandError_NetworkCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$CommandError_NetworkCopyWithImpl<$Res>
    implements $CommandError_NetworkCopyWith<$Res> {
  _$CommandError_NetworkCopyWithImpl(this._self, this._then);

  final CommandError_Network _self;
  final $Res Function(CommandError_Network) _then;

/// Create a copy of CommandError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(CommandError_Network(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CommandError_Sonos extends CommandError {
  const CommandError_Sonos(this.field0): super._();
  

@override final  String field0;

/// Create a copy of CommandError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandError_SonosCopyWith<CommandError_Sonos> get copyWith => _$CommandError_SonosCopyWithImpl<CommandError_Sonos>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandError_Sonos&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'CommandError.sonos(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $CommandError_SonosCopyWith<$Res> implements $CommandErrorCopyWith<$Res> {
  factory $CommandError_SonosCopyWith(CommandError_Sonos value, $Res Function(CommandError_Sonos) _then) = _$CommandError_SonosCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$CommandError_SonosCopyWithImpl<$Res>
    implements $CommandError_SonosCopyWith<$Res> {
  _$CommandError_SonosCopyWithImpl(this._self, this._then);

  final CommandError_Sonos _self;
  final $Res Function(CommandError_Sonos) _then;

/// Create a copy of CommandError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(CommandError_Sonos(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

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
