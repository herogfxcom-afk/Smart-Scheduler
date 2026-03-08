// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
      id: (json['id'] as num?)?.toInt(),
      telegramId: (json['telegram_id'] as num).toInt(),
      firstName: json['first_name'] as String?,
      username: json['username'] as String?,
      photoUrl: json['photo_url'] as String?,
      isConnected: json['is_connected'] as bool? ?? false,
      isAppleConnected: json['is_apple_connected'] as bool? ?? false,
    );

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
      'id': instance.id,
      'telegram_id': instance.telegramId,
      'first_name': instance.firstName,
      'username': instance.username,
      'photo_url': instance.photoUrl,
      'is_connected': instance.isConnected,
      'is_apple_connected': instance.isAppleConnected,
    };
