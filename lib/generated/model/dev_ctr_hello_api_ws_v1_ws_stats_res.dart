//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DevCtrHelloApiWsV1WsStatsRes {
  /// Returns a new [DevCtrHelloApiWsV1WsStatsRes] instance.
  DevCtrHelloApiWsV1WsStatsRes({
    this.totalConnections,
    this.activeConnections,
    this.messagesSent,
    this.messagesReceived,
    this.totalRooms,
  });

  /// Total connections
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? totalConnections;

  /// Active connections
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? activeConnections;

  /// Messages sent
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? messagesSent;

  /// Messages received
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? messagesReceived;

  /// Total rooms
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? totalRooms;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DevCtrHelloApiWsV1WsStatsRes &&
    other.totalConnections == totalConnections &&
    other.activeConnections == activeConnections &&
    other.messagesSent == messagesSent &&
    other.messagesReceived == messagesReceived &&
    other.totalRooms == totalRooms;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (totalConnections == null ? 0 : totalConnections!.hashCode) +
    (activeConnections == null ? 0 : activeConnections!.hashCode) +
    (messagesSent == null ? 0 : messagesSent!.hashCode) +
    (messagesReceived == null ? 0 : messagesReceived!.hashCode) +
    (totalRooms == null ? 0 : totalRooms!.hashCode);

  @override
  String toString() => 'DevCtrHelloApiWsV1WsStatsRes[totalConnections=$totalConnections, activeConnections=$activeConnections, messagesSent=$messagesSent, messagesReceived=$messagesReceived, totalRooms=$totalRooms]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.totalConnections != null) {
      json[r'total_connections'] = this.totalConnections;
    } else {
      json[r'total_connections'] = null;
    }
    if (this.activeConnections != null) {
      json[r'active_connections'] = this.activeConnections;
    } else {
      json[r'active_connections'] = null;
    }
    if (this.messagesSent != null) {
      json[r'messages_sent'] = this.messagesSent;
    } else {
      json[r'messages_sent'] = null;
    }
    if (this.messagesReceived != null) {
      json[r'messages_received'] = this.messagesReceived;
    } else {
      json[r'messages_received'] = null;
    }
    if (this.totalRooms != null) {
      json[r'total_rooms'] = this.totalRooms;
    } else {
      json[r'total_rooms'] = null;
    }
    return json;
  }

  /// Returns a new [DevCtrHelloApiWsV1WsStatsRes] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DevCtrHelloApiWsV1WsStatsRes? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        requiredKeys.forEach((key) {
          assert(json.containsKey(key), 'Required key "DevCtrHelloApiWsV1WsStatsRes[$key]" is missing from JSON.');
          assert(json[key] != null, 'Required key "DevCtrHelloApiWsV1WsStatsRes[$key]" has a null value in JSON.');
        });
        return true;
      }());

      return DevCtrHelloApiWsV1WsStatsRes(
        totalConnections: mapValueOfType<int>(json, r'total_connections'),
        activeConnections: mapValueOfType<int>(json, r'active_connections'),
        messagesSent: mapValueOfType<int>(json, r'messages_sent'),
        messagesReceived: mapValueOfType<int>(json, r'messages_received'),
        totalRooms: mapValueOfType<int>(json, r'total_rooms'),
      );
    }
    return null;
  }

  static List<DevCtrHelloApiWsV1WsStatsRes> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DevCtrHelloApiWsV1WsStatsRes>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DevCtrHelloApiWsV1WsStatsRes.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DevCtrHelloApiWsV1WsStatsRes> mapFromJson(dynamic json) {
    final map = <String, DevCtrHelloApiWsV1WsStatsRes>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DevCtrHelloApiWsV1WsStatsRes.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DevCtrHelloApiWsV1WsStatsRes-objects as value to a dart map
  static Map<String, List<DevCtrHelloApiWsV1WsStatsRes>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DevCtrHelloApiWsV1WsStatsRes>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DevCtrHelloApiWsV1WsStatsRes.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

