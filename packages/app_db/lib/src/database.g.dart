// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $FeedsTable extends Feeds with TableInfo<$FeedsTable, Feed> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FeedsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, position, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'feeds';
  @override
  VerificationContext validateIntegrity(
    Insertable<Feed> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Feed map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Feed(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $FeedsTable createAlias(String alias) {
    return $FeedsTable(attachedDatabase, alias);
  }
}

class Feed extends DataClass implements Insertable<Feed> {
  final int id;
  final String name;
  final int position;
  final DateTime createdAt;
  const Feed({
    required this.id,
    required this.name,
    required this.position,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FeedsCompanion toCompanion(bool nullToAbsent) {
    return FeedsCompanion(
      id: Value(id),
      name: Value(name),
      position: Value(position),
      createdAt: Value(createdAt),
    );
  }

  factory Feed.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Feed(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Feed copyWith({int? id, String? name, int? position, DateTime? createdAt}) =>
      Feed(
        id: id ?? this.id,
        name: name ?? this.name,
        position: position ?? this.position,
        createdAt: createdAt ?? this.createdAt,
      );
  Feed copyWithCompanion(FeedsCompanion data) {
    return Feed(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Feed(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, position, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Feed &&
          other.id == this.id &&
          other.name == this.name &&
          other.position == this.position &&
          other.createdAt == this.createdAt);
}

class FeedsCompanion extends UpdateCompanion<Feed> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> position;
  final Value<DateTime> createdAt;
  const FeedsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  FeedsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int position,
    required DateTime createdAt,
  }) : name = Value(name),
       position = Value(position),
       createdAt = Value(createdAt);
  static Insertable<Feed> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? position,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  FeedsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? position,
    Value<DateTime>? createdAt,
  }) {
    return FeedsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FeedsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $FeedSourcesTable extends FeedSources
    with TableInfo<$FeedSourcesTable, FeedSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FeedSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _feedIdMeta = const VerificationMeta('feedId');
  @override
  late final GeneratedColumn<int> feedId = GeneratedColumn<int>(
    'feed_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES feeds (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<int> chatId = GeneratedColumn<int>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [feedId, chatId, position, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'feed_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<FeedSource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('feed_id')) {
      context.handle(
        _feedIdMeta,
        feedId.isAcceptableOrUnknown(data['feed_id']!, _feedIdMeta),
      );
    } else if (isInserting) {
      context.missing(_feedIdMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {feedId, chatId};
  @override
  FeedSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FeedSource(
      feedId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}feed_id'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chat_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FeedSourcesTable createAlias(String alias) {
    return $FeedSourcesTable(attachedDatabase, alias);
  }
}

class FeedSource extends DataClass implements Insertable<FeedSource> {
  final int feedId;
  final int chatId;
  final int position;
  final DateTime addedAt;
  const FeedSource({
    required this.feedId,
    required this.chatId,
    required this.position,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['feed_id'] = Variable<int>(feedId);
    map['chat_id'] = Variable<int>(chatId);
    map['position'] = Variable<int>(position);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FeedSourcesCompanion toCompanion(bool nullToAbsent) {
    return FeedSourcesCompanion(
      feedId: Value(feedId),
      chatId: Value(chatId),
      position: Value(position),
      addedAt: Value(addedAt),
    );
  }

  factory FeedSource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FeedSource(
      feedId: serializer.fromJson<int>(json['feedId']),
      chatId: serializer.fromJson<int>(json['chatId']),
      position: serializer.fromJson<int>(json['position']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'feedId': serializer.toJson<int>(feedId),
      'chatId': serializer.toJson<int>(chatId),
      'position': serializer.toJson<int>(position),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  FeedSource copyWith({
    int? feedId,
    int? chatId,
    int? position,
    DateTime? addedAt,
  }) => FeedSource(
    feedId: feedId ?? this.feedId,
    chatId: chatId ?? this.chatId,
    position: position ?? this.position,
    addedAt: addedAt ?? this.addedAt,
  );
  FeedSource copyWithCompanion(FeedSourcesCompanion data) {
    return FeedSource(
      feedId: data.feedId.present ? data.feedId.value : this.feedId,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      position: data.position.present ? data.position.value : this.position,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FeedSource(')
          ..write('feedId: $feedId, ')
          ..write('chatId: $chatId, ')
          ..write('position: $position, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(feedId, chatId, position, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FeedSource &&
          other.feedId == this.feedId &&
          other.chatId == this.chatId &&
          other.position == this.position &&
          other.addedAt == this.addedAt);
}

class FeedSourcesCompanion extends UpdateCompanion<FeedSource> {
  final Value<int> feedId;
  final Value<int> chatId;
  final Value<int> position;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const FeedSourcesCompanion({
    this.feedId = const Value.absent(),
    this.chatId = const Value.absent(),
    this.position = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FeedSourcesCompanion.insert({
    required int feedId,
    required int chatId,
    required int position,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : feedId = Value(feedId),
       chatId = Value(chatId),
       position = Value(position),
       addedAt = Value(addedAt);
  static Insertable<FeedSource> custom({
    Expression<int>? feedId,
    Expression<int>? chatId,
    Expression<int>? position,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (feedId != null) 'feed_id': feedId,
      if (chatId != null) 'chat_id': chatId,
      if (position != null) 'position': position,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FeedSourcesCompanion copyWith({
    Value<int>? feedId,
    Value<int>? chatId,
    Value<int>? position,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return FeedSourcesCompanion(
      feedId: feedId ?? this.feedId,
      chatId: chatId ?? this.chatId,
      position: position ?? this.position,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (feedId.present) {
      map['feed_id'] = Variable<int>(feedId.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<int>(chatId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FeedSourcesCompanion(')
          ..write('feedId: $feedId, ')
          ..write('chatId: $chatId, ')
          ..write('position: $position, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FeedReadMarksTable extends FeedReadMarks
    with TableInfo<$FeedReadMarksTable, FeedReadMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FeedReadMarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _feedIdMeta = const VerificationMeta('feedId');
  @override
  late final GeneratedColumn<int> feedId = GeneratedColumn<int>(
    'feed_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES feeds (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<int> chatId = GeneratedColumn<int>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastReadMessageIdMeta = const VerificationMeta(
    'lastReadMessageId',
  );
  @override
  late final GeneratedColumn<int> lastReadMessageId = GeneratedColumn<int>(
    'last_read_message_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [feedId, chatId, lastReadMessageId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'feed_read_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<FeedReadMark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('feed_id')) {
      context.handle(
        _feedIdMeta,
        feedId.isAcceptableOrUnknown(data['feed_id']!, _feedIdMeta),
      );
    } else if (isInserting) {
      context.missing(_feedIdMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('last_read_message_id')) {
      context.handle(
        _lastReadMessageIdMeta,
        lastReadMessageId.isAcceptableOrUnknown(
          data['last_read_message_id']!,
          _lastReadMessageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastReadMessageIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {feedId, chatId};
  @override
  FeedReadMark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FeedReadMark(
      feedId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}feed_id'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chat_id'],
      )!,
      lastReadMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_message_id'],
      )!,
    );
  }

  @override
  $FeedReadMarksTable createAlias(String alias) {
    return $FeedReadMarksTable(attachedDatabase, alias);
  }
}

class FeedReadMark extends DataClass implements Insertable<FeedReadMark> {
  final int feedId;
  final int chatId;
  final int lastReadMessageId;
  const FeedReadMark({
    required this.feedId,
    required this.chatId,
    required this.lastReadMessageId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['feed_id'] = Variable<int>(feedId);
    map['chat_id'] = Variable<int>(chatId);
    map['last_read_message_id'] = Variable<int>(lastReadMessageId);
    return map;
  }

  FeedReadMarksCompanion toCompanion(bool nullToAbsent) {
    return FeedReadMarksCompanion(
      feedId: Value(feedId),
      chatId: Value(chatId),
      lastReadMessageId: Value(lastReadMessageId),
    );
  }

  factory FeedReadMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FeedReadMark(
      feedId: serializer.fromJson<int>(json['feedId']),
      chatId: serializer.fromJson<int>(json['chatId']),
      lastReadMessageId: serializer.fromJson<int>(json['lastReadMessageId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'feedId': serializer.toJson<int>(feedId),
      'chatId': serializer.toJson<int>(chatId),
      'lastReadMessageId': serializer.toJson<int>(lastReadMessageId),
    };
  }

  FeedReadMark copyWith({int? feedId, int? chatId, int? lastReadMessageId}) =>
      FeedReadMark(
        feedId: feedId ?? this.feedId,
        chatId: chatId ?? this.chatId,
        lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
      );
  FeedReadMark copyWithCompanion(FeedReadMarksCompanion data) {
    return FeedReadMark(
      feedId: data.feedId.present ? data.feedId.value : this.feedId,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      lastReadMessageId: data.lastReadMessageId.present
          ? data.lastReadMessageId.value
          : this.lastReadMessageId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FeedReadMark(')
          ..write('feedId: $feedId, ')
          ..write('chatId: $chatId, ')
          ..write('lastReadMessageId: $lastReadMessageId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(feedId, chatId, lastReadMessageId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FeedReadMark &&
          other.feedId == this.feedId &&
          other.chatId == this.chatId &&
          other.lastReadMessageId == this.lastReadMessageId);
}

class FeedReadMarksCompanion extends UpdateCompanion<FeedReadMark> {
  final Value<int> feedId;
  final Value<int> chatId;
  final Value<int> lastReadMessageId;
  final Value<int> rowid;
  const FeedReadMarksCompanion({
    this.feedId = const Value.absent(),
    this.chatId = const Value.absent(),
    this.lastReadMessageId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FeedReadMarksCompanion.insert({
    required int feedId,
    required int chatId,
    required int lastReadMessageId,
    this.rowid = const Value.absent(),
  }) : feedId = Value(feedId),
       chatId = Value(chatId),
       lastReadMessageId = Value(lastReadMessageId);
  static Insertable<FeedReadMark> custom({
    Expression<int>? feedId,
    Expression<int>? chatId,
    Expression<int>? lastReadMessageId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (feedId != null) 'feed_id': feedId,
      if (chatId != null) 'chat_id': chatId,
      if (lastReadMessageId != null) 'last_read_message_id': lastReadMessageId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FeedReadMarksCompanion copyWith({
    Value<int>? feedId,
    Value<int>? chatId,
    Value<int>? lastReadMessageId,
    Value<int>? rowid,
  }) {
    return FeedReadMarksCompanion(
      feedId: feedId ?? this.feedId,
      chatId: chatId ?? this.chatId,
      lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (feedId.present) {
      map['feed_id'] = Variable<int>(feedId.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<int>(chatId.value);
    }
    if (lastReadMessageId.present) {
      map['last_read_message_id'] = Variable<int>(lastReadMessageId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FeedReadMarksCompanion(')
          ..write('feedId: $feedId, ')
          ..write('chatId: $chatId, ')
          ..write('lastReadMessageId: $lastReadMessageId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchedChannelsTable extends WatchedChannels
    with TableInfo<$WatchedChannelsTable, WatchedChannel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchedChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<int> chatId = GeneratedColumn<int>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [chatId, title, username];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watched_channels';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchedChannel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {chatId};
  @override
  WatchedChannel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchedChannel(
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chat_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
    );
  }

  @override
  $WatchedChannelsTable createAlias(String alias) {
    return $WatchedChannelsTable(attachedDatabase, alias);
  }
}

class WatchedChannel extends DataClass implements Insertable<WatchedChannel> {
  final int chatId;
  final String title;
  final String? username;
  const WatchedChannel({
    required this.chatId,
    required this.title,
    this.username,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['chat_id'] = Variable<int>(chatId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    return map;
  }

  WatchedChannelsCompanion toCompanion(bool nullToAbsent) {
    return WatchedChannelsCompanion(
      chatId: Value(chatId),
      title: Value(title),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
    );
  }

  factory WatchedChannel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchedChannel(
      chatId: serializer.fromJson<int>(json['chatId']),
      title: serializer.fromJson<String>(json['title']),
      username: serializer.fromJson<String?>(json['username']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'chatId': serializer.toJson<int>(chatId),
      'title': serializer.toJson<String>(title),
      'username': serializer.toJson<String?>(username),
    };
  }

  WatchedChannel copyWith({
    int? chatId,
    String? title,
    Value<String?> username = const Value.absent(),
  }) => WatchedChannel(
    chatId: chatId ?? this.chatId,
    title: title ?? this.title,
    username: username.present ? username.value : this.username,
  );
  WatchedChannel copyWithCompanion(WatchedChannelsCompanion data) {
    return WatchedChannel(
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      title: data.title.present ? data.title.value : this.title,
      username: data.username.present ? data.username.value : this.username,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchedChannel(')
          ..write('chatId: $chatId, ')
          ..write('title: $title, ')
          ..write('username: $username')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(chatId, title, username);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchedChannel &&
          other.chatId == this.chatId &&
          other.title == this.title &&
          other.username == this.username);
}

class WatchedChannelsCompanion extends UpdateCompanion<WatchedChannel> {
  final Value<int> chatId;
  final Value<String> title;
  final Value<String?> username;
  const WatchedChannelsCompanion({
    this.chatId = const Value.absent(),
    this.title = const Value.absent(),
    this.username = const Value.absent(),
  });
  WatchedChannelsCompanion.insert({
    this.chatId = const Value.absent(),
    required String title,
    this.username = const Value.absent(),
  }) : title = Value(title);
  static Insertable<WatchedChannel> custom({
    Expression<int>? chatId,
    Expression<String>? title,
    Expression<String>? username,
  }) {
    return RawValuesInsertable({
      if (chatId != null) 'chat_id': chatId,
      if (title != null) 'title': title,
      if (username != null) 'username': username,
    });
  }

  WatchedChannelsCompanion copyWith({
    Value<int>? chatId,
    Value<String>? title,
    Value<String?>? username,
  }) {
    return WatchedChannelsCompanion(
      chatId: chatId ?? this.chatId,
      title: title ?? this.title,
      username: username ?? this.username,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (chatId.present) {
      map['chat_id'] = Variable<int>(chatId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchedChannelsCompanion(')
          ..write('chatId: $chatId, ')
          ..write('title: $title, ')
          ..write('username: $username')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RulesTable extends Rules with TableInfo<$RulesTable, Rule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RulesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _scopeKindMeta = const VerificationMeta(
    'scopeKind',
  );
  @override
  late final GeneratedColumn<String> scopeKind = GeneratedColumn<String>(
    'scope_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeChatIdMeta = const VerificationMeta(
    'scopeChatId',
  );
  @override
  late final GeneratedColumn<int> scopeChatId = GeneratedColumn<int>(
    'scope_chat_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conditionJsonMeta = const VerificationMeta(
    'conditionJson',
  );
  @override
  late final GeneratedColumn<String> conditionJson = GeneratedColumn<String>(
    'condition_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readAloudMeta = const VerificationMeta(
    'readAloud',
  );
  @override
  late final GeneratedColumn<bool> readAloud = GeneratedColumn<bool>(
    'read_aloud',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("read_aloud" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _scheduleJsonMeta = const VerificationMeta(
    'scheduleJson',
  );
  @override
  late final GeneratedColumn<String> scheduleJson = GeneratedColumn<String>(
    'schedule_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    enabled,
    scopeKind,
    scopeChatId,
    conditionJson,
    priority,
    readAloud,
    scheduleJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<Rule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('scope_kind')) {
      context.handle(
        _scopeKindMeta,
        scopeKind.isAcceptableOrUnknown(data['scope_kind']!, _scopeKindMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeKindMeta);
    }
    if (data.containsKey('scope_chat_id')) {
      context.handle(
        _scopeChatIdMeta,
        scopeChatId.isAcceptableOrUnknown(
          data['scope_chat_id']!,
          _scopeChatIdMeta,
        ),
      );
    }
    if (data.containsKey('condition_json')) {
      context.handle(
        _conditionJsonMeta,
        conditionJson.isAcceptableOrUnknown(
          data['condition_json']!,
          _conditionJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conditionJsonMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('read_aloud')) {
      context.handle(
        _readAloudMeta,
        readAloud.isAcceptableOrUnknown(data['read_aloud']!, _readAloudMeta),
      );
    }
    if (data.containsKey('schedule_json')) {
      context.handle(
        _scheduleJsonMeta,
        scheduleJson.isAcceptableOrUnknown(
          data['schedule_json']!,
          _scheduleJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Rule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Rule(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      scopeKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_kind'],
      )!,
      scopeChatId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scope_chat_id'],
      ),
      conditionJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}condition_json'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      readAloud: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}read_aloud'],
      )!,
      scheduleJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RulesTable createAlias(String alias) {
    return $RulesTable(attachedDatabase, alias);
  }
}

class Rule extends DataClass implements Insertable<Rule> {
  final int id;
  final String name;
  final bool enabled;

  /// 'global' or 'channel'.
  final String scopeKind;
  final int? scopeChatId;
  final String conditionJson;

  /// 'silent', 'normal' or 'urgent'.
  final String priority;
  final bool readAloud;
  final String? scheduleJson;
  final DateTime createdAt;
  const Rule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.scopeKind,
    this.scopeChatId,
    required this.conditionJson,
    required this.priority,
    required this.readAloud,
    this.scheduleJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['enabled'] = Variable<bool>(enabled);
    map['scope_kind'] = Variable<String>(scopeKind);
    if (!nullToAbsent || scopeChatId != null) {
      map['scope_chat_id'] = Variable<int>(scopeChatId);
    }
    map['condition_json'] = Variable<String>(conditionJson);
    map['priority'] = Variable<String>(priority);
    map['read_aloud'] = Variable<bool>(readAloud);
    if (!nullToAbsent || scheduleJson != null) {
      map['schedule_json'] = Variable<String>(scheduleJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RulesCompanion toCompanion(bool nullToAbsent) {
    return RulesCompanion(
      id: Value(id),
      name: Value(name),
      enabled: Value(enabled),
      scopeKind: Value(scopeKind),
      scopeChatId: scopeChatId == null && nullToAbsent
          ? const Value.absent()
          : Value(scopeChatId),
      conditionJson: Value(conditionJson),
      priority: Value(priority),
      readAloud: Value(readAloud),
      scheduleJson: scheduleJson == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduleJson),
      createdAt: Value(createdAt),
    );
  }

  factory Rule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Rule(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      scopeKind: serializer.fromJson<String>(json['scopeKind']),
      scopeChatId: serializer.fromJson<int?>(json['scopeChatId']),
      conditionJson: serializer.fromJson<String>(json['conditionJson']),
      priority: serializer.fromJson<String>(json['priority']),
      readAloud: serializer.fromJson<bool>(json['readAloud']),
      scheduleJson: serializer.fromJson<String?>(json['scheduleJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'enabled': serializer.toJson<bool>(enabled),
      'scopeKind': serializer.toJson<String>(scopeKind),
      'scopeChatId': serializer.toJson<int?>(scopeChatId),
      'conditionJson': serializer.toJson<String>(conditionJson),
      'priority': serializer.toJson<String>(priority),
      'readAloud': serializer.toJson<bool>(readAloud),
      'scheduleJson': serializer.toJson<String?>(scheduleJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Rule copyWith({
    int? id,
    String? name,
    bool? enabled,
    String? scopeKind,
    Value<int?> scopeChatId = const Value.absent(),
    String? conditionJson,
    String? priority,
    bool? readAloud,
    Value<String?> scheduleJson = const Value.absent(),
    DateTime? createdAt,
  }) => Rule(
    id: id ?? this.id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    scopeKind: scopeKind ?? this.scopeKind,
    scopeChatId: scopeChatId.present ? scopeChatId.value : this.scopeChatId,
    conditionJson: conditionJson ?? this.conditionJson,
    priority: priority ?? this.priority,
    readAloud: readAloud ?? this.readAloud,
    scheduleJson: scheduleJson.present ? scheduleJson.value : this.scheduleJson,
    createdAt: createdAt ?? this.createdAt,
  );
  Rule copyWithCompanion(RulesCompanion data) {
    return Rule(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      scopeKind: data.scopeKind.present ? data.scopeKind.value : this.scopeKind,
      scopeChatId: data.scopeChatId.present
          ? data.scopeChatId.value
          : this.scopeChatId,
      conditionJson: data.conditionJson.present
          ? data.conditionJson.value
          : this.conditionJson,
      priority: data.priority.present ? data.priority.value : this.priority,
      readAloud: data.readAloud.present ? data.readAloud.value : this.readAloud,
      scheduleJson: data.scheduleJson.present
          ? data.scheduleJson.value
          : this.scheduleJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Rule(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('scopeKind: $scopeKind, ')
          ..write('scopeChatId: $scopeChatId, ')
          ..write('conditionJson: $conditionJson, ')
          ..write('priority: $priority, ')
          ..write('readAloud: $readAloud, ')
          ..write('scheduleJson: $scheduleJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    enabled,
    scopeKind,
    scopeChatId,
    conditionJson,
    priority,
    readAloud,
    scheduleJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Rule &&
          other.id == this.id &&
          other.name == this.name &&
          other.enabled == this.enabled &&
          other.scopeKind == this.scopeKind &&
          other.scopeChatId == this.scopeChatId &&
          other.conditionJson == this.conditionJson &&
          other.priority == this.priority &&
          other.readAloud == this.readAloud &&
          other.scheduleJson == this.scheduleJson &&
          other.createdAt == this.createdAt);
}

class RulesCompanion extends UpdateCompanion<Rule> {
  final Value<int> id;
  final Value<String> name;
  final Value<bool> enabled;
  final Value<String> scopeKind;
  final Value<int?> scopeChatId;
  final Value<String> conditionJson;
  final Value<String> priority;
  final Value<bool> readAloud;
  final Value<String?> scheduleJson;
  final Value<DateTime> createdAt;
  const RulesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.enabled = const Value.absent(),
    this.scopeKind = const Value.absent(),
    this.scopeChatId = const Value.absent(),
    this.conditionJson = const Value.absent(),
    this.priority = const Value.absent(),
    this.readAloud = const Value.absent(),
    this.scheduleJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  RulesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.enabled = const Value.absent(),
    required String scopeKind,
    this.scopeChatId = const Value.absent(),
    required String conditionJson,
    required String priority,
    this.readAloud = const Value.absent(),
    this.scheduleJson = const Value.absent(),
    required DateTime createdAt,
  }) : name = Value(name),
       scopeKind = Value(scopeKind),
       conditionJson = Value(conditionJson),
       priority = Value(priority),
       createdAt = Value(createdAt);
  static Insertable<Rule> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<bool>? enabled,
    Expression<String>? scopeKind,
    Expression<int>? scopeChatId,
    Expression<String>? conditionJson,
    Expression<String>? priority,
    Expression<bool>? readAloud,
    Expression<String>? scheduleJson,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (enabled != null) 'enabled': enabled,
      if (scopeKind != null) 'scope_kind': scopeKind,
      if (scopeChatId != null) 'scope_chat_id': scopeChatId,
      if (conditionJson != null) 'condition_json': conditionJson,
      if (priority != null) 'priority': priority,
      if (readAloud != null) 'read_aloud': readAloud,
      if (scheduleJson != null) 'schedule_json': scheduleJson,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  RulesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<bool>? enabled,
    Value<String>? scopeKind,
    Value<int?>? scopeChatId,
    Value<String>? conditionJson,
    Value<String>? priority,
    Value<bool>? readAloud,
    Value<String?>? scheduleJson,
    Value<DateTime>? createdAt,
  }) {
    return RulesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      scopeKind: scopeKind ?? this.scopeKind,
      scopeChatId: scopeChatId ?? this.scopeChatId,
      conditionJson: conditionJson ?? this.conditionJson,
      priority: priority ?? this.priority,
      readAloud: readAloud ?? this.readAloud,
      scheduleJson: scheduleJson ?? this.scheduleJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (scopeKind.present) {
      map['scope_kind'] = Variable<String>(scopeKind.value);
    }
    if (scopeChatId.present) {
      map['scope_chat_id'] = Variable<int>(scopeChatId.value);
    }
    if (conditionJson.present) {
      map['condition_json'] = Variable<String>(conditionJson.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (readAloud.present) {
      map['read_aloud'] = Variable<bool>(readAloud.value);
    }
    if (scheduleJson.present) {
      map['schedule_json'] = Variable<String>(scheduleJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RulesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('enabled: $enabled, ')
          ..write('scopeKind: $scopeKind, ')
          ..write('scopeChatId: $scopeChatId, ')
          ..write('conditionJson: $conditionJson, ')
          ..write('priority: $priority, ')
          ..write('readAloud: $readAloud, ')
          ..write('scheduleJson: $scheduleJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FeedsTable feeds = $FeedsTable(this);
  late final $FeedSourcesTable feedSources = $FeedSourcesTable(this);
  late final $FeedReadMarksTable feedReadMarks = $FeedReadMarksTable(this);
  late final $WatchedChannelsTable watchedChannels = $WatchedChannelsTable(
    this,
  );
  late final $SettingsTable settings = $SettingsTable(this);
  late final $RulesTable rules = $RulesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    feeds,
    feedSources,
    feedReadMarks,
    watchedChannels,
    settings,
    rules,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'feeds',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('feed_sources', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'feeds',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('feed_read_marks', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$FeedsTableCreateCompanionBuilder = FeedsCompanion Function({
  Value<int> id,
  required String name,
  required int position,
  required DateTime createdAt,
});
typedef $$FeedsTableUpdateCompanionBuilder = FeedsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> position,
  Value<DateTime> createdAt,
});

final class $$FeedsTableReferences
    extends BaseReferences<_$AppDatabase, $FeedsTable, Feed> {
  $$FeedsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FeedSourcesTable, List<FeedSource>>
  _feedSourcesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.feedSources,
    aliasName: 'feeds__id__feed_sources__feed_id',
  );

  $$FeedSourcesTableProcessedTableManager get feedSourcesRefs {
    final manager = $$FeedSourcesTableTableManager(
      $_db,
      $_db.feedSources,
    ).filter((f) => f.feedId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_feedSourcesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FeedReadMarksTable, List<FeedReadMark>>
  _feedReadMarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.feedReadMarks,
    aliasName: 'feeds__id__feed_read_marks__feed_id',
  );

  $$FeedReadMarksTableProcessedTableManager get feedReadMarksRefs {
    final manager = $$FeedReadMarksTableTableManager(
      $_db,
      $_db.feedReadMarks,
    ).filter((f) => f.feedId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_feedReadMarksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FeedsTableFilterComposer extends Composer<_$AppDatabase, $FeedsTable> {
  $$FeedsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> feedSourcesRefs(
    Expression<bool> Function($$FeedSourcesTableFilterComposer f) f,
  ) {
    final $$FeedSourcesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.feedSources,
      getReferencedColumn: (t) => t.feedId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedSourcesTableFilterComposer(
            $db: $db,
            $table: $db.feedSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> feedReadMarksRefs(
    Expression<bool> Function($$FeedReadMarksTableFilterComposer f) f,
  ) {
    final $$FeedReadMarksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.feedReadMarks,
      getReferencedColumn: (t) => t.feedId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedReadMarksTableFilterComposer(
            $db: $db,
            $table: $db.feedReadMarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FeedsTableOrderingComposer
    extends Composer<_$AppDatabase, $FeedsTable> {
  $$FeedsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FeedsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FeedsTable> {
  $$FeedsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> feedSourcesRefs<T extends Object>(
    Expression<T> Function($$FeedSourcesTableAnnotationComposer a) f,
  ) {
    final $$FeedSourcesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.feedSources,
      getReferencedColumn: (t) => t.feedId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedSourcesTableAnnotationComposer(
            $db: $db,
            $table: $db.feedSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> feedReadMarksRefs<T extends Object>(
    Expression<T> Function($$FeedReadMarksTableAnnotationComposer a) f,
  ) {
    final $$FeedReadMarksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.feedReadMarks,
      getReferencedColumn: (t) => t.feedId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedReadMarksTableAnnotationComposer(
            $db: $db,
            $table: $db.feedReadMarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FeedsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FeedsTable,
          Feed,
          $$FeedsTableFilterComposer,
          $$FeedsTableOrderingComposer,
          $$FeedsTableAnnotationComposer,
          $$FeedsTableCreateCompanionBuilder,
          $$FeedsTableUpdateCompanionBuilder,
          (Feed, $$FeedsTableReferences),
          Feed,
          PrefetchHooks Function({bool feedSourcesRefs, bool feedReadMarksRefs})
        > {
  $$FeedsTableTableManager(_$AppDatabase db, $FeedsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FeedsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FeedsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FeedsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => FeedsCompanion(
                id: id,
                name: name,
                position: position,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required int position,
                required DateTime createdAt,
              }) => FeedsCompanion.insert(
                id: id,
                name: name,
                position: position,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FeedsTable, Feed>(table),
                  $$FeedsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({feedSourcesRefs = false, feedReadMarksRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (feedSourcesRefs) db.feedSources,
                    if (feedReadMarksRefs) db.feedReadMarks,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (feedSourcesRefs)
                        await $_getPrefetchedData<
                          Feed,
                          $FeedsTable,
                          FeedSource
                        >(
                          currentTable: table,
                          referencedTable: $$FeedsTableReferences
                              ._feedSourcesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FeedsTableReferences(
                                db,
                                table,
                                p0,
                              ).feedSourcesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.feedId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (feedReadMarksRefs)
                        await $_getPrefetchedData<
                          Feed,
                          $FeedsTable,
                          FeedReadMark
                        >(
                          currentTable: table,
                          referencedTable: $$FeedsTableReferences
                              ._feedReadMarksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FeedsTableReferences(
                                db,
                                table,
                                p0,
                              ).feedReadMarksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.feedId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$FeedsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FeedsTable,
      Feed,
      $$FeedsTableFilterComposer,
      $$FeedsTableOrderingComposer,
      $$FeedsTableAnnotationComposer,
      $$FeedsTableCreateCompanionBuilder,
      $$FeedsTableUpdateCompanionBuilder,
      (Feed, $$FeedsTableReferences),
      Feed,
      PrefetchHooks Function({bool feedSourcesRefs, bool feedReadMarksRefs})
    >;
typedef $$FeedSourcesTableCreateCompanionBuilder =
    FeedSourcesCompanion Function({
      required int feedId,
      required int chatId,
      required int position,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$FeedSourcesTableUpdateCompanionBuilder =
    FeedSourcesCompanion Function({
      Value<int> feedId,
      Value<int> chatId,
      Value<int> position,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

final class $$FeedSourcesTableReferences
    extends BaseReferences<_$AppDatabase, $FeedSourcesTable, FeedSource> {
  $$FeedSourcesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FeedsTable _feedIdTable(_$AppDatabase db) =>
      db.feeds.createAlias('feed_sources__feed_id__feeds__id');

  $$FeedsTableProcessedTableManager get feedId {
    final $_column = $_itemColumn<int>('feed_id')!;

    final manager = $$FeedsTableTableManager(
      $_db,
      $_db.feeds,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_feedIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FeedSourcesTableFilterComposer
    extends Composer<_$AppDatabase, $FeedSourcesTable> {
  $$FeedSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FeedsTableFilterComposer get feedId {
    final $$FeedsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableFilterComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FeedSourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $FeedSourcesTable> {
  $$FeedSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FeedsTableOrderingComposer get feedId {
    final $$FeedsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableOrderingComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FeedSourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FeedSourcesTable> {
  $$FeedSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  $$FeedsTableAnnotationComposer get feedId {
    final $$FeedsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableAnnotationComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FeedSourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FeedSourcesTable,
          FeedSource,
          $$FeedSourcesTableFilterComposer,
          $$FeedSourcesTableOrderingComposer,
          $$FeedSourcesTableAnnotationComposer,
          $$FeedSourcesTableCreateCompanionBuilder,
          $$FeedSourcesTableUpdateCompanionBuilder,
          (FeedSource, $$FeedSourcesTableReferences),
          FeedSource,
          PrefetchHooks Function({bool feedId})
        > {
  $$FeedSourcesTableTableManager(_$AppDatabase db, $FeedSourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FeedSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FeedSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FeedSourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> feedId = const Value.absent(),
                Value<int> chatId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FeedSourcesCompanion(
                feedId: feedId,
                chatId: chatId,
                position: position,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int feedId,
                required int chatId,
                required int position,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => FeedSourcesCompanion.insert(
                feedId: feedId,
                chatId: chatId,
                position: position,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FeedSourcesTable, FeedSource>(table),
                  $$FeedSourcesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({feedId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (feedId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.feedId,
                        referencedTable: $$FeedSourcesTableReferences
                            ._feedIdTable(db),
                        referencedColumn: $$FeedSourcesTableReferences
                            ._feedIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FeedSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FeedSourcesTable,
      FeedSource,
      $$FeedSourcesTableFilterComposer,
      $$FeedSourcesTableOrderingComposer,
      $$FeedSourcesTableAnnotationComposer,
      $$FeedSourcesTableCreateCompanionBuilder,
      $$FeedSourcesTableUpdateCompanionBuilder,
      (FeedSource, $$FeedSourcesTableReferences),
      FeedSource,
      PrefetchHooks Function({bool feedId})
    >;
typedef $$FeedReadMarksTableCreateCompanionBuilder =
    FeedReadMarksCompanion Function({
      required int feedId,
      required int chatId,
      required int lastReadMessageId,
      Value<int> rowid,
    });
typedef $$FeedReadMarksTableUpdateCompanionBuilder =
    FeedReadMarksCompanion Function({
      Value<int> feedId,
      Value<int> chatId,
      Value<int> lastReadMessageId,
      Value<int> rowid,
    });

final class $$FeedReadMarksTableReferences
    extends BaseReferences<_$AppDatabase, $FeedReadMarksTable, FeedReadMark> {
  $$FeedReadMarksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FeedsTable _feedIdTable(_$AppDatabase db) =>
      db.feeds.createAlias('feed_read_marks__feed_id__feeds__id');

  $$FeedsTableProcessedTableManager get feedId {
    final $_column = $_itemColumn<int>('feed_id')!;

    final manager = $$FeedsTableTableManager(
      $_db,
      $_db.feeds,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_feedIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FeedReadMarksTableFilterComposer
    extends Composer<_$AppDatabase, $FeedReadMarksTable> {
  $$FeedReadMarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadMessageId => $composableBuilder(
    column: $table.lastReadMessageId,
    builder: (column) => ColumnFilters(column),
  );

  $$FeedsTableFilterComposer get feedId {
    final $$FeedsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableFilterComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FeedReadMarksTableOrderingComposer
    extends Composer<_$AppDatabase, $FeedReadMarksTable> {
  $$FeedReadMarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadMessageId => $composableBuilder(
    column: $table.lastReadMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  $$FeedsTableOrderingComposer get feedId {
    final $$FeedsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableOrderingComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FeedReadMarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $FeedReadMarksTable> {
  $$FeedReadMarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<int> get lastReadMessageId => $composableBuilder(
    column: $table.lastReadMessageId,
    builder: (column) => column,
  );

  $$FeedsTableAnnotationComposer get feedId {
    final $$FeedsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.feeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FeedsTableAnnotationComposer(
            $db: $db,
            $table: $db.feeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FeedReadMarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FeedReadMarksTable,
          FeedReadMark,
          $$FeedReadMarksTableFilterComposer,
          $$FeedReadMarksTableOrderingComposer,
          $$FeedReadMarksTableAnnotationComposer,
          $$FeedReadMarksTableCreateCompanionBuilder,
          $$FeedReadMarksTableUpdateCompanionBuilder,
          (FeedReadMark, $$FeedReadMarksTableReferences),
          FeedReadMark,
          PrefetchHooks Function({bool feedId})
        > {
  $$FeedReadMarksTableTableManager(_$AppDatabase db, $FeedReadMarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FeedReadMarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FeedReadMarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FeedReadMarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> feedId = const Value.absent(),
                Value<int> chatId = const Value.absent(),
                Value<int> lastReadMessageId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FeedReadMarksCompanion(
                feedId: feedId,
                chatId: chatId,
                lastReadMessageId: lastReadMessageId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int feedId,
                required int chatId,
                required int lastReadMessageId,
                Value<int> rowid = const Value.absent(),
              }) => FeedReadMarksCompanion.insert(
                feedId: feedId,
                chatId: chatId,
                lastReadMessageId: lastReadMessageId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FeedReadMarksTable, FeedReadMark>(table),
                  $$FeedReadMarksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({feedId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (feedId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.feedId,
                        referencedTable: $$FeedReadMarksTableReferences
                            ._feedIdTable(db),
                        referencedColumn: $$FeedReadMarksTableReferences
                            ._feedIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FeedReadMarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FeedReadMarksTable,
      FeedReadMark,
      $$FeedReadMarksTableFilterComposer,
      $$FeedReadMarksTableOrderingComposer,
      $$FeedReadMarksTableAnnotationComposer,
      $$FeedReadMarksTableCreateCompanionBuilder,
      $$FeedReadMarksTableUpdateCompanionBuilder,
      (FeedReadMark, $$FeedReadMarksTableReferences),
      FeedReadMark,
      PrefetchHooks Function({bool feedId})
    >;
typedef $$WatchedChannelsTableCreateCompanionBuilder =
    WatchedChannelsCompanion Function({
      Value<int> chatId,
      required String title,
      Value<String?> username,
    });
typedef $$WatchedChannelsTableUpdateCompanionBuilder =
    WatchedChannelsCompanion Function({
      Value<int> chatId,
      Value<String> title,
      Value<String?> username,
    });

class $$WatchedChannelsTableFilterComposer
    extends Composer<_$AppDatabase, $WatchedChannelsTable> {
  $$WatchedChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchedChannelsTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchedChannelsTable> {
  $$WatchedChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchedChannelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchedChannelsTable> {
  $$WatchedChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);
}

class $$WatchedChannelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchedChannelsTable,
          WatchedChannel,
          $$WatchedChannelsTableFilterComposer,
          $$WatchedChannelsTableOrderingComposer,
          $$WatchedChannelsTableAnnotationComposer,
          $$WatchedChannelsTableCreateCompanionBuilder,
          $$WatchedChannelsTableUpdateCompanionBuilder,
          (
            WatchedChannel,
            BaseReferences<
              _$AppDatabase,
              $WatchedChannelsTable,
              WatchedChannel
            >,
          ),
          WatchedChannel,
          PrefetchHooks Function()
        > {
  $$WatchedChannelsTableTableManager(
    _$AppDatabase db,
    $WatchedChannelsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchedChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchedChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchedChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> chatId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> username = const Value.absent(),
              }) => WatchedChannelsCompanion(
                chatId: chatId,
                title: title,
                username: username,
              ),
          createCompanionCallback:
              ({
                Value<int> chatId = const Value.absent(),
                required String title,
                Value<String?> username = const Value.absent(),
              }) => WatchedChannelsCompanion.insert(
                chatId: chatId,
                title: title,
                username: username,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WatchedChannelsTable, WatchedChannel>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $WatchedChannelsTable,
                    WatchedChannel
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchedChannelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchedChannelsTable,
      WatchedChannel,
      $$WatchedChannelsTableFilterComposer,
      $$WatchedChannelsTableOrderingComposer,
      $$WatchedChannelsTableAnnotationComposer,
      $$WatchedChannelsTableCreateCompanionBuilder,
      $$WatchedChannelsTableUpdateCompanionBuilder,
      (
        WatchedChannel,
        BaseReferences<_$AppDatabase, $WatchedChannelsTable, WatchedChannel>,
      ),
      WatchedChannel,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$RulesTableCreateCompanionBuilder = RulesCompanion Function({
  Value<int> id,
  required String name,
  Value<bool> enabled,
  required String scopeKind,
  Value<int?> scopeChatId,
  required String conditionJson,
  required String priority,
  Value<bool> readAloud,
  Value<String?> scheduleJson,
  required DateTime createdAt,
});
typedef $$RulesTableUpdateCompanionBuilder = RulesCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<bool> enabled,
  Value<String> scopeKind,
  Value<int?> scopeChatId,
  Value<String> conditionJson,
  Value<String> priority,
  Value<bool> readAloud,
  Value<String?> scheduleJson,
  Value<DateTime> createdAt,
});

class $$RulesTableFilterComposer extends Composer<_$AppDatabase, $RulesTable> {
  $$RulesTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeKind => $composableBuilder(
    column: $table.scopeKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scopeChatId => $composableBuilder(
    column: $table.scopeChatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conditionJson => $composableBuilder(
    column: $table.conditionJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get readAloud => $composableBuilder(
    column: $table.readAloud,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduleJson => $composableBuilder(
    column: $table.scheduleJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RulesTableOrderingComposer
    extends Composer<_$AppDatabase, $RulesTable> {
  $$RulesTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeKind => $composableBuilder(
    column: $table.scopeKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scopeChatId => $composableBuilder(
    column: $table.scopeChatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conditionJson => $composableBuilder(
    column: $table.conditionJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get readAloud => $composableBuilder(
    column: $table.readAloud,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduleJson => $composableBuilder(
    column: $table.scheduleJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RulesTable> {
  $$RulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get scopeKind =>
      $composableBuilder(column: $table.scopeKind, builder: (column) => column);

  GeneratedColumn<int> get scopeChatId => $composableBuilder(
    column: $table.scopeChatId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conditionJson => $composableBuilder(
    column: $table.conditionJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<bool> get readAloud =>
      $composableBuilder(column: $table.readAloud, builder: (column) => column);

  GeneratedColumn<String> get scheduleJson => $composableBuilder(
    column: $table.scheduleJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$RulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RulesTable,
          Rule,
          $$RulesTableFilterComposer,
          $$RulesTableOrderingComposer,
          $$RulesTableAnnotationComposer,
          $$RulesTableCreateCompanionBuilder,
          $$RulesTableUpdateCompanionBuilder,
          (Rule, BaseReferences<_$AppDatabase, $RulesTable, Rule>),
          Rule,
          PrefetchHooks Function()
        > {
  $$RulesTableTableManager(_$AppDatabase db, $RulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> scopeKind = const Value.absent(),
                Value<int?> scopeChatId = const Value.absent(),
                Value<String> conditionJson = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<bool> readAloud = const Value.absent(),
                Value<String?> scheduleJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => RulesCompanion(
                id: id,
                name: name,
                enabled: enabled,
                scopeKind: scopeKind,
                scopeChatId: scopeChatId,
                conditionJson: conditionJson,
                priority: priority,
                readAloud: readAloud,
                scheduleJson: scheduleJson,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<bool> enabled = const Value.absent(),
                required String scopeKind,
                Value<int?> scopeChatId = const Value.absent(),
                required String conditionJson,
                required String priority,
                Value<bool> readAloud = const Value.absent(),
                Value<String?> scheduleJson = const Value.absent(),
                required DateTime createdAt,
              }) => RulesCompanion.insert(
                id: id,
                name: name,
                enabled: enabled,
                scopeKind: scopeKind,
                scopeChatId: scopeChatId,
                conditionJson: conditionJson,
                priority: priority,
                readAloud: readAloud,
                scheduleJson: scheduleJson,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RulesTable, Rule>(table),
                  BaseReferences<_$AppDatabase, $RulesTable, Rule>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RulesTable,
      Rule,
      $$RulesTableFilterComposer,
      $$RulesTableOrderingComposer,
      $$RulesTableAnnotationComposer,
      $$RulesTableCreateCompanionBuilder,
      $$RulesTableUpdateCompanionBuilder,
      (Rule, BaseReferences<_$AppDatabase, $RulesTable, Rule>),
      Rule,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FeedsTableTableManager get feeds =>
      $$FeedsTableTableManager(_db, _db.feeds);
  $$FeedSourcesTableTableManager get feedSources =>
      $$FeedSourcesTableTableManager(_db, _db.feedSources);
  $$FeedReadMarksTableTableManager get feedReadMarks =>
      $$FeedReadMarksTableTableManager(_db, _db.feedReadMarks);
  $$WatchedChannelsTableTableManager get watchedChannels =>
      $$WatchedChannelsTableTableManager(_db, _db.watchedChannels);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$RulesTableTableManager get rules =>
      $$RulesTableTableManager(_db, _db.rules);
}
