import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class User {
  final int? id;
  final int telegramId;
  final String? firstName;
  final String? username;
  final String? photoUrl;
  final bool isConnected;
  final bool isAppleConnected;

  User({
    this.id,
    required this.telegramId,
    this.firstName,
    this.username,
    this.photoUrl,
    this.isConnected = false,
    this.isAppleConnected = false,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}
