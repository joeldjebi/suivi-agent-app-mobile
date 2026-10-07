// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PendingPositionsTable extends PendingPositions
    with TableInfo<$PendingPositionsTable, PendingPosition> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingPositionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _dayIdMeta = const VerificationMeta('dayId');
  @override
  late final GeneratedColumn<String> dayId = GeneratedColumn<String>(
    'day_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accuracyMeta = const VerificationMeta(
    'accuracy',
  );
  @override
  late final GeneratedColumn<double> accuracy = GeneratedColumn<double>(
    'accuracy',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
    'speed',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isMockedMeta = const VerificationMeta(
    'isMocked',
  );
  @override
  late final GeneratedColumn<bool> isMocked = GeneratedColumn<bool>(
    'is_mocked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_mocked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<DateTime> recordedAt = GeneratedColumn<DateTime>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    dayId,
    lat,
    lng,
    accuracy,
    speed,
    isMocked,
    recordedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_positions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingPosition> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('day_id')) {
      context.handle(
        _dayIdMeta,
        dayId.isAcceptableOrUnknown(data['day_id']!, _dayIdMeta),
      );
    } else if (isInserting) {
      context.missing(_dayIdMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    } else if (isInserting) {
      context.missing(_lngMeta);
    }
    if (data.containsKey('accuracy')) {
      context.handle(
        _accuracyMeta,
        accuracy.isAcceptableOrUnknown(data['accuracy']!, _accuracyMeta),
      );
    } else if (isInserting) {
      context.missing(_accuracyMeta);
    }
    if (data.containsKey('speed')) {
      context.handle(
        _speedMeta,
        speed.isAcceptableOrUnknown(data['speed']!, _speedMeta),
      );
    }
    if (data.containsKey('is_mocked')) {
      context.handle(
        _isMockedMeta,
        isMocked.isAcceptableOrUnknown(data['is_mocked']!, _isMockedMeta),
      );
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingPosition map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingPosition(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      dayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day_id'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      )!,
      accuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy'],
      )!,
      speed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed'],
      ),
      isMocked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_mocked'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recorded_at'],
      )!,
    );
  }

  @override
  $PendingPositionsTable createAlias(String alias) {
    return $PendingPositionsTable(attachedDatabase, alias);
  }
}

class PendingPosition extends DataClass implements Insertable<PendingPosition> {
  final int id;
  final String dayId;
  final double lat;
  final double lng;
  final double accuracy;
  final double? speed;
  final bool isMocked;
  final DateTime recordedAt;
  const PendingPosition({
    required this.id,
    required this.dayId,
    required this.lat,
    required this.lng,
    required this.accuracy,
    this.speed,
    required this.isMocked,
    required this.recordedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['day_id'] = Variable<String>(dayId);
    map['lat'] = Variable<double>(lat);
    map['lng'] = Variable<double>(lng);
    map['accuracy'] = Variable<double>(accuracy);
    if (!nullToAbsent || speed != null) {
      map['speed'] = Variable<double>(speed);
    }
    map['is_mocked'] = Variable<bool>(isMocked);
    map['recorded_at'] = Variable<DateTime>(recordedAt);
    return map;
  }

  PendingPositionsCompanion toCompanion(bool nullToAbsent) {
    return PendingPositionsCompanion(
      id: Value(id),
      dayId: Value(dayId),
      lat: Value(lat),
      lng: Value(lng),
      accuracy: Value(accuracy),
      speed: speed == null && nullToAbsent
          ? const Value.absent()
          : Value(speed),
      isMocked: Value(isMocked),
      recordedAt: Value(recordedAt),
    );
  }

  factory PendingPosition.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingPosition(
      id: serializer.fromJson<int>(json['id']),
      dayId: serializer.fromJson<String>(json['dayId']),
      lat: serializer.fromJson<double>(json['lat']),
      lng: serializer.fromJson<double>(json['lng']),
      accuracy: serializer.fromJson<double>(json['accuracy']),
      speed: serializer.fromJson<double?>(json['speed']),
      isMocked: serializer.fromJson<bool>(json['isMocked']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'dayId': serializer.toJson<String>(dayId),
      'lat': serializer.toJson<double>(lat),
      'lng': serializer.toJson<double>(lng),
      'accuracy': serializer.toJson<double>(accuracy),
      'speed': serializer.toJson<double?>(speed),
      'isMocked': serializer.toJson<bool>(isMocked),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
    };
  }

  PendingPosition copyWith({
    int? id,
    String? dayId,
    double? lat,
    double? lng,
    double? accuracy,
    Value<double?> speed = const Value.absent(),
    bool? isMocked,
    DateTime? recordedAt,
  }) => PendingPosition(
    id: id ?? this.id,
    dayId: dayId ?? this.dayId,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    accuracy: accuracy ?? this.accuracy,
    speed: speed.present ? speed.value : this.speed,
    isMocked: isMocked ?? this.isMocked,
    recordedAt: recordedAt ?? this.recordedAt,
  );
  PendingPosition copyWithCompanion(PendingPositionsCompanion data) {
    return PendingPosition(
      id: data.id.present ? data.id.value : this.id,
      dayId: data.dayId.present ? data.dayId.value : this.dayId,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      accuracy: data.accuracy.present ? data.accuracy.value : this.accuracy,
      speed: data.speed.present ? data.speed.value : this.speed,
      isMocked: data.isMocked.present ? data.isMocked.value : this.isMocked,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingPosition(')
          ..write('id: $id, ')
          ..write('dayId: $dayId, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('accuracy: $accuracy, ')
          ..write('speed: $speed, ')
          ..write('isMocked: $isMocked, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, dayId, lat, lng, accuracy, speed, isMocked, recordedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingPosition &&
          other.id == this.id &&
          other.dayId == this.dayId &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.accuracy == this.accuracy &&
          other.speed == this.speed &&
          other.isMocked == this.isMocked &&
          other.recordedAt == this.recordedAt);
}

class PendingPositionsCompanion extends UpdateCompanion<PendingPosition> {
  final Value<int> id;
  final Value<String> dayId;
  final Value<double> lat;
  final Value<double> lng;
  final Value<double> accuracy;
  final Value<double?> speed;
  final Value<bool> isMocked;
  final Value<DateTime> recordedAt;
  const PendingPositionsCompanion({
    this.id = const Value.absent(),
    this.dayId = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.speed = const Value.absent(),
    this.isMocked = const Value.absent(),
    this.recordedAt = const Value.absent(),
  });
  PendingPositionsCompanion.insert({
    this.id = const Value.absent(),
    required String dayId,
    required double lat,
    required double lng,
    required double accuracy,
    this.speed = const Value.absent(),
    this.isMocked = const Value.absent(),
    required DateTime recordedAt,
  }) : dayId = Value(dayId),
       lat = Value(lat),
       lng = Value(lng),
       accuracy = Value(accuracy),
       recordedAt = Value(recordedAt);
  static Insertable<PendingPosition> custom({
    Expression<int>? id,
    Expression<String>? dayId,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<double>? accuracy,
    Expression<double>? speed,
    Expression<bool>? isMocked,
    Expression<DateTime>? recordedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dayId != null) 'day_id': dayId,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (accuracy != null) 'accuracy': accuracy,
      if (speed != null) 'speed': speed,
      if (isMocked != null) 'is_mocked': isMocked,
      if (recordedAt != null) 'recorded_at': recordedAt,
    });
  }

  PendingPositionsCompanion copyWith({
    Value<int>? id,
    Value<String>? dayId,
    Value<double>? lat,
    Value<double>? lng,
    Value<double>? accuracy,
    Value<double?>? speed,
    Value<bool>? isMocked,
    Value<DateTime>? recordedAt,
  }) {
    return PendingPositionsCompanion(
      id: id ?? this.id,
      dayId: dayId ?? this.dayId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      isMocked: isMocked ?? this.isMocked,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (dayId.present) {
      map['day_id'] = Variable<String>(dayId.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (accuracy.present) {
      map['accuracy'] = Variable<double>(accuracy.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (isMocked.present) {
      map['is_mocked'] = Variable<bool>(isMocked.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<DateTime>(recordedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingPositionsCompanion(')
          ..write('id: $id, ')
          ..write('dayId: $dayId, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('accuracy: $accuracy, ')
          ..write('speed: $speed, ')
          ..write('isMocked: $isMocked, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }
}

class $PendingSubmissionsTable extends PendingSubmissions
    with TableInfo<$PendingSubmissionsTable, PendingSubmission> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingSubmissionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _missionIdMeta = const VerificationMeta(
    'missionId',
  );
  @override
  late final GeneratedColumn<String> missionId = GeneratedColumn<String>(
    'mission_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _missionTitleMeta = const VerificationMeta(
    'missionTitle',
  );
  @override
  late final GeneratedColumn<String> missionTitle = GeneratedColumn<String>(
    'mission_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _submittedAtMeta = const VerificationMeta(
    'submittedAt',
  );
  @override
  late final GeneratedColumn<DateTime> submittedAt = GeneratedColumn<DateTime>(
    'submitted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    clientId,
    missionId,
    missionTitle,
    dataJson,
    lat,
    lng,
    submittedAt,
    error,
    errorCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_submissions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingSubmission> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('mission_id')) {
      context.handle(
        _missionIdMeta,
        missionId.isAcceptableOrUnknown(data['mission_id']!, _missionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_missionIdMeta);
    }
    if (data.containsKey('mission_title')) {
      context.handle(
        _missionTitleMeta,
        missionTitle.isAcceptableOrUnknown(
          data['mission_title']!,
          _missionTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_missionTitleMeta);
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    }
    if (data.containsKey('submitted_at')) {
      context.handle(
        _submittedAtMeta,
        submittedAt.isAcceptableOrUnknown(
          data['submitted_at']!,
          _submittedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_submittedAtMeta);
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientId};
  @override
  PendingSubmission map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingSubmission(
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      missionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mission_id'],
      )!,
      missionTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mission_title'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      ),
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      ),
      submittedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}submitted_at'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
    );
  }

  @override
  $PendingSubmissionsTable createAlias(String alias) {
    return $PendingSubmissionsTable(attachedDatabase, alias);
  }
}

class PendingSubmission extends DataClass
    implements Insertable<PendingSubmission> {
  /// Identifiant généré sur le téléphone : un renvoi ne crée pas de doublon côté serveur.
  final String clientId;
  final String missionId;
  final String missionTitle;
  final String dataJson;
  final double? lat;
  final double? lng;
  final DateTime submittedAt;

  /// Refus définitif du serveur (formulaire invalide, mission close) : n'est plus renvoyé.
  final String? error;

  /// Code du refus (DAY_REQUIRED, WRONG_ZONE, INVALID_FORM, MISSION_CLOSED…) : décide si
  /// l'agent peut corriger et renvoyer.
  final String? errorCode;
  const PendingSubmission({
    required this.clientId,
    required this.missionId,
    required this.missionTitle,
    required this.dataJson,
    this.lat,
    this.lng,
    required this.submittedAt,
    this.error,
    this.errorCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_id'] = Variable<String>(clientId);
    map['mission_id'] = Variable<String>(missionId);
    map['mission_title'] = Variable<String>(missionTitle);
    map['data_json'] = Variable<String>(dataJson);
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lng != null) {
      map['lng'] = Variable<double>(lng);
    }
    map['submitted_at'] = Variable<DateTime>(submittedAt);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    return map;
  }

  PendingSubmissionsCompanion toCompanion(bool nullToAbsent) {
    return PendingSubmissionsCompanion(
      clientId: Value(clientId),
      missionId: Value(missionId),
      missionTitle: Value(missionTitle),
      dataJson: Value(dataJson),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lng: lng == null && nullToAbsent ? const Value.absent() : Value(lng),
      submittedAt: Value(submittedAt),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
    );
  }

  factory PendingSubmission.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingSubmission(
      clientId: serializer.fromJson<String>(json['clientId']),
      missionId: serializer.fromJson<String>(json['missionId']),
      missionTitle: serializer.fromJson<String>(json['missionTitle']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      lat: serializer.fromJson<double?>(json['lat']),
      lng: serializer.fromJson<double?>(json['lng']),
      submittedAt: serializer.fromJson<DateTime>(json['submittedAt']),
      error: serializer.fromJson<String?>(json['error']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientId': serializer.toJson<String>(clientId),
      'missionId': serializer.toJson<String>(missionId),
      'missionTitle': serializer.toJson<String>(missionTitle),
      'dataJson': serializer.toJson<String>(dataJson),
      'lat': serializer.toJson<double?>(lat),
      'lng': serializer.toJson<double?>(lng),
      'submittedAt': serializer.toJson<DateTime>(submittedAt),
      'error': serializer.toJson<String?>(error),
      'errorCode': serializer.toJson<String?>(errorCode),
    };
  }

  PendingSubmission copyWith({
    String? clientId,
    String? missionId,
    String? missionTitle,
    String? dataJson,
    Value<double?> lat = const Value.absent(),
    Value<double?> lng = const Value.absent(),
    DateTime? submittedAt,
    Value<String?> error = const Value.absent(),
    Value<String?> errorCode = const Value.absent(),
  }) => PendingSubmission(
    clientId: clientId ?? this.clientId,
    missionId: missionId ?? this.missionId,
    missionTitle: missionTitle ?? this.missionTitle,
    dataJson: dataJson ?? this.dataJson,
    lat: lat.present ? lat.value : this.lat,
    lng: lng.present ? lng.value : this.lng,
    submittedAt: submittedAt ?? this.submittedAt,
    error: error.present ? error.value : this.error,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
  );
  PendingSubmission copyWithCompanion(PendingSubmissionsCompanion data) {
    return PendingSubmission(
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      missionId: data.missionId.present ? data.missionId.value : this.missionId,
      missionTitle: data.missionTitle.present
          ? data.missionTitle.value
          : this.missionTitle,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      submittedAt: data.submittedAt.present
          ? data.submittedAt.value
          : this.submittedAt,
      error: data.error.present ? data.error.value : this.error,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingSubmission(')
          ..write('clientId: $clientId, ')
          ..write('missionId: $missionId, ')
          ..write('missionTitle: $missionTitle, ')
          ..write('dataJson: $dataJson, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('submittedAt: $submittedAt, ')
          ..write('error: $error, ')
          ..write('errorCode: $errorCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    clientId,
    missionId,
    missionTitle,
    dataJson,
    lat,
    lng,
    submittedAt,
    error,
    errorCode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingSubmission &&
          other.clientId == this.clientId &&
          other.missionId == this.missionId &&
          other.missionTitle == this.missionTitle &&
          other.dataJson == this.dataJson &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.submittedAt == this.submittedAt &&
          other.error == this.error &&
          other.errorCode == this.errorCode);
}

class PendingSubmissionsCompanion extends UpdateCompanion<PendingSubmission> {
  final Value<String> clientId;
  final Value<String> missionId;
  final Value<String> missionTitle;
  final Value<String> dataJson;
  final Value<double?> lat;
  final Value<double?> lng;
  final Value<DateTime> submittedAt;
  final Value<String?> error;
  final Value<String?> errorCode;
  final Value<int> rowid;
  const PendingSubmissionsCompanion({
    this.clientId = const Value.absent(),
    this.missionId = const Value.absent(),
    this.missionTitle = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.submittedAt = const Value.absent(),
    this.error = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingSubmissionsCompanion.insert({
    required String clientId,
    required String missionId,
    required String missionTitle,
    required String dataJson,
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    required DateTime submittedAt,
    this.error = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : clientId = Value(clientId),
       missionId = Value(missionId),
       missionTitle = Value(missionTitle),
       dataJson = Value(dataJson),
       submittedAt = Value(submittedAt);
  static Insertable<PendingSubmission> custom({
    Expression<String>? clientId,
    Expression<String>? missionId,
    Expression<String>? missionTitle,
    Expression<String>? dataJson,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<DateTime>? submittedAt,
    Expression<String>? error,
    Expression<String>? errorCode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientId != null) 'client_id': clientId,
      if (missionId != null) 'mission_id': missionId,
      if (missionTitle != null) 'mission_title': missionTitle,
      if (dataJson != null) 'data_json': dataJson,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (submittedAt != null) 'submitted_at': submittedAt,
      if (error != null) 'error': error,
      if (errorCode != null) 'error_code': errorCode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingSubmissionsCompanion copyWith({
    Value<String>? clientId,
    Value<String>? missionId,
    Value<String>? missionTitle,
    Value<String>? dataJson,
    Value<double?>? lat,
    Value<double?>? lng,
    Value<DateTime>? submittedAt,
    Value<String?>? error,
    Value<String?>? errorCode,
    Value<int>? rowid,
  }) {
    return PendingSubmissionsCompanion(
      clientId: clientId ?? this.clientId,
      missionId: missionId ?? this.missionId,
      missionTitle: missionTitle ?? this.missionTitle,
      dataJson: dataJson ?? this.dataJson,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      submittedAt: submittedAt ?? this.submittedAt,
      error: error ?? this.error,
      errorCode: errorCode ?? this.errorCode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (missionId.present) {
      map['mission_id'] = Variable<String>(missionId.value);
    }
    if (missionTitle.present) {
      map['mission_title'] = Variable<String>(missionTitle.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (submittedAt.present) {
      map['submitted_at'] = Variable<DateTime>(submittedAt.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingSubmissionsCompanion(')
          ..write('clientId: $clientId, ')
          ..write('missionId: $missionId, ')
          ..write('missionTitle: $missionTitle, ')
          ..write('dataJson: $dataJson, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('submittedAt: $submittedAt, ')
          ..write('error: $error, ')
          ..write('errorCode: $errorCode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PendingPositionsTable pendingPositions = $PendingPositionsTable(
    this,
  );
  late final $PendingSubmissionsTable pendingSubmissions =
      $PendingSubmissionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pendingPositions,
    pendingSubmissions,
  ];
}

typedef $$PendingPositionsTableCreateCompanionBuilder =
    PendingPositionsCompanion Function({
      Value<int> id,
      required String dayId,
      required double lat,
      required double lng,
      required double accuracy,
      Value<double?> speed,
      Value<bool> isMocked,
      required DateTime recordedAt,
    });
typedef $$PendingPositionsTableUpdateCompanionBuilder =
    PendingPositionsCompanion Function({
      Value<int> id,
      Value<String> dayId,
      Value<double> lat,
      Value<double> lng,
      Value<double> accuracy,
      Value<double?> speed,
      Value<bool> isMocked,
      Value<DateTime> recordedAt,
    });

class $$PendingPositionsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingPositionsTable> {
  $$PendingPositionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dayId => $composableBuilder(
    column: $table.dayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMocked => $composableBuilder(
    column: $table.isMocked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingPositionsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingPositionsTable> {
  $$PendingPositionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dayId => $composableBuilder(
    column: $table.dayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMocked => $composableBuilder(
    column: $table.isMocked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingPositionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingPositionsTable> {
  $$PendingPositionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dayId =>
      $composableBuilder(column: $table.dayId, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<double> get accuracy =>
      $composableBuilder(column: $table.accuracy, builder: (column) => column);

  GeneratedColumn<double> get speed =>
      $composableBuilder(column: $table.speed, builder: (column) => column);

  GeneratedColumn<bool> get isMocked =>
      $composableBuilder(column: $table.isMocked, builder: (column) => column);

  GeneratedColumn<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );
}

class $$PendingPositionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingPositionsTable,
          PendingPosition,
          $$PendingPositionsTableFilterComposer,
          $$PendingPositionsTableOrderingComposer,
          $$PendingPositionsTableAnnotationComposer,
          $$PendingPositionsTableCreateCompanionBuilder,
          $$PendingPositionsTableUpdateCompanionBuilder,
          (
            PendingPosition,
            BaseReferences<
              _$AppDatabase,
              $PendingPositionsTable,
              PendingPosition
            >,
          ),
          PendingPosition,
          PrefetchHooks Function()
        > {
  $$PendingPositionsTableTableManager(
    _$AppDatabase db,
    $PendingPositionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingPositionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingPositionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingPositionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> dayId = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lng = const Value.absent(),
                Value<double> accuracy = const Value.absent(),
                Value<double?> speed = const Value.absent(),
                Value<bool> isMocked = const Value.absent(),
                Value<DateTime> recordedAt = const Value.absent(),
              }) => PendingPositionsCompanion(
                id: id,
                dayId: dayId,
                lat: lat,
                lng: lng,
                accuracy: accuracy,
                speed: speed,
                isMocked: isMocked,
                recordedAt: recordedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String dayId,
                required double lat,
                required double lng,
                required double accuracy,
                Value<double?> speed = const Value.absent(),
                Value<bool> isMocked = const Value.absent(),
                required DateTime recordedAt,
              }) => PendingPositionsCompanion.insert(
                id: id,
                dayId: dayId,
                lat: lat,
                lng: lng,
                accuracy: accuracy,
                speed: speed,
                isMocked: isMocked,
                recordedAt: recordedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingPositionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingPositionsTable,
      PendingPosition,
      $$PendingPositionsTableFilterComposer,
      $$PendingPositionsTableOrderingComposer,
      $$PendingPositionsTableAnnotationComposer,
      $$PendingPositionsTableCreateCompanionBuilder,
      $$PendingPositionsTableUpdateCompanionBuilder,
      (
        PendingPosition,
        BaseReferences<_$AppDatabase, $PendingPositionsTable, PendingPosition>,
      ),
      PendingPosition,
      PrefetchHooks Function()
    >;
typedef $$PendingSubmissionsTableCreateCompanionBuilder =
    PendingSubmissionsCompanion Function({
      required String clientId,
      required String missionId,
      required String missionTitle,
      required String dataJson,
      Value<double?> lat,
      Value<double?> lng,
      required DateTime submittedAt,
      Value<String?> error,
      Value<String?> errorCode,
      Value<int> rowid,
    });
typedef $$PendingSubmissionsTableUpdateCompanionBuilder =
    PendingSubmissionsCompanion Function({
      Value<String> clientId,
      Value<String> missionId,
      Value<String> missionTitle,
      Value<String> dataJson,
      Value<double?> lat,
      Value<double?> lng,
      Value<DateTime> submittedAt,
      Value<String?> error,
      Value<String?> errorCode,
      Value<int> rowid,
    });

class $$PendingSubmissionsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingSubmissionsTable> {
  $$PendingSubmissionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get missionId => $composableBuilder(
    column: $table.missionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get missionTitle => $composableBuilder(
    column: $table.missionTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get submittedAt => $composableBuilder(
    column: $table.submittedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingSubmissionsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingSubmissionsTable> {
  $$PendingSubmissionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get missionId => $composableBuilder(
    column: $table.missionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get missionTitle => $composableBuilder(
    column: $table.missionTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get submittedAt => $composableBuilder(
    column: $table.submittedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingSubmissionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingSubmissionsTable> {
  $$PendingSubmissionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get missionId =>
      $composableBuilder(column: $table.missionId, builder: (column) => column);

  GeneratedColumn<String> get missionTitle => $composableBuilder(
    column: $table.missionTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<DateTime> get submittedAt => $composableBuilder(
    column: $table.submittedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);
}

class $$PendingSubmissionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingSubmissionsTable,
          PendingSubmission,
          $$PendingSubmissionsTableFilterComposer,
          $$PendingSubmissionsTableOrderingComposer,
          $$PendingSubmissionsTableAnnotationComposer,
          $$PendingSubmissionsTableCreateCompanionBuilder,
          $$PendingSubmissionsTableUpdateCompanionBuilder,
          (
            PendingSubmission,
            BaseReferences<
              _$AppDatabase,
              $PendingSubmissionsTable,
              PendingSubmission
            >,
          ),
          PendingSubmission,
          PrefetchHooks Function()
        > {
  $$PendingSubmissionsTableTableManager(
    _$AppDatabase db,
    $PendingSubmissionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingSubmissionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingSubmissionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingSubmissionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> clientId = const Value.absent(),
                Value<String> missionId = const Value.absent(),
                Value<String> missionTitle = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<DateTime> submittedAt = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingSubmissionsCompanion(
                clientId: clientId,
                missionId: missionId,
                missionTitle: missionTitle,
                dataJson: dataJson,
                lat: lat,
                lng: lng,
                submittedAt: submittedAt,
                error: error,
                errorCode: errorCode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientId,
                required String missionId,
                required String missionTitle,
                required String dataJson,
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                required DateTime submittedAt,
                Value<String?> error = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingSubmissionsCompanion.insert(
                clientId: clientId,
                missionId: missionId,
                missionTitle: missionTitle,
                dataJson: dataJson,
                lat: lat,
                lng: lng,
                submittedAt: submittedAt,
                error: error,
                errorCode: errorCode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingSubmissionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingSubmissionsTable,
      PendingSubmission,
      $$PendingSubmissionsTableFilterComposer,
      $$PendingSubmissionsTableOrderingComposer,
      $$PendingSubmissionsTableAnnotationComposer,
      $$PendingSubmissionsTableCreateCompanionBuilder,
      $$PendingSubmissionsTableUpdateCompanionBuilder,
      (
        PendingSubmission,
        BaseReferences<
          _$AppDatabase,
          $PendingSubmissionsTable,
          PendingSubmission
        >,
      ),
      PendingSubmission,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PendingPositionsTableTableManager get pendingPositions =>
      $$PendingPositionsTableTableManager(_db, _db.pendingPositions);
  $$PendingSubmissionsTableTableManager get pendingSubmissions =>
      $$PendingSubmissionsTableTableManager(_db, _db.pendingSubmissions);
}
