// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $WeakTopicsTable extends WeakTopics
    with TableInfo<$WeakTopicsTable, WeakTopic> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WeakTopicsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicNameMeta = const VerificationMeta(
    'topicName',
  );
  @override
  late final GeneratedColumn<String> topicName = GeneratedColumn<String>(
    'topic_name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ProficiencyLevel, String>
  proficiencyLevel =
      GeneratedColumn<String>(
        'proficiency_level',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ProficiencyLevel>(
        $WeakTopicsTable.$converterproficiencyLevel,
      );
  static const VerificationMeta _lastReviewedAtMeta = const VerificationMeta(
    'lastReviewedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastReviewedAt =
      GeneratedColumn<DateTime>(
        'last_reviewed_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subject,
    topicName,
    proficiencyLevel,
    lastReviewedAt,
    notes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'weak_topics';
  @override
  VerificationContext validateIntegrity(
    Insertable<WeakTopic> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('topic_name')) {
      context.handle(
        _topicNameMeta,
        topicName.isAcceptableOrUnknown(data['topic_name']!, _topicNameMeta),
      );
    } else if (isInserting) {
      context.missing(_topicNameMeta);
    }
    if (data.containsKey('last_reviewed_at')) {
      context.handle(
        _lastReviewedAtMeta,
        lastReviewedAt.isAcceptableOrUnknown(
          data['last_reviewed_at']!,
          _lastReviewedAtMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WeakTopic map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WeakTopic(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      topicName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_name'],
      )!,
      proficiencyLevel: $WeakTopicsTable.$converterproficiencyLevel.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}proficiency_level'],
        )!,
      ),
      lastReviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_reviewed_at'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $WeakTopicsTable createAlias(String alias) {
    return $WeakTopicsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ProficiencyLevel, String, String>
  $converterproficiencyLevel = const EnumNameConverter<ProficiencyLevel>(
    ProficiencyLevel.values,
  );
}

class WeakTopic extends DataClass implements Insertable<WeakTopic> {
  final int id;
  final String subject;
  final String topicName;
  final ProficiencyLevel proficiencyLevel;
  final DateTime? lastReviewedAt;
  final String? notes;
  final DateTime createdAt;
  const WeakTopic({
    required this.id,
    required this.subject,
    required this.topicName,
    required this.proficiencyLevel,
    this.lastReviewedAt,
    this.notes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['subject'] = Variable<String>(subject);
    map['topic_name'] = Variable<String>(topicName);
    {
      map['proficiency_level'] = Variable<String>(
        $WeakTopicsTable.$converterproficiencyLevel.toSql(proficiencyLevel),
      );
    }
    if (!nullToAbsent || lastReviewedAt != null) {
      map['last_reviewed_at'] = Variable<DateTime>(lastReviewedAt);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  WeakTopicsCompanion toCompanion(bool nullToAbsent) {
    return WeakTopicsCompanion(
      id: Value(id),
      subject: Value(subject),
      topicName: Value(topicName),
      proficiencyLevel: Value(proficiencyLevel),
      lastReviewedAt: lastReviewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReviewedAt),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
    );
  }

  factory WeakTopic.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WeakTopic(
      id: serializer.fromJson<int>(json['id']),
      subject: serializer.fromJson<String>(json['subject']),
      topicName: serializer.fromJson<String>(json['topicName']),
      proficiencyLevel: $WeakTopicsTable.$converterproficiencyLevel.fromJson(
        serializer.fromJson<String>(json['proficiencyLevel']),
      ),
      lastReviewedAt: serializer.fromJson<DateTime?>(json['lastReviewedAt']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'subject': serializer.toJson<String>(subject),
      'topicName': serializer.toJson<String>(topicName),
      'proficiencyLevel': serializer.toJson<String>(
        $WeakTopicsTable.$converterproficiencyLevel.toJson(proficiencyLevel),
      ),
      'lastReviewedAt': serializer.toJson<DateTime?>(lastReviewedAt),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  WeakTopic copyWith({
    int? id,
    String? subject,
    String? topicName,
    ProficiencyLevel? proficiencyLevel,
    Value<DateTime?> lastReviewedAt = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
  }) => WeakTopic(
    id: id ?? this.id,
    subject: subject ?? this.subject,
    topicName: topicName ?? this.topicName,
    proficiencyLevel: proficiencyLevel ?? this.proficiencyLevel,
    lastReviewedAt: lastReviewedAt.present
        ? lastReviewedAt.value
        : this.lastReviewedAt,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
  );
  WeakTopic copyWithCompanion(WeakTopicsCompanion data) {
    return WeakTopic(
      id: data.id.present ? data.id.value : this.id,
      subject: data.subject.present ? data.subject.value : this.subject,
      topicName: data.topicName.present ? data.topicName.value : this.topicName,
      proficiencyLevel: data.proficiencyLevel.present
          ? data.proficiencyLevel.value
          : this.proficiencyLevel,
      lastReviewedAt: data.lastReviewedAt.present
          ? data.lastReviewedAt.value
          : this.lastReviewedAt,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WeakTopic(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('topicName: $topicName, ')
          ..write('proficiencyLevel: $proficiencyLevel, ')
          ..write('lastReviewedAt: $lastReviewedAt, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    subject,
    topicName,
    proficiencyLevel,
    lastReviewedAt,
    notes,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WeakTopic &&
          other.id == this.id &&
          other.subject == this.subject &&
          other.topicName == this.topicName &&
          other.proficiencyLevel == this.proficiencyLevel &&
          other.lastReviewedAt == this.lastReviewedAt &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt);
}

class WeakTopicsCompanion extends UpdateCompanion<WeakTopic> {
  final Value<int> id;
  final Value<String> subject;
  final Value<String> topicName;
  final Value<ProficiencyLevel> proficiencyLevel;
  final Value<DateTime?> lastReviewedAt;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  const WeakTopicsCompanion({
    this.id = const Value.absent(),
    this.subject = const Value.absent(),
    this.topicName = const Value.absent(),
    this.proficiencyLevel = const Value.absent(),
    this.lastReviewedAt = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  WeakTopicsCompanion.insert({
    this.id = const Value.absent(),
    required String subject,
    required String topicName,
    required ProficiencyLevel proficiencyLevel,
    this.lastReviewedAt = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : subject = Value(subject),
       topicName = Value(topicName),
       proficiencyLevel = Value(proficiencyLevel);
  static Insertable<WeakTopic> custom({
    Expression<int>? id,
    Expression<String>? subject,
    Expression<String>? topicName,
    Expression<String>? proficiencyLevel,
    Expression<DateTime>? lastReviewedAt,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subject != null) 'subject': subject,
      if (topicName != null) 'topic_name': topicName,
      if (proficiencyLevel != null) 'proficiency_level': proficiencyLevel,
      if (lastReviewedAt != null) 'last_reviewed_at': lastReviewedAt,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  WeakTopicsCompanion copyWith({
    Value<int>? id,
    Value<String>? subject,
    Value<String>? topicName,
    Value<ProficiencyLevel>? proficiencyLevel,
    Value<DateTime?>? lastReviewedAt,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
  }) {
    return WeakTopicsCompanion(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      topicName: topicName ?? this.topicName,
      proficiencyLevel: proficiencyLevel ?? this.proficiencyLevel,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (topicName.present) {
      map['topic_name'] = Variable<String>(topicName.value);
    }
    if (proficiencyLevel.present) {
      map['proficiency_level'] = Variable<String>(
        $WeakTopicsTable.$converterproficiencyLevel.toSql(
          proficiencyLevel.value,
        ),
      );
    }
    if (lastReviewedAt.present) {
      map['last_reviewed_at'] = Variable<DateTime>(lastReviewedAt.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WeakTopicsCompanion(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('topicName: $topicName, ')
          ..write('proficiencyLevel: $proficiencyLevel, ')
          ..write('lastReviewedAt: $lastReviewedAt, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ExamSchedulesTable extends ExamSchedules
    with TableInfo<$ExamSchedulesTable, ExamSchedule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExamSchedulesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _examDateMeta = const VerificationMeta(
    'examDate',
  );
  @override
  late final GeneratedColumn<DateTime> examDate = GeneratedColumn<DateTime>(
    'exam_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _examTimeMeta = const VerificationMeta(
    'examTime',
  );
  @override
  late final GeneratedColumn<String> examTime = GeneratedColumn<String>(
    'exam_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('10:00 PM'),
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('General'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicsCoveredMeta = const VerificationMeta(
    'topicsCovered',
  );
  @override
  late final GeneratedColumn<String> topicsCovered = GeneratedColumn<String>(
    'topics_covered',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _examTypeMeta = const VerificationMeta(
    'examType',
  );
  @override
  late final GeneratedColumn<String> examType = GeneratedColumn<String>(
    'exam_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Daily'),
  );
  static const VerificationMeta _trackNameMeta = const VerificationMeta(
    'trackName',
  );
  @override
  late final GeneratedColumn<String> trackName = GeneratedColumn<String>(
    'track_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('General BCS'),
  );
  static const VerificationMeta _resourceSummaryMeta = const VerificationMeta(
    'resourceSummary',
  );
  @override
  late final GeneratedColumn<String> resourceSummary = GeneratedColumn<String>(
    'resource_summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawReferenceMeta = const VerificationMeta(
    'rawReference',
  );
  @override
  late final GeneratedColumn<String> rawReference = GeneratedColumn<String>(
    'raw_reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedStatusMeta = const VerificationMeta(
    'completedStatus',
  );
  @override
  late final GeneratedColumn<bool> completedStatus = GeneratedColumn<bool>(
    'completed_status',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed_status" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
    'score',
    aliasedName,
    true,
    type: DriftSqlType.double,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    examDate,
    examTime,
    subject,
    title,
    topicsCovered,
    examType,
    trackName,
    resourceSummary,
    rawReference,
    completedStatus,
    score,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'exam_schedules';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExamSchedule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('exam_date')) {
      context.handle(
        _examDateMeta,
        examDate.isAcceptableOrUnknown(data['exam_date']!, _examDateMeta),
      );
    } else if (isInserting) {
      context.missing(_examDateMeta);
    }
    if (data.containsKey('exam_time')) {
      context.handle(
        _examTimeMeta,
        examTime.isAcceptableOrUnknown(data['exam_time']!, _examTimeMeta),
      );
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
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
    if (data.containsKey('topics_covered')) {
      context.handle(
        _topicsCoveredMeta,
        topicsCovered.isAcceptableOrUnknown(
          data['topics_covered']!,
          _topicsCoveredMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_topicsCoveredMeta);
    }
    if (data.containsKey('exam_type')) {
      context.handle(
        _examTypeMeta,
        examType.isAcceptableOrUnknown(data['exam_type']!, _examTypeMeta),
      );
    }
    if (data.containsKey('track_name')) {
      context.handle(
        _trackNameMeta,
        trackName.isAcceptableOrUnknown(data['track_name']!, _trackNameMeta),
      );
    }
    if (data.containsKey('resource_summary')) {
      context.handle(
        _resourceSummaryMeta,
        resourceSummary.isAcceptableOrUnknown(
          data['resource_summary']!,
          _resourceSummaryMeta,
        ),
      );
    }
    if (data.containsKey('raw_reference')) {
      context.handle(
        _rawReferenceMeta,
        rawReference.isAcceptableOrUnknown(
          data['raw_reference']!,
          _rawReferenceMeta,
        ),
      );
    }
    if (data.containsKey('completed_status')) {
      context.handle(
        _completedStatusMeta,
        completedStatus.isAcceptableOrUnknown(
          data['completed_status']!,
          _completedStatusMeta,
        ),
      );
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExamSchedule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExamSchedule(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      examDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}exam_date'],
      )!,
      examTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exam_time'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      topicsCovered: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topics_covered'],
      )!,
      examType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exam_type'],
      )!,
      trackName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_name'],
      )!,
      resourceSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource_summary'],
      ),
      rawReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_reference'],
      ),
      completedStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed_status'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ExamSchedulesTable createAlias(String alias) {
    return $ExamSchedulesTable(attachedDatabase, alias);
  }
}

class ExamSchedule extends DataClass implements Insertable<ExamSchedule> {
  final int id;
  final DateTime examDate;
  final String examTime;
  final String subject;
  final String title;
  final String topicsCovered;
  final String examType;
  final String trackName;
  final String? resourceSummary;
  final String? rawReference;
  final bool completedStatus;
  final double? score;
  final DateTime createdAt;
  const ExamSchedule({
    required this.id,
    required this.examDate,
    required this.examTime,
    required this.subject,
    required this.title,
    required this.topicsCovered,
    required this.examType,
    required this.trackName,
    this.resourceSummary,
    this.rawReference,
    required this.completedStatus,
    this.score,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['exam_date'] = Variable<DateTime>(examDate);
    map['exam_time'] = Variable<String>(examTime);
    map['subject'] = Variable<String>(subject);
    map['title'] = Variable<String>(title);
    map['topics_covered'] = Variable<String>(topicsCovered);
    map['exam_type'] = Variable<String>(examType);
    map['track_name'] = Variable<String>(trackName);
    if (!nullToAbsent || resourceSummary != null) {
      map['resource_summary'] = Variable<String>(resourceSummary);
    }
    if (!nullToAbsent || rawReference != null) {
      map['raw_reference'] = Variable<String>(rawReference);
    }
    map['completed_status'] = Variable<bool>(completedStatus);
    if (!nullToAbsent || score != null) {
      map['score'] = Variable<double>(score);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ExamSchedulesCompanion toCompanion(bool nullToAbsent) {
    return ExamSchedulesCompanion(
      id: Value(id),
      examDate: Value(examDate),
      examTime: Value(examTime),
      subject: Value(subject),
      title: Value(title),
      topicsCovered: Value(topicsCovered),
      examType: Value(examType),
      trackName: Value(trackName),
      resourceSummary: resourceSummary == null && nullToAbsent
          ? const Value.absent()
          : Value(resourceSummary),
      rawReference: rawReference == null && nullToAbsent
          ? const Value.absent()
          : Value(rawReference),
      completedStatus: Value(completedStatus),
      score: score == null && nullToAbsent
          ? const Value.absent()
          : Value(score),
      createdAt: Value(createdAt),
    );
  }

  factory ExamSchedule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExamSchedule(
      id: serializer.fromJson<int>(json['id']),
      examDate: serializer.fromJson<DateTime>(json['examDate']),
      examTime: serializer.fromJson<String>(json['examTime']),
      subject: serializer.fromJson<String>(json['subject']),
      title: serializer.fromJson<String>(json['title']),
      topicsCovered: serializer.fromJson<String>(json['topicsCovered']),
      examType: serializer.fromJson<String>(json['examType']),
      trackName: serializer.fromJson<String>(json['trackName']),
      resourceSummary: serializer.fromJson<String?>(json['resourceSummary']),
      rawReference: serializer.fromJson<String?>(json['rawReference']),
      completedStatus: serializer.fromJson<bool>(json['completedStatus']),
      score: serializer.fromJson<double?>(json['score']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'examDate': serializer.toJson<DateTime>(examDate),
      'examTime': serializer.toJson<String>(examTime),
      'subject': serializer.toJson<String>(subject),
      'title': serializer.toJson<String>(title),
      'topicsCovered': serializer.toJson<String>(topicsCovered),
      'examType': serializer.toJson<String>(examType),
      'trackName': serializer.toJson<String>(trackName),
      'resourceSummary': serializer.toJson<String?>(resourceSummary),
      'rawReference': serializer.toJson<String?>(rawReference),
      'completedStatus': serializer.toJson<bool>(completedStatus),
      'score': serializer.toJson<double?>(score),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ExamSchedule copyWith({
    int? id,
    DateTime? examDate,
    String? examTime,
    String? subject,
    String? title,
    String? topicsCovered,
    String? examType,
    String? trackName,
    Value<String?> resourceSummary = const Value.absent(),
    Value<String?> rawReference = const Value.absent(),
    bool? completedStatus,
    Value<double?> score = const Value.absent(),
    DateTime? createdAt,
  }) => ExamSchedule(
    id: id ?? this.id,
    examDate: examDate ?? this.examDate,
    examTime: examTime ?? this.examTime,
    subject: subject ?? this.subject,
    title: title ?? this.title,
    topicsCovered: topicsCovered ?? this.topicsCovered,
    examType: examType ?? this.examType,
    trackName: trackName ?? this.trackName,
    resourceSummary: resourceSummary.present
        ? resourceSummary.value
        : this.resourceSummary,
    rawReference: rawReference.present ? rawReference.value : this.rawReference,
    completedStatus: completedStatus ?? this.completedStatus,
    score: score.present ? score.value : this.score,
    createdAt: createdAt ?? this.createdAt,
  );
  ExamSchedule copyWithCompanion(ExamSchedulesCompanion data) {
    return ExamSchedule(
      id: data.id.present ? data.id.value : this.id,
      examDate: data.examDate.present ? data.examDate.value : this.examDate,
      examTime: data.examTime.present ? data.examTime.value : this.examTime,
      subject: data.subject.present ? data.subject.value : this.subject,
      title: data.title.present ? data.title.value : this.title,
      topicsCovered: data.topicsCovered.present
          ? data.topicsCovered.value
          : this.topicsCovered,
      examType: data.examType.present ? data.examType.value : this.examType,
      trackName: data.trackName.present ? data.trackName.value : this.trackName,
      resourceSummary: data.resourceSummary.present
          ? data.resourceSummary.value
          : this.resourceSummary,
      rawReference: data.rawReference.present
          ? data.rawReference.value
          : this.rawReference,
      completedStatus: data.completedStatus.present
          ? data.completedStatus.value
          : this.completedStatus,
      score: data.score.present ? data.score.value : this.score,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExamSchedule(')
          ..write('id: $id, ')
          ..write('examDate: $examDate, ')
          ..write('examTime: $examTime, ')
          ..write('subject: $subject, ')
          ..write('title: $title, ')
          ..write('topicsCovered: $topicsCovered, ')
          ..write('examType: $examType, ')
          ..write('trackName: $trackName, ')
          ..write('resourceSummary: $resourceSummary, ')
          ..write('rawReference: $rawReference, ')
          ..write('completedStatus: $completedStatus, ')
          ..write('score: $score, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    examDate,
    examTime,
    subject,
    title,
    topicsCovered,
    examType,
    trackName,
    resourceSummary,
    rawReference,
    completedStatus,
    score,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExamSchedule &&
          other.id == this.id &&
          other.examDate == this.examDate &&
          other.examTime == this.examTime &&
          other.subject == this.subject &&
          other.title == this.title &&
          other.topicsCovered == this.topicsCovered &&
          other.examType == this.examType &&
          other.trackName == this.trackName &&
          other.resourceSummary == this.resourceSummary &&
          other.rawReference == this.rawReference &&
          other.completedStatus == this.completedStatus &&
          other.score == this.score &&
          other.createdAt == this.createdAt);
}

class ExamSchedulesCompanion extends UpdateCompanion<ExamSchedule> {
  final Value<int> id;
  final Value<DateTime> examDate;
  final Value<String> examTime;
  final Value<String> subject;
  final Value<String> title;
  final Value<String> topicsCovered;
  final Value<String> examType;
  final Value<String> trackName;
  final Value<String?> resourceSummary;
  final Value<String?> rawReference;
  final Value<bool> completedStatus;
  final Value<double?> score;
  final Value<DateTime> createdAt;
  const ExamSchedulesCompanion({
    this.id = const Value.absent(),
    this.examDate = const Value.absent(),
    this.examTime = const Value.absent(),
    this.subject = const Value.absent(),
    this.title = const Value.absent(),
    this.topicsCovered = const Value.absent(),
    this.examType = const Value.absent(),
    this.trackName = const Value.absent(),
    this.resourceSummary = const Value.absent(),
    this.rawReference = const Value.absent(),
    this.completedStatus = const Value.absent(),
    this.score = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ExamSchedulesCompanion.insert({
    this.id = const Value.absent(),
    required DateTime examDate,
    this.examTime = const Value.absent(),
    this.subject = const Value.absent(),
    required String title,
    required String topicsCovered,
    this.examType = const Value.absent(),
    this.trackName = const Value.absent(),
    this.resourceSummary = const Value.absent(),
    this.rawReference = const Value.absent(),
    this.completedStatus = const Value.absent(),
    this.score = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : examDate = Value(examDate),
       title = Value(title),
       topicsCovered = Value(topicsCovered);
  static Insertable<ExamSchedule> custom({
    Expression<int>? id,
    Expression<DateTime>? examDate,
    Expression<String>? examTime,
    Expression<String>? subject,
    Expression<String>? title,
    Expression<String>? topicsCovered,
    Expression<String>? examType,
    Expression<String>? trackName,
    Expression<String>? resourceSummary,
    Expression<String>? rawReference,
    Expression<bool>? completedStatus,
    Expression<double>? score,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (examDate != null) 'exam_date': examDate,
      if (examTime != null) 'exam_time': examTime,
      if (subject != null) 'subject': subject,
      if (title != null) 'title': title,
      if (topicsCovered != null) 'topics_covered': topicsCovered,
      if (examType != null) 'exam_type': examType,
      if (trackName != null) 'track_name': trackName,
      if (resourceSummary != null) 'resource_summary': resourceSummary,
      if (rawReference != null) 'raw_reference': rawReference,
      if (completedStatus != null) 'completed_status': completedStatus,
      if (score != null) 'score': score,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ExamSchedulesCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? examDate,
    Value<String>? examTime,
    Value<String>? subject,
    Value<String>? title,
    Value<String>? topicsCovered,
    Value<String>? examType,
    Value<String>? trackName,
    Value<String?>? resourceSummary,
    Value<String?>? rawReference,
    Value<bool>? completedStatus,
    Value<double?>? score,
    Value<DateTime>? createdAt,
  }) {
    return ExamSchedulesCompanion(
      id: id ?? this.id,
      examDate: examDate ?? this.examDate,
      examTime: examTime ?? this.examTime,
      subject: subject ?? this.subject,
      title: title ?? this.title,
      topicsCovered: topicsCovered ?? this.topicsCovered,
      examType: examType ?? this.examType,
      trackName: trackName ?? this.trackName,
      resourceSummary: resourceSummary ?? this.resourceSummary,
      rawReference: rawReference ?? this.rawReference,
      completedStatus: completedStatus ?? this.completedStatus,
      score: score ?? this.score,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (examDate.present) {
      map['exam_date'] = Variable<DateTime>(examDate.value);
    }
    if (examTime.present) {
      map['exam_time'] = Variable<String>(examTime.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (topicsCovered.present) {
      map['topics_covered'] = Variable<String>(topicsCovered.value);
    }
    if (examType.present) {
      map['exam_type'] = Variable<String>(examType.value);
    }
    if (trackName.present) {
      map['track_name'] = Variable<String>(trackName.value);
    }
    if (resourceSummary.present) {
      map['resource_summary'] = Variable<String>(resourceSummary.value);
    }
    if (rawReference.present) {
      map['raw_reference'] = Variable<String>(rawReference.value);
    }
    if (completedStatus.present) {
      map['completed_status'] = Variable<bool>(completedStatus.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExamSchedulesCompanion(')
          ..write('id: $id, ')
          ..write('examDate: $examDate, ')
          ..write('examTime: $examTime, ')
          ..write('subject: $subject, ')
          ..write('title: $title, ')
          ..write('topicsCovered: $topicsCovered, ')
          ..write('examType: $examType, ')
          ..write('trackName: $trackName, ')
          ..write('resourceSummary: $resourceSummary, ')
          ..write('rawReference: $rawReference, ')
          ..write('completedStatus: $completedStatus, ')
          ..write('score: $score, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DailyEnergyLogsTable extends DailyEnergyLogs
    with TableInfo<$DailyEnergyLogsTable, DailyEnergyLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyEnergyLogsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EnergyLevel, String> energyLevel =
      GeneratedColumn<String>(
        'energy_level',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EnergyLevel>($DailyEnergyLogsTable.$converterenergyLevel);
  static const VerificationMeta _officeFatigueScoreMeta =
      const VerificationMeta('officeFatigueScore');
  @override
  late final GeneratedColumn<int> officeFatigueScore = GeneratedColumn<int>(
    'office_fatigue_score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(5),
  );
  static const VerificationMeta _completedTasksMeta = const VerificationMeta(
    'completedTasks',
  );
  @override
  late final GeneratedColumn<String> completedTasks = GeneratedColumn<String>(
    'completed_tasks',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    energyLevel,
    officeFatigueScore,
    completedTasks,
    notes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_energy_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyEnergyLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('office_fatigue_score')) {
      context.handle(
        _officeFatigueScoreMeta,
        officeFatigueScore.isAcceptableOrUnknown(
          data['office_fatigue_score']!,
          _officeFatigueScoreMeta,
        ),
      );
    }
    if (data.containsKey('completed_tasks')) {
      context.handle(
        _completedTasksMeta,
        completedTasks.isAcceptableOrUnknown(
          data['completed_tasks']!,
          _completedTasksMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DailyEnergyLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyEnergyLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      energyLevel: $DailyEnergyLogsTable.$converterenergyLevel.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}energy_level'],
        )!,
      ),
      officeFatigueScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}office_fatigue_score'],
      )!,
      completedTasks: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}completed_tasks'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DailyEnergyLogsTable createAlias(String alias) {
    return $DailyEnergyLogsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EnergyLevel, String, String> $converterenergyLevel =
      const EnumNameConverter<EnergyLevel>(EnergyLevel.values);
}

class DailyEnergyLog extends DataClass implements Insertable<DailyEnergyLog> {
  final int id;
  final DateTime date;
  final EnergyLevel energyLevel;
  final int officeFatigueScore;
  final String completedTasks;
  final String? notes;
  final DateTime createdAt;
  const DailyEnergyLog({
    required this.id,
    required this.date,
    required this.energyLevel,
    required this.officeFatigueScore,
    required this.completedTasks,
    this.notes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<DateTime>(date);
    {
      map['energy_level'] = Variable<String>(
        $DailyEnergyLogsTable.$converterenergyLevel.toSql(energyLevel),
      );
    }
    map['office_fatigue_score'] = Variable<int>(officeFatigueScore);
    map['completed_tasks'] = Variable<String>(completedTasks);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DailyEnergyLogsCompanion toCompanion(bool nullToAbsent) {
    return DailyEnergyLogsCompanion(
      id: Value(id),
      date: Value(date),
      energyLevel: Value(energyLevel),
      officeFatigueScore: Value(officeFatigueScore),
      completedTasks: Value(completedTasks),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
    );
  }

  factory DailyEnergyLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyEnergyLog(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<DateTime>(json['date']),
      energyLevel: $DailyEnergyLogsTable.$converterenergyLevel.fromJson(
        serializer.fromJson<String>(json['energyLevel']),
      ),
      officeFatigueScore: serializer.fromJson<int>(json['officeFatigueScore']),
      completedTasks: serializer.fromJson<String>(json['completedTasks']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<DateTime>(date),
      'energyLevel': serializer.toJson<String>(
        $DailyEnergyLogsTable.$converterenergyLevel.toJson(energyLevel),
      ),
      'officeFatigueScore': serializer.toJson<int>(officeFatigueScore),
      'completedTasks': serializer.toJson<String>(completedTasks),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DailyEnergyLog copyWith({
    int? id,
    DateTime? date,
    EnergyLevel? energyLevel,
    int? officeFatigueScore,
    String? completedTasks,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
  }) => DailyEnergyLog(
    id: id ?? this.id,
    date: date ?? this.date,
    energyLevel: energyLevel ?? this.energyLevel,
    officeFatigueScore: officeFatigueScore ?? this.officeFatigueScore,
    completedTasks: completedTasks ?? this.completedTasks,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
  );
  DailyEnergyLog copyWithCompanion(DailyEnergyLogsCompanion data) {
    return DailyEnergyLog(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      energyLevel: data.energyLevel.present
          ? data.energyLevel.value
          : this.energyLevel,
      officeFatigueScore: data.officeFatigueScore.present
          ? data.officeFatigueScore.value
          : this.officeFatigueScore,
      completedTasks: data.completedTasks.present
          ? data.completedTasks.value
          : this.completedTasks,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyEnergyLog(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('energyLevel: $energyLevel, ')
          ..write('officeFatigueScore: $officeFatigueScore, ')
          ..write('completedTasks: $completedTasks, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    date,
    energyLevel,
    officeFatigueScore,
    completedTasks,
    notes,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyEnergyLog &&
          other.id == this.id &&
          other.date == this.date &&
          other.energyLevel == this.energyLevel &&
          other.officeFatigueScore == this.officeFatigueScore &&
          other.completedTasks == this.completedTasks &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt);
}

class DailyEnergyLogsCompanion extends UpdateCompanion<DailyEnergyLog> {
  final Value<int> id;
  final Value<DateTime> date;
  final Value<EnergyLevel> energyLevel;
  final Value<int> officeFatigueScore;
  final Value<String> completedTasks;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  const DailyEnergyLogsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.energyLevel = const Value.absent(),
    this.officeFatigueScore = const Value.absent(),
    this.completedTasks = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  DailyEnergyLogsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime date,
    required EnergyLevel energyLevel,
    this.officeFatigueScore = const Value.absent(),
    this.completedTasks = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : date = Value(date),
       energyLevel = Value(energyLevel);
  static Insertable<DailyEnergyLog> custom({
    Expression<int>? id,
    Expression<DateTime>? date,
    Expression<String>? energyLevel,
    Expression<int>? officeFatigueScore,
    Expression<String>? completedTasks,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (energyLevel != null) 'energy_level': energyLevel,
      if (officeFatigueScore != null)
        'office_fatigue_score': officeFatigueScore,
      if (completedTasks != null) 'completed_tasks': completedTasks,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  DailyEnergyLogsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? date,
    Value<EnergyLevel>? energyLevel,
    Value<int>? officeFatigueScore,
    Value<String>? completedTasks,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
  }) {
    return DailyEnergyLogsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      energyLevel: energyLevel ?? this.energyLevel,
      officeFatigueScore: officeFatigueScore ?? this.officeFatigueScore,
      completedTasks: completedTasks ?? this.completedTasks,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (energyLevel.present) {
      map['energy_level'] = Variable<String>(
        $DailyEnergyLogsTable.$converterenergyLevel.toSql(energyLevel.value),
      );
    }
    if (officeFatigueScore.present) {
      map['office_fatigue_score'] = Variable<int>(officeFatigueScore.value);
    }
    if (completedTasks.present) {
      map['completed_tasks'] = Variable<String>(completedTasks.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyEnergyLogsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('energyLevel: $energyLevel, ')
          ..write('officeFatigueScore: $officeFatigueScore, ')
          ..write('completedTasks: $completedTasks, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
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
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
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
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
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

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
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
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
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

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
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
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatSessionsTable extends ChatSessions
    with TableInfo<$ChatSessionsTable, ChatSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatSessionsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
    'topic',
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summarizedUpToIdMeta = const VerificationMeta(
    'summarizedUpToId',
  );
  @override
  late final GeneratedColumn<int> summarizedUpToId = GeneratedColumn<int>(
    'summarized_up_to_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    subject,
    topic,
    createdAt,
    updatedAt,
    summary,
    summarizedUpToId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    }
    if (data.containsKey('topic')) {
      context.handle(
        _topicMeta,
        topic.isAcceptableOrUnknown(data['topic']!, _topicMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('summarized_up_to_id')) {
      context.handle(
        _summarizedUpToIdMeta,
        summarizedUpToId.isAcceptableOrUnknown(
          data['summarized_up_to_id']!,
          _summarizedUpToIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      ),
      topic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      summarizedUpToId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}summarized_up_to_id'],
      ),
    );
  }

  @override
  $ChatSessionsTable createAlias(String alias) {
    return $ChatSessionsTable(attachedDatabase, alias);
  }
}

class ChatSession extends DataClass implements Insertable<ChatSession> {
  final int id;
  final String title;
  final String? subject;
  final String? topic;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Running summary of everything that fell out of the replayed history
  /// window, so a long thread keeps its continuity instead of silently
  /// forgetting whatever happened more than a handful of exchanges ago.
  final String? summary;

  /// Id of the last chat message already folded into [summary].
  final int? summarizedUpToId;
  const ChatSession({
    required this.id,
    required this.title,
    this.subject,
    this.topic,
    required this.createdAt,
    required this.updatedAt,
    this.summary,
    this.summarizedUpToId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || subject != null) {
      map['subject'] = Variable<String>(subject);
    }
    if (!nullToAbsent || topic != null) {
      map['topic'] = Variable<String>(topic);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    if (!nullToAbsent || summarizedUpToId != null) {
      map['summarized_up_to_id'] = Variable<int>(summarizedUpToId);
    }
    return map;
  }

  ChatSessionsCompanion toCompanion(bool nullToAbsent) {
    return ChatSessionsCompanion(
      id: Value(id),
      title: Value(title),
      subject: subject == null && nullToAbsent
          ? const Value.absent()
          : Value(subject),
      topic: topic == null && nullToAbsent
          ? const Value.absent()
          : Value(topic),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      summarizedUpToId: summarizedUpToId == null && nullToAbsent
          ? const Value.absent()
          : Value(summarizedUpToId),
    );
  }

  factory ChatSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatSession(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      subject: serializer.fromJson<String?>(json['subject']),
      topic: serializer.fromJson<String?>(json['topic']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      summary: serializer.fromJson<String?>(json['summary']),
      summarizedUpToId: serializer.fromJson<int?>(json['summarizedUpToId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'subject': serializer.toJson<String?>(subject),
      'topic': serializer.toJson<String?>(topic),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'summary': serializer.toJson<String?>(summary),
      'summarizedUpToId': serializer.toJson<int?>(summarizedUpToId),
    };
  }

  ChatSession copyWith({
    int? id,
    String? title,
    Value<String?> subject = const Value.absent(),
    Value<String?> topic = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> summary = const Value.absent(),
    Value<int?> summarizedUpToId = const Value.absent(),
  }) => ChatSession(
    id: id ?? this.id,
    title: title ?? this.title,
    subject: subject.present ? subject.value : this.subject,
    topic: topic.present ? topic.value : this.topic,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    summary: summary.present ? summary.value : this.summary,
    summarizedUpToId: summarizedUpToId.present
        ? summarizedUpToId.value
        : this.summarizedUpToId,
  );
  ChatSession copyWithCompanion(ChatSessionsCompanion data) {
    return ChatSession(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      subject: data.subject.present ? data.subject.value : this.subject,
      topic: data.topic.present ? data.topic.value : this.topic,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      summary: data.summary.present ? data.summary.value : this.summary,
      summarizedUpToId: data.summarizedUpToId.present
          ? data.summarizedUpToId.value
          : this.summarizedUpToId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatSession(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('subject: $subject, ')
          ..write('topic: $topic, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('summary: $summary, ')
          ..write('summarizedUpToId: $summarizedUpToId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    subject,
    topic,
    createdAt,
    updatedAt,
    summary,
    summarizedUpToId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatSession &&
          other.id == this.id &&
          other.title == this.title &&
          other.subject == this.subject &&
          other.topic == this.topic &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.summary == this.summary &&
          other.summarizedUpToId == this.summarizedUpToId);
}

class ChatSessionsCompanion extends UpdateCompanion<ChatSession> {
  final Value<int> id;
  final Value<String> title;
  final Value<String?> subject;
  final Value<String?> topic;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> summary;
  final Value<int?> summarizedUpToId;
  const ChatSessionsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.subject = const Value.absent(),
    this.topic = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.summary = const Value.absent(),
    this.summarizedUpToId = const Value.absent(),
  });
  ChatSessionsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.subject = const Value.absent(),
    this.topic = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.summary = const Value.absent(),
    this.summarizedUpToId = const Value.absent(),
  }) : title = Value(title);
  static Insertable<ChatSession> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? subject,
    Expression<String>? topic,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? summary,
    Expression<int>? summarizedUpToId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (subject != null) 'subject': subject,
      if (topic != null) 'topic': topic,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (summary != null) 'summary': summary,
      if (summarizedUpToId != null) 'summarized_up_to_id': summarizedUpToId,
    });
  }

  ChatSessionsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String?>? subject,
    Value<String?>? topic,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? summary,
    Value<int?>? summarizedUpToId,
  }) {
    return ChatSessionsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      summary: summary ?? this.summary,
      summarizedUpToId: summarizedUpToId ?? this.summarizedUpToId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (summarizedUpToId.present) {
      map['summarized_up_to_id'] = Variable<int>(summarizedUpToId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatSessionsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('subject: $subject, ')
          ..write('topic: $topic, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('summary: $summary, ')
          ..write('summarizedUpToId: $summarizedUpToId')
          ..write(')'))
        .toString();
  }
}

class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, ChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _textContentMeta = const VerificationMeta(
    'textContent',
  );
  @override
  late final GeneratedColumn<String> textContent = GeneratedColumn<String>(
    'text_content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _suggestedActionMeta = const VerificationMeta(
    'suggestedAction',
  );
  @override
  late final GeneratedColumn<String> suggestedAction = GeneratedColumn<String>(
    'suggested_action',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    role,
    textContent,
    suggestedAction,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('text_content')) {
      context.handle(
        _textContentMeta,
        textContent.isAcceptableOrUnknown(
          data['text_content']!,
          _textContentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_textContentMeta);
    }
    if (data.containsKey('suggested_action')) {
      context.handle(
        _suggestedActionMeta,
        suggestedAction.isAcceptableOrUnknown(
          data['suggested_action']!,
          _suggestedActionMeta,
        ),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      ),
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      textContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_content'],
      )!,
      suggestedAction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suggested_action'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }
}

class ChatMessage extends DataClass implements Insertable<ChatMessage> {
  final int id;
  final int? sessionId;
  final String role;
  final String textContent;
  final String? suggestedAction;
  final DateTime timestamp;
  const ChatMessage({
    required this.id,
    this.sessionId,
    required this.role,
    required this.textContent,
    this.suggestedAction,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<int>(sessionId);
    }
    map['role'] = Variable<String>(role);
    map['text_content'] = Variable<String>(textContent);
    if (!nullToAbsent || suggestedAction != null) {
      map['suggested_action'] = Variable<String>(suggestedAction);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      id: Value(id),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      role: Value(role),
      textContent: Value(textContent),
      suggestedAction: suggestedAction == null && nullToAbsent
          ? const Value.absent()
          : Value(suggestedAction),
      timestamp: Value(timestamp),
    );
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessage(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<int?>(json['sessionId']),
      role: serializer.fromJson<String>(json['role']),
      textContent: serializer.fromJson<String>(json['textContent']),
      suggestedAction: serializer.fromJson<String?>(json['suggestedAction']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<int?>(sessionId),
      'role': serializer.toJson<String>(role),
      'textContent': serializer.toJson<String>(textContent),
      'suggestedAction': serializer.toJson<String?>(suggestedAction),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  ChatMessage copyWith({
    int? id,
    Value<int?> sessionId = const Value.absent(),
    String? role,
    String? textContent,
    Value<String?> suggestedAction = const Value.absent(),
    DateTime? timestamp,
  }) => ChatMessage(
    id: id ?? this.id,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    role: role ?? this.role,
    textContent: textContent ?? this.textContent,
    suggestedAction: suggestedAction.present
        ? suggestedAction.value
        : this.suggestedAction,
    timestamp: timestamp ?? this.timestamp,
  );
  ChatMessage copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessage(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      role: data.role.present ? data.role.value : this.role,
      textContent: data.textContent.present
          ? data.textContent.value
          : this.textContent,
      suggestedAction: data.suggestedAction.present
          ? data.suggestedAction.value
          : this.suggestedAction,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessage(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('textContent: $textContent, ')
          ..write('suggestedAction: $suggestedAction, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sessionId, role, textContent, suggestedAction, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.role == this.role &&
          other.textContent == this.textContent &&
          other.suggestedAction == this.suggestedAction &&
          other.timestamp == this.timestamp);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessage> {
  final Value<int> id;
  final Value<int?> sessionId;
  final Value<String> role;
  final Value<String> textContent;
  final Value<String?> suggestedAction;
  final Value<DateTime> timestamp;
  const ChatMessagesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.role = const Value.absent(),
    this.textContent = const Value.absent(),
    this.suggestedAction = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    required String role,
    required String textContent,
    this.suggestedAction = const Value.absent(),
    this.timestamp = const Value.absent(),
  }) : role = Value(role),
       textContent = Value(textContent);
  static Insertable<ChatMessage> custom({
    Expression<int>? id,
    Expression<int>? sessionId,
    Expression<String>? role,
    Expression<String>? textContent,
    Expression<String>? suggestedAction,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (role != null) 'role': role,
      if (textContent != null) 'text_content': textContent,
      if (suggestedAction != null) 'suggested_action': suggestedAction,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<int>? id,
    Value<int?>? sessionId,
    Value<String>? role,
    Value<String>? textContent,
    Value<String?>? suggestedAction,
    Value<DateTime>? timestamp,
  }) {
    return ChatMessagesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      textContent: textContent ?? this.textContent,
      suggestedAction: suggestedAction ?? this.suggestedAction,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (textContent.present) {
      map['text_content'] = Variable<String>(textContent.value);
    }
    if (suggestedAction.present) {
      map['suggested_action'] = Variable<String>(suggestedAction.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('textContent: $textContent, ')
          ..write('suggestedAction: $suggestedAction, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

class $DrillRecordsTable extends DrillRecords
    with TableInfo<$DrillRecordsTable, DrillRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DrillRecordsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
    'topic',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalQuestionsMeta = const VerificationMeta(
    'totalQuestions',
  );
  @override
  late final GeneratedColumn<int> totalQuestions = GeneratedColumn<int>(
    'total_questions',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _correctCountMeta = const VerificationMeta(
    'correctCount',
  );
  @override
  late final GeneratedColumn<int> correctCount = GeneratedColumn<int>(
    'correct_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _incorrectCountMeta = const VerificationMeta(
    'incorrectCount',
  );
  @override
  late final GeneratedColumn<int> incorrectCount = GeneratedColumn<int>(
    'incorrect_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scorePercentageMeta = const VerificationMeta(
    'scorePercentage',
  );
  @override
  late final GeneratedColumn<double> scorePercentage = GeneratedColumn<double>(
    'score_percentage',
    aliasedName,
    false,
    type: DriftSqlType.double,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subject,
    topic,
    totalQuestions,
    correctCount,
    incorrectCount,
    scorePercentage,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drill_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<DrillRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
        _topicMeta,
        topic.isAcceptableOrUnknown(data['topic']!, _topicMeta),
      );
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('total_questions')) {
      context.handle(
        _totalQuestionsMeta,
        totalQuestions.isAcceptableOrUnknown(
          data['total_questions']!,
          _totalQuestionsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalQuestionsMeta);
    }
    if (data.containsKey('correct_count')) {
      context.handle(
        _correctCountMeta,
        correctCount.isAcceptableOrUnknown(
          data['correct_count']!,
          _correctCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_correctCountMeta);
    }
    if (data.containsKey('incorrect_count')) {
      context.handle(
        _incorrectCountMeta,
        incorrectCount.isAcceptableOrUnknown(
          data['incorrect_count']!,
          _incorrectCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_incorrectCountMeta);
    }
    if (data.containsKey('score_percentage')) {
      context.handle(
        _scorePercentageMeta,
        scorePercentage.isAcceptableOrUnknown(
          data['score_percentage']!,
          _scorePercentageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scorePercentageMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DrillRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DrillRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      topic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic'],
      )!,
      totalQuestions: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_questions'],
      )!,
      correctCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}correct_count'],
      )!,
      incorrectCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}incorrect_count'],
      )!,
      scorePercentage: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score_percentage'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DrillRecordsTable createAlias(String alias) {
    return $DrillRecordsTable(attachedDatabase, alias);
  }
}

class DrillRecord extends DataClass implements Insertable<DrillRecord> {
  final int id;
  final String subject;
  final String topic;
  final int totalQuestions;
  final int correctCount;
  final int incorrectCount;
  final double scorePercentage;
  final DateTime createdAt;
  const DrillRecord({
    required this.id,
    required this.subject,
    required this.topic,
    required this.totalQuestions,
    required this.correctCount,
    required this.incorrectCount,
    required this.scorePercentage,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['subject'] = Variable<String>(subject);
    map['topic'] = Variable<String>(topic);
    map['total_questions'] = Variable<int>(totalQuestions);
    map['correct_count'] = Variable<int>(correctCount);
    map['incorrect_count'] = Variable<int>(incorrectCount);
    map['score_percentage'] = Variable<double>(scorePercentage);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DrillRecordsCompanion toCompanion(bool nullToAbsent) {
    return DrillRecordsCompanion(
      id: Value(id),
      subject: Value(subject),
      topic: Value(topic),
      totalQuestions: Value(totalQuestions),
      correctCount: Value(correctCount),
      incorrectCount: Value(incorrectCount),
      scorePercentage: Value(scorePercentage),
      createdAt: Value(createdAt),
    );
  }

  factory DrillRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DrillRecord(
      id: serializer.fromJson<int>(json['id']),
      subject: serializer.fromJson<String>(json['subject']),
      topic: serializer.fromJson<String>(json['topic']),
      totalQuestions: serializer.fromJson<int>(json['totalQuestions']),
      correctCount: serializer.fromJson<int>(json['correctCount']),
      incorrectCount: serializer.fromJson<int>(json['incorrectCount']),
      scorePercentage: serializer.fromJson<double>(json['scorePercentage']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'subject': serializer.toJson<String>(subject),
      'topic': serializer.toJson<String>(topic),
      'totalQuestions': serializer.toJson<int>(totalQuestions),
      'correctCount': serializer.toJson<int>(correctCount),
      'incorrectCount': serializer.toJson<int>(incorrectCount),
      'scorePercentage': serializer.toJson<double>(scorePercentage),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DrillRecord copyWith({
    int? id,
    String? subject,
    String? topic,
    int? totalQuestions,
    int? correctCount,
    int? incorrectCount,
    double? scorePercentage,
    DateTime? createdAt,
  }) => DrillRecord(
    id: id ?? this.id,
    subject: subject ?? this.subject,
    topic: topic ?? this.topic,
    totalQuestions: totalQuestions ?? this.totalQuestions,
    correctCount: correctCount ?? this.correctCount,
    incorrectCount: incorrectCount ?? this.incorrectCount,
    scorePercentage: scorePercentage ?? this.scorePercentage,
    createdAt: createdAt ?? this.createdAt,
  );
  DrillRecord copyWithCompanion(DrillRecordsCompanion data) {
    return DrillRecord(
      id: data.id.present ? data.id.value : this.id,
      subject: data.subject.present ? data.subject.value : this.subject,
      topic: data.topic.present ? data.topic.value : this.topic,
      totalQuestions: data.totalQuestions.present
          ? data.totalQuestions.value
          : this.totalQuestions,
      correctCount: data.correctCount.present
          ? data.correctCount.value
          : this.correctCount,
      incorrectCount: data.incorrectCount.present
          ? data.incorrectCount.value
          : this.incorrectCount,
      scorePercentage: data.scorePercentage.present
          ? data.scorePercentage.value
          : this.scorePercentage,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DrillRecord(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('topic: $topic, ')
          ..write('totalQuestions: $totalQuestions, ')
          ..write('correctCount: $correctCount, ')
          ..write('incorrectCount: $incorrectCount, ')
          ..write('scorePercentage: $scorePercentage, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    subject,
    topic,
    totalQuestions,
    correctCount,
    incorrectCount,
    scorePercentage,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DrillRecord &&
          other.id == this.id &&
          other.subject == this.subject &&
          other.topic == this.topic &&
          other.totalQuestions == this.totalQuestions &&
          other.correctCount == this.correctCount &&
          other.incorrectCount == this.incorrectCount &&
          other.scorePercentage == this.scorePercentage &&
          other.createdAt == this.createdAt);
}

class DrillRecordsCompanion extends UpdateCompanion<DrillRecord> {
  final Value<int> id;
  final Value<String> subject;
  final Value<String> topic;
  final Value<int> totalQuestions;
  final Value<int> correctCount;
  final Value<int> incorrectCount;
  final Value<double> scorePercentage;
  final Value<DateTime> createdAt;
  const DrillRecordsCompanion({
    this.id = const Value.absent(),
    this.subject = const Value.absent(),
    this.topic = const Value.absent(),
    this.totalQuestions = const Value.absent(),
    this.correctCount = const Value.absent(),
    this.incorrectCount = const Value.absent(),
    this.scorePercentage = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  DrillRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String subject,
    required String topic,
    required int totalQuestions,
    required int correctCount,
    required int incorrectCount,
    required double scorePercentage,
    this.createdAt = const Value.absent(),
  }) : subject = Value(subject),
       topic = Value(topic),
       totalQuestions = Value(totalQuestions),
       correctCount = Value(correctCount),
       incorrectCount = Value(incorrectCount),
       scorePercentage = Value(scorePercentage);
  static Insertable<DrillRecord> custom({
    Expression<int>? id,
    Expression<String>? subject,
    Expression<String>? topic,
    Expression<int>? totalQuestions,
    Expression<int>? correctCount,
    Expression<int>? incorrectCount,
    Expression<double>? scorePercentage,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subject != null) 'subject': subject,
      if (topic != null) 'topic': topic,
      if (totalQuestions != null) 'total_questions': totalQuestions,
      if (correctCount != null) 'correct_count': correctCount,
      if (incorrectCount != null) 'incorrect_count': incorrectCount,
      if (scorePercentage != null) 'score_percentage': scorePercentage,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  DrillRecordsCompanion copyWith({
    Value<int>? id,
    Value<String>? subject,
    Value<String>? topic,
    Value<int>? totalQuestions,
    Value<int>? correctCount,
    Value<int>? incorrectCount,
    Value<double>? scorePercentage,
    Value<DateTime>? createdAt,
  }) {
    return DrillRecordsCompanion(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      correctCount: correctCount ?? this.correctCount,
      incorrectCount: incorrectCount ?? this.incorrectCount,
      scorePercentage: scorePercentage ?? this.scorePercentage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (totalQuestions.present) {
      map['total_questions'] = Variable<int>(totalQuestions.value);
    }
    if (correctCount.present) {
      map['correct_count'] = Variable<int>(correctCount.value);
    }
    if (incorrectCount.present) {
      map['incorrect_count'] = Variable<int>(incorrectCount.value);
    }
    if (scorePercentage.present) {
      map['score_percentage'] = Variable<double>(scorePercentage.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DrillRecordsCompanion(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('topic: $topic, ')
          ..write('totalQuestions: $totalQuestions, ')
          ..write('correctCount: $correctCount, ')
          ..write('incorrectCount: $incorrectCount, ')
          ..write('scorePercentage: $scorePercentage, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DrillQuestionsTable extends DrillQuestions
    with TableInfo<$DrillQuestionsTable, DrillQuestion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DrillQuestionsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _drillRecordIdMeta = const VerificationMeta(
    'drillRecordId',
  );
  @override
  late final GeneratedColumn<int> drillRecordId = GeneratedColumn<int>(
    'drill_record_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
    'topic',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _questionTextMeta = const VerificationMeta(
    'questionText',
  );
  @override
  late final GeneratedColumn<String> questionText = GeneratedColumn<String>(
    'question_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _optionsJsonMeta = const VerificationMeta(
    'optionsJson',
  );
  @override
  late final GeneratedColumn<String> optionsJson = GeneratedColumn<String>(
    'options_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _correctIndexMeta = const VerificationMeta(
    'correctIndex',
  );
  @override
  late final GeneratedColumn<int> correctIndex = GeneratedColumn<int>(
    'correct_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _selectedIndexMeta = const VerificationMeta(
    'selectedIndex',
  );
  @override
  late final GeneratedColumn<int> selectedIndex = GeneratedColumn<int>(
    'selected_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isCorrectMeta = const VerificationMeta(
    'isCorrect',
  );
  @override
  late final GeneratedColumn<bool> isCorrect = GeneratedColumn<bool>(
    'is_correct',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_correct" IN (0, 1))',
    ),
  );
  static const VerificationMeta _explanationMeta = const VerificationMeta(
    'explanation',
  );
  @override
  late final GeneratedColumn<String> explanation = GeneratedColumn<String>(
    'explanation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isMasteredMeta = const VerificationMeta(
    'isMastered',
  );
  @override
  late final GeneratedColumn<bool> isMastered = GeneratedColumn<bool>(
    'is_mastered',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_mastered" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _attemptedAtMeta = const VerificationMeta(
    'attemptedAt',
  );
  @override
  late final GeneratedColumn<DateTime> attemptedAt = GeneratedColumn<DateTime>(
    'attempted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _originalCorrectIndexMeta =
      const VerificationMeta('originalCorrectIndex');
  @override
  late final GeneratedColumn<int> originalCorrectIndex = GeneratedColumn<int>(
    'original_correct_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originalExplanationMeta =
      const VerificationMeta('originalExplanation');
  @override
  late final GeneratedColumn<String> originalExplanation =
      GeneratedColumn<String>(
        'original_explanation',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _originalQuestionTextMeta =
      const VerificationMeta('originalQuestionText');
  @override
  late final GeneratedColumn<String> originalQuestionText =
      GeneratedColumn<String>(
        'original_question_text',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _originalOptionsJsonMeta =
      const VerificationMeta('originalOptionsJson');
  @override
  late final GeneratedColumn<String> originalOptionsJson =
      GeneratedColumn<String>(
        'original_options_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _correctedAtMeta = const VerificationMeta(
    'correctedAt',
  );
  @override
  late final GeneratedColumn<DateTime> correctedAt = GeneratedColumn<DateTime>(
    'corrected_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _verificationStatusMeta =
      const VerificationMeta('verificationStatus');
  @override
  late final GeneratedColumn<String> verificationStatus =
      GeneratedColumn<String>(
        'verification_status',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _verificationNoteMeta = const VerificationMeta(
    'verificationNote',
  );
  @override
  late final GeneratedColumn<String> verificationNote = GeneratedColumn<String>(
    'verification_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _verifiedAtMeta = const VerificationMeta(
    'verifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> verifiedAt = GeneratedColumn<DateTime>(
    'verified_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    drillRecordId,
    subject,
    topic,
    questionText,
    optionsJson,
    correctIndex,
    selectedIndex,
    isCorrect,
    explanation,
    isMastered,
    attemptedAt,
    originalCorrectIndex,
    originalExplanation,
    originalQuestionText,
    originalOptionsJson,
    correctedAt,
    verificationStatus,
    verificationNote,
    verifiedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drill_questions';
  @override
  VerificationContext validateIntegrity(
    Insertable<DrillQuestion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('drill_record_id')) {
      context.handle(
        _drillRecordIdMeta,
        drillRecordId.isAcceptableOrUnknown(
          data['drill_record_id']!,
          _drillRecordIdMeta,
        ),
      );
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
        _topicMeta,
        topic.isAcceptableOrUnknown(data['topic']!, _topicMeta),
      );
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('question_text')) {
      context.handle(
        _questionTextMeta,
        questionText.isAcceptableOrUnknown(
          data['question_text']!,
          _questionTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_questionTextMeta);
    }
    if (data.containsKey('options_json')) {
      context.handle(
        _optionsJsonMeta,
        optionsJson.isAcceptableOrUnknown(
          data['options_json']!,
          _optionsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_optionsJsonMeta);
    }
    if (data.containsKey('correct_index')) {
      context.handle(
        _correctIndexMeta,
        correctIndex.isAcceptableOrUnknown(
          data['correct_index']!,
          _correctIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_correctIndexMeta);
    }
    if (data.containsKey('selected_index')) {
      context.handle(
        _selectedIndexMeta,
        selectedIndex.isAcceptableOrUnknown(
          data['selected_index']!,
          _selectedIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_selectedIndexMeta);
    }
    if (data.containsKey('is_correct')) {
      context.handle(
        _isCorrectMeta,
        isCorrect.isAcceptableOrUnknown(data['is_correct']!, _isCorrectMeta),
      );
    } else if (isInserting) {
      context.missing(_isCorrectMeta);
    }
    if (data.containsKey('explanation')) {
      context.handle(
        _explanationMeta,
        explanation.isAcceptableOrUnknown(
          data['explanation']!,
          _explanationMeta,
        ),
      );
    }
    if (data.containsKey('is_mastered')) {
      context.handle(
        _isMasteredMeta,
        isMastered.isAcceptableOrUnknown(data['is_mastered']!, _isMasteredMeta),
      );
    }
    if (data.containsKey('attempted_at')) {
      context.handle(
        _attemptedAtMeta,
        attemptedAt.isAcceptableOrUnknown(
          data['attempted_at']!,
          _attemptedAtMeta,
        ),
      );
    }
    if (data.containsKey('original_correct_index')) {
      context.handle(
        _originalCorrectIndexMeta,
        originalCorrectIndex.isAcceptableOrUnknown(
          data['original_correct_index']!,
          _originalCorrectIndexMeta,
        ),
      );
    }
    if (data.containsKey('original_explanation')) {
      context.handle(
        _originalExplanationMeta,
        originalExplanation.isAcceptableOrUnknown(
          data['original_explanation']!,
          _originalExplanationMeta,
        ),
      );
    }
    if (data.containsKey('original_question_text')) {
      context.handle(
        _originalQuestionTextMeta,
        originalQuestionText.isAcceptableOrUnknown(
          data['original_question_text']!,
          _originalQuestionTextMeta,
        ),
      );
    }
    if (data.containsKey('original_options_json')) {
      context.handle(
        _originalOptionsJsonMeta,
        originalOptionsJson.isAcceptableOrUnknown(
          data['original_options_json']!,
          _originalOptionsJsonMeta,
        ),
      );
    }
    if (data.containsKey('corrected_at')) {
      context.handle(
        _correctedAtMeta,
        correctedAt.isAcceptableOrUnknown(
          data['corrected_at']!,
          _correctedAtMeta,
        ),
      );
    }
    if (data.containsKey('verification_status')) {
      context.handle(
        _verificationStatusMeta,
        verificationStatus.isAcceptableOrUnknown(
          data['verification_status']!,
          _verificationStatusMeta,
        ),
      );
    }
    if (data.containsKey('verification_note')) {
      context.handle(
        _verificationNoteMeta,
        verificationNote.isAcceptableOrUnknown(
          data['verification_note']!,
          _verificationNoteMeta,
        ),
      );
    }
    if (data.containsKey('verified_at')) {
      context.handle(
        _verifiedAtMeta,
        verifiedAt.isAcceptableOrUnknown(data['verified_at']!, _verifiedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DrillQuestion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DrillQuestion(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      drillRecordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}drill_record_id'],
      ),
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      topic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic'],
      )!,
      questionText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_text'],
      )!,
      optionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}options_json'],
      )!,
      correctIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}correct_index'],
      )!,
      selectedIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}selected_index'],
      )!,
      isCorrect: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_correct'],
      )!,
      explanation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}explanation'],
      )!,
      isMastered: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_mastered'],
      )!,
      attemptedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}attempted_at'],
      )!,
      originalCorrectIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}original_correct_index'],
      ),
      originalExplanation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_explanation'],
      ),
      originalQuestionText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_question_text'],
      ),
      originalOptionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_options_json'],
      ),
      correctedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}corrected_at'],
      ),
      verificationStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verification_status'],
      ),
      verificationNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verification_note'],
      ),
      verifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}verified_at'],
      ),
    );
  }

  @override
  $DrillQuestionsTable createAlias(String alias) {
    return $DrillQuestionsTable(attachedDatabase, alias);
  }
}

class DrillQuestion extends DataClass implements Insertable<DrillQuestion> {
  final int id;
  final int? drillRecordId;
  final String subject;
  final String topic;
  final String questionText;
  final String optionsJson;
  final int correctIndex;
  final int selectedIndex;
  final bool isCorrect;
  final String explanation;
  final bool isMastered;
  final DateTime attemptedAt;

  /// What [correctIndex] and [explanation] held before a verification
  /// correction was accepted. Null until one is.
  ///
  /// [selectedIndex] and [isCorrect] are never rewritten: they record what
  /// the user answered and how it was scored at the time, and a later
  /// correction to the question does not change what happened in that
  /// attempt.
  final int? originalCorrectIndex;
  final String? originalExplanation;
  final String? originalQuestionText;
  final String? originalOptionsJson;
  final DateTime? correctedAt;

  /// The last verification's outcome, kept so reopening the sheet shows what
  /// was already found instead of paying for the same check again.
  final String? verificationStatus;
  final String? verificationNote;
  final DateTime? verifiedAt;
  const DrillQuestion({
    required this.id,
    this.drillRecordId,
    required this.subject,
    required this.topic,
    required this.questionText,
    required this.optionsJson,
    required this.correctIndex,
    required this.selectedIndex,
    required this.isCorrect,
    required this.explanation,
    required this.isMastered,
    required this.attemptedAt,
    this.originalCorrectIndex,
    this.originalExplanation,
    this.originalQuestionText,
    this.originalOptionsJson,
    this.correctedAt,
    this.verificationStatus,
    this.verificationNote,
    this.verifiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || drillRecordId != null) {
      map['drill_record_id'] = Variable<int>(drillRecordId);
    }
    map['subject'] = Variable<String>(subject);
    map['topic'] = Variable<String>(topic);
    map['question_text'] = Variable<String>(questionText);
    map['options_json'] = Variable<String>(optionsJson);
    map['correct_index'] = Variable<int>(correctIndex);
    map['selected_index'] = Variable<int>(selectedIndex);
    map['is_correct'] = Variable<bool>(isCorrect);
    map['explanation'] = Variable<String>(explanation);
    map['is_mastered'] = Variable<bool>(isMastered);
    map['attempted_at'] = Variable<DateTime>(attemptedAt);
    if (!nullToAbsent || originalCorrectIndex != null) {
      map['original_correct_index'] = Variable<int>(originalCorrectIndex);
    }
    if (!nullToAbsent || originalExplanation != null) {
      map['original_explanation'] = Variable<String>(originalExplanation);
    }
    if (!nullToAbsent || originalQuestionText != null) {
      map['original_question_text'] = Variable<String>(originalQuestionText);
    }
    if (!nullToAbsent || originalOptionsJson != null) {
      map['original_options_json'] = Variable<String>(originalOptionsJson);
    }
    if (!nullToAbsent || correctedAt != null) {
      map['corrected_at'] = Variable<DateTime>(correctedAt);
    }
    if (!nullToAbsent || verificationStatus != null) {
      map['verification_status'] = Variable<String>(verificationStatus);
    }
    if (!nullToAbsent || verificationNote != null) {
      map['verification_note'] = Variable<String>(verificationNote);
    }
    if (!nullToAbsent || verifiedAt != null) {
      map['verified_at'] = Variable<DateTime>(verifiedAt);
    }
    return map;
  }

  DrillQuestionsCompanion toCompanion(bool nullToAbsent) {
    return DrillQuestionsCompanion(
      id: Value(id),
      drillRecordId: drillRecordId == null && nullToAbsent
          ? const Value.absent()
          : Value(drillRecordId),
      subject: Value(subject),
      topic: Value(topic),
      questionText: Value(questionText),
      optionsJson: Value(optionsJson),
      correctIndex: Value(correctIndex),
      selectedIndex: Value(selectedIndex),
      isCorrect: Value(isCorrect),
      explanation: Value(explanation),
      isMastered: Value(isMastered),
      attemptedAt: Value(attemptedAt),
      originalCorrectIndex: originalCorrectIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(originalCorrectIndex),
      originalExplanation: originalExplanation == null && nullToAbsent
          ? const Value.absent()
          : Value(originalExplanation),
      originalQuestionText: originalQuestionText == null && nullToAbsent
          ? const Value.absent()
          : Value(originalQuestionText),
      originalOptionsJson: originalOptionsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(originalOptionsJson),
      correctedAt: correctedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedAt),
      verificationStatus: verificationStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(verificationStatus),
      verificationNote: verificationNote == null && nullToAbsent
          ? const Value.absent()
          : Value(verificationNote),
      verifiedAt: verifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedAt),
    );
  }

  factory DrillQuestion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DrillQuestion(
      id: serializer.fromJson<int>(json['id']),
      drillRecordId: serializer.fromJson<int?>(json['drillRecordId']),
      subject: serializer.fromJson<String>(json['subject']),
      topic: serializer.fromJson<String>(json['topic']),
      questionText: serializer.fromJson<String>(json['questionText']),
      optionsJson: serializer.fromJson<String>(json['optionsJson']),
      correctIndex: serializer.fromJson<int>(json['correctIndex']),
      selectedIndex: serializer.fromJson<int>(json['selectedIndex']),
      isCorrect: serializer.fromJson<bool>(json['isCorrect']),
      explanation: serializer.fromJson<String>(json['explanation']),
      isMastered: serializer.fromJson<bool>(json['isMastered']),
      attemptedAt: serializer.fromJson<DateTime>(json['attemptedAt']),
      originalCorrectIndex: serializer.fromJson<int?>(
        json['originalCorrectIndex'],
      ),
      originalExplanation: serializer.fromJson<String?>(
        json['originalExplanation'],
      ),
      originalQuestionText: serializer.fromJson<String?>(
        json['originalQuestionText'],
      ),
      originalOptionsJson: serializer.fromJson<String?>(
        json['originalOptionsJson'],
      ),
      correctedAt: serializer.fromJson<DateTime?>(json['correctedAt']),
      verificationStatus: serializer.fromJson<String?>(
        json['verificationStatus'],
      ),
      verificationNote: serializer.fromJson<String?>(json['verificationNote']),
      verifiedAt: serializer.fromJson<DateTime?>(json['verifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'drillRecordId': serializer.toJson<int?>(drillRecordId),
      'subject': serializer.toJson<String>(subject),
      'topic': serializer.toJson<String>(topic),
      'questionText': serializer.toJson<String>(questionText),
      'optionsJson': serializer.toJson<String>(optionsJson),
      'correctIndex': serializer.toJson<int>(correctIndex),
      'selectedIndex': serializer.toJson<int>(selectedIndex),
      'isCorrect': serializer.toJson<bool>(isCorrect),
      'explanation': serializer.toJson<String>(explanation),
      'isMastered': serializer.toJson<bool>(isMastered),
      'attemptedAt': serializer.toJson<DateTime>(attemptedAt),
      'originalCorrectIndex': serializer.toJson<int?>(originalCorrectIndex),
      'originalExplanation': serializer.toJson<String?>(originalExplanation),
      'originalQuestionText': serializer.toJson<String?>(originalQuestionText),
      'originalOptionsJson': serializer.toJson<String?>(originalOptionsJson),
      'correctedAt': serializer.toJson<DateTime?>(correctedAt),
      'verificationStatus': serializer.toJson<String?>(verificationStatus),
      'verificationNote': serializer.toJson<String?>(verificationNote),
      'verifiedAt': serializer.toJson<DateTime?>(verifiedAt),
    };
  }

  DrillQuestion copyWith({
    int? id,
    Value<int?> drillRecordId = const Value.absent(),
    String? subject,
    String? topic,
    String? questionText,
    String? optionsJson,
    int? correctIndex,
    int? selectedIndex,
    bool? isCorrect,
    String? explanation,
    bool? isMastered,
    DateTime? attemptedAt,
    Value<int?> originalCorrectIndex = const Value.absent(),
    Value<String?> originalExplanation = const Value.absent(),
    Value<String?> originalQuestionText = const Value.absent(),
    Value<String?> originalOptionsJson = const Value.absent(),
    Value<DateTime?> correctedAt = const Value.absent(),
    Value<String?> verificationStatus = const Value.absent(),
    Value<String?> verificationNote = const Value.absent(),
    Value<DateTime?> verifiedAt = const Value.absent(),
  }) => DrillQuestion(
    id: id ?? this.id,
    drillRecordId: drillRecordId.present
        ? drillRecordId.value
        : this.drillRecordId,
    subject: subject ?? this.subject,
    topic: topic ?? this.topic,
    questionText: questionText ?? this.questionText,
    optionsJson: optionsJson ?? this.optionsJson,
    correctIndex: correctIndex ?? this.correctIndex,
    selectedIndex: selectedIndex ?? this.selectedIndex,
    isCorrect: isCorrect ?? this.isCorrect,
    explanation: explanation ?? this.explanation,
    isMastered: isMastered ?? this.isMastered,
    attemptedAt: attemptedAt ?? this.attemptedAt,
    originalCorrectIndex: originalCorrectIndex.present
        ? originalCorrectIndex.value
        : this.originalCorrectIndex,
    originalExplanation: originalExplanation.present
        ? originalExplanation.value
        : this.originalExplanation,
    originalQuestionText: originalQuestionText.present
        ? originalQuestionText.value
        : this.originalQuestionText,
    originalOptionsJson: originalOptionsJson.present
        ? originalOptionsJson.value
        : this.originalOptionsJson,
    correctedAt: correctedAt.present ? correctedAt.value : this.correctedAt,
    verificationStatus: verificationStatus.present
        ? verificationStatus.value
        : this.verificationStatus,
    verificationNote: verificationNote.present
        ? verificationNote.value
        : this.verificationNote,
    verifiedAt: verifiedAt.present ? verifiedAt.value : this.verifiedAt,
  );
  DrillQuestion copyWithCompanion(DrillQuestionsCompanion data) {
    return DrillQuestion(
      id: data.id.present ? data.id.value : this.id,
      drillRecordId: data.drillRecordId.present
          ? data.drillRecordId.value
          : this.drillRecordId,
      subject: data.subject.present ? data.subject.value : this.subject,
      topic: data.topic.present ? data.topic.value : this.topic,
      questionText: data.questionText.present
          ? data.questionText.value
          : this.questionText,
      optionsJson: data.optionsJson.present
          ? data.optionsJson.value
          : this.optionsJson,
      correctIndex: data.correctIndex.present
          ? data.correctIndex.value
          : this.correctIndex,
      selectedIndex: data.selectedIndex.present
          ? data.selectedIndex.value
          : this.selectedIndex,
      isCorrect: data.isCorrect.present ? data.isCorrect.value : this.isCorrect,
      explanation: data.explanation.present
          ? data.explanation.value
          : this.explanation,
      isMastered: data.isMastered.present
          ? data.isMastered.value
          : this.isMastered,
      attemptedAt: data.attemptedAt.present
          ? data.attemptedAt.value
          : this.attemptedAt,
      originalCorrectIndex: data.originalCorrectIndex.present
          ? data.originalCorrectIndex.value
          : this.originalCorrectIndex,
      originalExplanation: data.originalExplanation.present
          ? data.originalExplanation.value
          : this.originalExplanation,
      originalQuestionText: data.originalQuestionText.present
          ? data.originalQuestionText.value
          : this.originalQuestionText,
      originalOptionsJson: data.originalOptionsJson.present
          ? data.originalOptionsJson.value
          : this.originalOptionsJson,
      correctedAt: data.correctedAt.present
          ? data.correctedAt.value
          : this.correctedAt,
      verificationStatus: data.verificationStatus.present
          ? data.verificationStatus.value
          : this.verificationStatus,
      verificationNote: data.verificationNote.present
          ? data.verificationNote.value
          : this.verificationNote,
      verifiedAt: data.verifiedAt.present
          ? data.verifiedAt.value
          : this.verifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DrillQuestion(')
          ..write('id: $id, ')
          ..write('drillRecordId: $drillRecordId, ')
          ..write('subject: $subject, ')
          ..write('topic: $topic, ')
          ..write('questionText: $questionText, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('correctIndex: $correctIndex, ')
          ..write('selectedIndex: $selectedIndex, ')
          ..write('isCorrect: $isCorrect, ')
          ..write('explanation: $explanation, ')
          ..write('isMastered: $isMastered, ')
          ..write('attemptedAt: $attemptedAt, ')
          ..write('originalCorrectIndex: $originalCorrectIndex, ')
          ..write('originalExplanation: $originalExplanation, ')
          ..write('originalQuestionText: $originalQuestionText, ')
          ..write('originalOptionsJson: $originalOptionsJson, ')
          ..write('correctedAt: $correctedAt, ')
          ..write('verificationStatus: $verificationStatus, ')
          ..write('verificationNote: $verificationNote, ')
          ..write('verifiedAt: $verifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    drillRecordId,
    subject,
    topic,
    questionText,
    optionsJson,
    correctIndex,
    selectedIndex,
    isCorrect,
    explanation,
    isMastered,
    attemptedAt,
    originalCorrectIndex,
    originalExplanation,
    originalQuestionText,
    originalOptionsJson,
    correctedAt,
    verificationStatus,
    verificationNote,
    verifiedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DrillQuestion &&
          other.id == this.id &&
          other.drillRecordId == this.drillRecordId &&
          other.subject == this.subject &&
          other.topic == this.topic &&
          other.questionText == this.questionText &&
          other.optionsJson == this.optionsJson &&
          other.correctIndex == this.correctIndex &&
          other.selectedIndex == this.selectedIndex &&
          other.isCorrect == this.isCorrect &&
          other.explanation == this.explanation &&
          other.isMastered == this.isMastered &&
          other.attemptedAt == this.attemptedAt &&
          other.originalCorrectIndex == this.originalCorrectIndex &&
          other.originalExplanation == this.originalExplanation &&
          other.originalQuestionText == this.originalQuestionText &&
          other.originalOptionsJson == this.originalOptionsJson &&
          other.correctedAt == this.correctedAt &&
          other.verificationStatus == this.verificationStatus &&
          other.verificationNote == this.verificationNote &&
          other.verifiedAt == this.verifiedAt);
}

class DrillQuestionsCompanion extends UpdateCompanion<DrillQuestion> {
  final Value<int> id;
  final Value<int?> drillRecordId;
  final Value<String> subject;
  final Value<String> topic;
  final Value<String> questionText;
  final Value<String> optionsJson;
  final Value<int> correctIndex;
  final Value<int> selectedIndex;
  final Value<bool> isCorrect;
  final Value<String> explanation;
  final Value<bool> isMastered;
  final Value<DateTime> attemptedAt;
  final Value<int?> originalCorrectIndex;
  final Value<String?> originalExplanation;
  final Value<String?> originalQuestionText;
  final Value<String?> originalOptionsJson;
  final Value<DateTime?> correctedAt;
  final Value<String?> verificationStatus;
  final Value<String?> verificationNote;
  final Value<DateTime?> verifiedAt;
  const DrillQuestionsCompanion({
    this.id = const Value.absent(),
    this.drillRecordId = const Value.absent(),
    this.subject = const Value.absent(),
    this.topic = const Value.absent(),
    this.questionText = const Value.absent(),
    this.optionsJson = const Value.absent(),
    this.correctIndex = const Value.absent(),
    this.selectedIndex = const Value.absent(),
    this.isCorrect = const Value.absent(),
    this.explanation = const Value.absent(),
    this.isMastered = const Value.absent(),
    this.attemptedAt = const Value.absent(),
    this.originalCorrectIndex = const Value.absent(),
    this.originalExplanation = const Value.absent(),
    this.originalQuestionText = const Value.absent(),
    this.originalOptionsJson = const Value.absent(),
    this.correctedAt = const Value.absent(),
    this.verificationStatus = const Value.absent(),
    this.verificationNote = const Value.absent(),
    this.verifiedAt = const Value.absent(),
  });
  DrillQuestionsCompanion.insert({
    this.id = const Value.absent(),
    this.drillRecordId = const Value.absent(),
    required String subject,
    required String topic,
    required String questionText,
    required String optionsJson,
    required int correctIndex,
    required int selectedIndex,
    required bool isCorrect,
    this.explanation = const Value.absent(),
    this.isMastered = const Value.absent(),
    this.attemptedAt = const Value.absent(),
    this.originalCorrectIndex = const Value.absent(),
    this.originalExplanation = const Value.absent(),
    this.originalQuestionText = const Value.absent(),
    this.originalOptionsJson = const Value.absent(),
    this.correctedAt = const Value.absent(),
    this.verificationStatus = const Value.absent(),
    this.verificationNote = const Value.absent(),
    this.verifiedAt = const Value.absent(),
  }) : subject = Value(subject),
       topic = Value(topic),
       questionText = Value(questionText),
       optionsJson = Value(optionsJson),
       correctIndex = Value(correctIndex),
       selectedIndex = Value(selectedIndex),
       isCorrect = Value(isCorrect);
  static Insertable<DrillQuestion> custom({
    Expression<int>? id,
    Expression<int>? drillRecordId,
    Expression<String>? subject,
    Expression<String>? topic,
    Expression<String>? questionText,
    Expression<String>? optionsJson,
    Expression<int>? correctIndex,
    Expression<int>? selectedIndex,
    Expression<bool>? isCorrect,
    Expression<String>? explanation,
    Expression<bool>? isMastered,
    Expression<DateTime>? attemptedAt,
    Expression<int>? originalCorrectIndex,
    Expression<String>? originalExplanation,
    Expression<String>? originalQuestionText,
    Expression<String>? originalOptionsJson,
    Expression<DateTime>? correctedAt,
    Expression<String>? verificationStatus,
    Expression<String>? verificationNote,
    Expression<DateTime>? verifiedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (drillRecordId != null) 'drill_record_id': drillRecordId,
      if (subject != null) 'subject': subject,
      if (topic != null) 'topic': topic,
      if (questionText != null) 'question_text': questionText,
      if (optionsJson != null) 'options_json': optionsJson,
      if (correctIndex != null) 'correct_index': correctIndex,
      if (selectedIndex != null) 'selected_index': selectedIndex,
      if (isCorrect != null) 'is_correct': isCorrect,
      if (explanation != null) 'explanation': explanation,
      if (isMastered != null) 'is_mastered': isMastered,
      if (attemptedAt != null) 'attempted_at': attemptedAt,
      if (originalCorrectIndex != null)
        'original_correct_index': originalCorrectIndex,
      if (originalExplanation != null)
        'original_explanation': originalExplanation,
      if (originalQuestionText != null)
        'original_question_text': originalQuestionText,
      if (originalOptionsJson != null)
        'original_options_json': originalOptionsJson,
      if (correctedAt != null) 'corrected_at': correctedAt,
      if (verificationStatus != null) 'verification_status': verificationStatus,
      if (verificationNote != null) 'verification_note': verificationNote,
      if (verifiedAt != null) 'verified_at': verifiedAt,
    });
  }

  DrillQuestionsCompanion copyWith({
    Value<int>? id,
    Value<int?>? drillRecordId,
    Value<String>? subject,
    Value<String>? topic,
    Value<String>? questionText,
    Value<String>? optionsJson,
    Value<int>? correctIndex,
    Value<int>? selectedIndex,
    Value<bool>? isCorrect,
    Value<String>? explanation,
    Value<bool>? isMastered,
    Value<DateTime>? attemptedAt,
    Value<int?>? originalCorrectIndex,
    Value<String?>? originalExplanation,
    Value<String?>? originalQuestionText,
    Value<String?>? originalOptionsJson,
    Value<DateTime?>? correctedAt,
    Value<String?>? verificationStatus,
    Value<String?>? verificationNote,
    Value<DateTime?>? verifiedAt,
  }) {
    return DrillQuestionsCompanion(
      id: id ?? this.id,
      drillRecordId: drillRecordId ?? this.drillRecordId,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      questionText: questionText ?? this.questionText,
      optionsJson: optionsJson ?? this.optionsJson,
      correctIndex: correctIndex ?? this.correctIndex,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      isCorrect: isCorrect ?? this.isCorrect,
      explanation: explanation ?? this.explanation,
      isMastered: isMastered ?? this.isMastered,
      attemptedAt: attemptedAt ?? this.attemptedAt,
      originalCorrectIndex: originalCorrectIndex ?? this.originalCorrectIndex,
      originalExplanation: originalExplanation ?? this.originalExplanation,
      originalQuestionText: originalQuestionText ?? this.originalQuestionText,
      originalOptionsJson: originalOptionsJson ?? this.originalOptionsJson,
      correctedAt: correctedAt ?? this.correctedAt,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      verificationNote: verificationNote ?? this.verificationNote,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (drillRecordId.present) {
      map['drill_record_id'] = Variable<int>(drillRecordId.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (questionText.present) {
      map['question_text'] = Variable<String>(questionText.value);
    }
    if (optionsJson.present) {
      map['options_json'] = Variable<String>(optionsJson.value);
    }
    if (correctIndex.present) {
      map['correct_index'] = Variable<int>(correctIndex.value);
    }
    if (selectedIndex.present) {
      map['selected_index'] = Variable<int>(selectedIndex.value);
    }
    if (isCorrect.present) {
      map['is_correct'] = Variable<bool>(isCorrect.value);
    }
    if (explanation.present) {
      map['explanation'] = Variable<String>(explanation.value);
    }
    if (isMastered.present) {
      map['is_mastered'] = Variable<bool>(isMastered.value);
    }
    if (attemptedAt.present) {
      map['attempted_at'] = Variable<DateTime>(attemptedAt.value);
    }
    if (originalCorrectIndex.present) {
      map['original_correct_index'] = Variable<int>(originalCorrectIndex.value);
    }
    if (originalExplanation.present) {
      map['original_explanation'] = Variable<String>(originalExplanation.value);
    }
    if (originalQuestionText.present) {
      map['original_question_text'] = Variable<String>(
        originalQuestionText.value,
      );
    }
    if (originalOptionsJson.present) {
      map['original_options_json'] = Variable<String>(
        originalOptionsJson.value,
      );
    }
    if (correctedAt.present) {
      map['corrected_at'] = Variable<DateTime>(correctedAt.value);
    }
    if (verificationStatus.present) {
      map['verification_status'] = Variable<String>(verificationStatus.value);
    }
    if (verificationNote.present) {
      map['verification_note'] = Variable<String>(verificationNote.value);
    }
    if (verifiedAt.present) {
      map['verified_at'] = Variable<DateTime>(verifiedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DrillQuestionsCompanion(')
          ..write('id: $id, ')
          ..write('drillRecordId: $drillRecordId, ')
          ..write('subject: $subject, ')
          ..write('topic: $topic, ')
          ..write('questionText: $questionText, ')
          ..write('optionsJson: $optionsJson, ')
          ..write('correctIndex: $correctIndex, ')
          ..write('selectedIndex: $selectedIndex, ')
          ..write('isCorrect: $isCorrect, ')
          ..write('explanation: $explanation, ')
          ..write('isMastered: $isMastered, ')
          ..write('attemptedAt: $attemptedAt, ')
          ..write('originalCorrectIndex: $originalCorrectIndex, ')
          ..write('originalExplanation: $originalExplanation, ')
          ..write('originalQuestionText: $originalQuestionText, ')
          ..write('originalOptionsJson: $originalOptionsJson, ')
          ..write('correctedAt: $correctedAt, ')
          ..write('verificationStatus: $verificationStatus, ')
          ..write('verificationNote: $verificationNote, ')
          ..write('verifiedAt: $verifiedAt')
          ..write(')'))
        .toString();
  }
}

class $SpacedReviewItemsTable extends SpacedReviewItems
    with TableInfo<$SpacedReviewItemsTable, SpacedReviewItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpacedReviewItemsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
    'topic',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 250,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyRuleMeta = const VerificationMeta(
    'keyRule',
  );
  @override
  late final GeneratedColumn<String> keyRule = GeneratedColumn<String>(
    'key_rule',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repetitionLevelMeta = const VerificationMeta(
    'repetitionLevel',
  );
  @override
  late final GeneratedColumn<int> repetitionLevel = GeneratedColumn<int>(
    'repetition_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _intervalDaysMeta = const VerificationMeta(
    'intervalDays',
  );
  @override
  late final GeneratedColumn<int> intervalDays = GeneratedColumn<int>(
    'interval_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _nextReviewDateMeta = const VerificationMeta(
    'nextReviewDate',
  );
  @override
  late final GeneratedColumn<DateTime> nextReviewDate =
      GeneratedColumn<DateTime>(
        'next_review_date',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _lastReviewedAtMeta = const VerificationMeta(
    'lastReviewedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastReviewedAt =
      GeneratedColumn<DateTime>(
        'last_reviewed_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isMasteredMeta = const VerificationMeta(
    'isMastered',
  );
  @override
  late final GeneratedColumn<bool> isMastered = GeneratedColumn<bool>(
    'is_mastered',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_mastered" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subject,
    topic,
    title,
    keyRule,
    repetitionLevel,
    intervalDays,
    nextReviewDate,
    lastReviewedAt,
    isMastered,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'spaced_review_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<SpacedReviewItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
        _topicMeta,
        topic.isAcceptableOrUnknown(data['topic']!, _topicMeta),
      );
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('key_rule')) {
      context.handle(
        _keyRuleMeta,
        keyRule.isAcceptableOrUnknown(data['key_rule']!, _keyRuleMeta),
      );
    } else if (isInserting) {
      context.missing(_keyRuleMeta);
    }
    if (data.containsKey('repetition_level')) {
      context.handle(
        _repetitionLevelMeta,
        repetitionLevel.isAcceptableOrUnknown(
          data['repetition_level']!,
          _repetitionLevelMeta,
        ),
      );
    }
    if (data.containsKey('interval_days')) {
      context.handle(
        _intervalDaysMeta,
        intervalDays.isAcceptableOrUnknown(
          data['interval_days']!,
          _intervalDaysMeta,
        ),
      );
    }
    if (data.containsKey('next_review_date')) {
      context.handle(
        _nextReviewDateMeta,
        nextReviewDate.isAcceptableOrUnknown(
          data['next_review_date']!,
          _nextReviewDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextReviewDateMeta);
    }
    if (data.containsKey('last_reviewed_at')) {
      context.handle(
        _lastReviewedAtMeta,
        lastReviewedAt.isAcceptableOrUnknown(
          data['last_reviewed_at']!,
          _lastReviewedAtMeta,
        ),
      );
    }
    if (data.containsKey('is_mastered')) {
      context.handle(
        _isMasteredMeta,
        isMastered.isAcceptableOrUnknown(data['is_mastered']!, _isMasteredMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SpacedReviewItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SpacedReviewItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      topic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      keyRule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_rule'],
      )!,
      repetitionLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repetition_level'],
      )!,
      intervalDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interval_days'],
      )!,
      nextReviewDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_review_date'],
      )!,
      lastReviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_reviewed_at'],
      ),
      isMastered: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_mastered'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SpacedReviewItemsTable createAlias(String alias) {
    return $SpacedReviewItemsTable(attachedDatabase, alias);
  }
}

class SpacedReviewItem extends DataClass
    implements Insertable<SpacedReviewItem> {
  final int id;
  final String subject;
  final String topic;
  final String title;
  final String keyRule;
  final int repetitionLevel;
  final int intervalDays;
  final DateTime nextReviewDate;
  final DateTime? lastReviewedAt;
  final bool isMastered;
  final DateTime createdAt;
  const SpacedReviewItem({
    required this.id,
    required this.subject,
    required this.topic,
    required this.title,
    required this.keyRule,
    required this.repetitionLevel,
    required this.intervalDays,
    required this.nextReviewDate,
    this.lastReviewedAt,
    required this.isMastered,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['subject'] = Variable<String>(subject);
    map['topic'] = Variable<String>(topic);
    map['title'] = Variable<String>(title);
    map['key_rule'] = Variable<String>(keyRule);
    map['repetition_level'] = Variable<int>(repetitionLevel);
    map['interval_days'] = Variable<int>(intervalDays);
    map['next_review_date'] = Variable<DateTime>(nextReviewDate);
    if (!nullToAbsent || lastReviewedAt != null) {
      map['last_reviewed_at'] = Variable<DateTime>(lastReviewedAt);
    }
    map['is_mastered'] = Variable<bool>(isMastered);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SpacedReviewItemsCompanion toCompanion(bool nullToAbsent) {
    return SpacedReviewItemsCompanion(
      id: Value(id),
      subject: Value(subject),
      topic: Value(topic),
      title: Value(title),
      keyRule: Value(keyRule),
      repetitionLevel: Value(repetitionLevel),
      intervalDays: Value(intervalDays),
      nextReviewDate: Value(nextReviewDate),
      lastReviewedAt: lastReviewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReviewedAt),
      isMastered: Value(isMastered),
      createdAt: Value(createdAt),
    );
  }

  factory SpacedReviewItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SpacedReviewItem(
      id: serializer.fromJson<int>(json['id']),
      subject: serializer.fromJson<String>(json['subject']),
      topic: serializer.fromJson<String>(json['topic']),
      title: serializer.fromJson<String>(json['title']),
      keyRule: serializer.fromJson<String>(json['keyRule']),
      repetitionLevel: serializer.fromJson<int>(json['repetitionLevel']),
      intervalDays: serializer.fromJson<int>(json['intervalDays']),
      nextReviewDate: serializer.fromJson<DateTime>(json['nextReviewDate']),
      lastReviewedAt: serializer.fromJson<DateTime?>(json['lastReviewedAt']),
      isMastered: serializer.fromJson<bool>(json['isMastered']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'subject': serializer.toJson<String>(subject),
      'topic': serializer.toJson<String>(topic),
      'title': serializer.toJson<String>(title),
      'keyRule': serializer.toJson<String>(keyRule),
      'repetitionLevel': serializer.toJson<int>(repetitionLevel),
      'intervalDays': serializer.toJson<int>(intervalDays),
      'nextReviewDate': serializer.toJson<DateTime>(nextReviewDate),
      'lastReviewedAt': serializer.toJson<DateTime?>(lastReviewedAt),
      'isMastered': serializer.toJson<bool>(isMastered),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SpacedReviewItem copyWith({
    int? id,
    String? subject,
    String? topic,
    String? title,
    String? keyRule,
    int? repetitionLevel,
    int? intervalDays,
    DateTime? nextReviewDate,
    Value<DateTime?> lastReviewedAt = const Value.absent(),
    bool? isMastered,
    DateTime? createdAt,
  }) => SpacedReviewItem(
    id: id ?? this.id,
    subject: subject ?? this.subject,
    topic: topic ?? this.topic,
    title: title ?? this.title,
    keyRule: keyRule ?? this.keyRule,
    repetitionLevel: repetitionLevel ?? this.repetitionLevel,
    intervalDays: intervalDays ?? this.intervalDays,
    nextReviewDate: nextReviewDate ?? this.nextReviewDate,
    lastReviewedAt: lastReviewedAt.present
        ? lastReviewedAt.value
        : this.lastReviewedAt,
    isMastered: isMastered ?? this.isMastered,
    createdAt: createdAt ?? this.createdAt,
  );
  SpacedReviewItem copyWithCompanion(SpacedReviewItemsCompanion data) {
    return SpacedReviewItem(
      id: data.id.present ? data.id.value : this.id,
      subject: data.subject.present ? data.subject.value : this.subject,
      topic: data.topic.present ? data.topic.value : this.topic,
      title: data.title.present ? data.title.value : this.title,
      keyRule: data.keyRule.present ? data.keyRule.value : this.keyRule,
      repetitionLevel: data.repetitionLevel.present
          ? data.repetitionLevel.value
          : this.repetitionLevel,
      intervalDays: data.intervalDays.present
          ? data.intervalDays.value
          : this.intervalDays,
      nextReviewDate: data.nextReviewDate.present
          ? data.nextReviewDate.value
          : this.nextReviewDate,
      lastReviewedAt: data.lastReviewedAt.present
          ? data.lastReviewedAt.value
          : this.lastReviewedAt,
      isMastered: data.isMastered.present
          ? data.isMastered.value
          : this.isMastered,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SpacedReviewItem(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('topic: $topic, ')
          ..write('title: $title, ')
          ..write('keyRule: $keyRule, ')
          ..write('repetitionLevel: $repetitionLevel, ')
          ..write('intervalDays: $intervalDays, ')
          ..write('nextReviewDate: $nextReviewDate, ')
          ..write('lastReviewedAt: $lastReviewedAt, ')
          ..write('isMastered: $isMastered, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    subject,
    topic,
    title,
    keyRule,
    repetitionLevel,
    intervalDays,
    nextReviewDate,
    lastReviewedAt,
    isMastered,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpacedReviewItem &&
          other.id == this.id &&
          other.subject == this.subject &&
          other.topic == this.topic &&
          other.title == this.title &&
          other.keyRule == this.keyRule &&
          other.repetitionLevel == this.repetitionLevel &&
          other.intervalDays == this.intervalDays &&
          other.nextReviewDate == this.nextReviewDate &&
          other.lastReviewedAt == this.lastReviewedAt &&
          other.isMastered == this.isMastered &&
          other.createdAt == this.createdAt);
}

class SpacedReviewItemsCompanion extends UpdateCompanion<SpacedReviewItem> {
  final Value<int> id;
  final Value<String> subject;
  final Value<String> topic;
  final Value<String> title;
  final Value<String> keyRule;
  final Value<int> repetitionLevel;
  final Value<int> intervalDays;
  final Value<DateTime> nextReviewDate;
  final Value<DateTime?> lastReviewedAt;
  final Value<bool> isMastered;
  final Value<DateTime> createdAt;
  const SpacedReviewItemsCompanion({
    this.id = const Value.absent(),
    this.subject = const Value.absent(),
    this.topic = const Value.absent(),
    this.title = const Value.absent(),
    this.keyRule = const Value.absent(),
    this.repetitionLevel = const Value.absent(),
    this.intervalDays = const Value.absent(),
    this.nextReviewDate = const Value.absent(),
    this.lastReviewedAt = const Value.absent(),
    this.isMastered = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SpacedReviewItemsCompanion.insert({
    this.id = const Value.absent(),
    required String subject,
    required String topic,
    required String title,
    required String keyRule,
    this.repetitionLevel = const Value.absent(),
    this.intervalDays = const Value.absent(),
    required DateTime nextReviewDate,
    this.lastReviewedAt = const Value.absent(),
    this.isMastered = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : subject = Value(subject),
       topic = Value(topic),
       title = Value(title),
       keyRule = Value(keyRule),
       nextReviewDate = Value(nextReviewDate);
  static Insertable<SpacedReviewItem> custom({
    Expression<int>? id,
    Expression<String>? subject,
    Expression<String>? topic,
    Expression<String>? title,
    Expression<String>? keyRule,
    Expression<int>? repetitionLevel,
    Expression<int>? intervalDays,
    Expression<DateTime>? nextReviewDate,
    Expression<DateTime>? lastReviewedAt,
    Expression<bool>? isMastered,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subject != null) 'subject': subject,
      if (topic != null) 'topic': topic,
      if (title != null) 'title': title,
      if (keyRule != null) 'key_rule': keyRule,
      if (repetitionLevel != null) 'repetition_level': repetitionLevel,
      if (intervalDays != null) 'interval_days': intervalDays,
      if (nextReviewDate != null) 'next_review_date': nextReviewDate,
      if (lastReviewedAt != null) 'last_reviewed_at': lastReviewedAt,
      if (isMastered != null) 'is_mastered': isMastered,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SpacedReviewItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? subject,
    Value<String>? topic,
    Value<String>? title,
    Value<String>? keyRule,
    Value<int>? repetitionLevel,
    Value<int>? intervalDays,
    Value<DateTime>? nextReviewDate,
    Value<DateTime?>? lastReviewedAt,
    Value<bool>? isMastered,
    Value<DateTime>? createdAt,
  }) {
    return SpacedReviewItemsCompanion(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      title: title ?? this.title,
      keyRule: keyRule ?? this.keyRule,
      repetitionLevel: repetitionLevel ?? this.repetitionLevel,
      intervalDays: intervalDays ?? this.intervalDays,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      isMastered: isMastered ?? this.isMastered,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (keyRule.present) {
      map['key_rule'] = Variable<String>(keyRule.value);
    }
    if (repetitionLevel.present) {
      map['repetition_level'] = Variable<int>(repetitionLevel.value);
    }
    if (intervalDays.present) {
      map['interval_days'] = Variable<int>(intervalDays.value);
    }
    if (nextReviewDate.present) {
      map['next_review_date'] = Variable<DateTime>(nextReviewDate.value);
    }
    if (lastReviewedAt.present) {
      map['last_reviewed_at'] = Variable<DateTime>(lastReviewedAt.value);
    }
    if (isMastered.present) {
      map['is_mastered'] = Variable<bool>(isMastered.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpacedReviewItemsCompanion(')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('topic: $topic, ')
          ..write('title: $title, ')
          ..write('keyRule: $keyRule, ')
          ..write('repetitionLevel: $repetitionLevel, ')
          ..write('intervalDays: $intervalDays, ')
          ..write('nextReviewDate: $nextReviewDate, ')
          ..write('lastReviewedAt: $lastReviewedAt, ')
          ..write('isMastered: $isMastered, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WeakTopicsTable weakTopics = $WeakTopicsTable(this);
  late final $ExamSchedulesTable examSchedules = $ExamSchedulesTable(this);
  late final $DailyEnergyLogsTable dailyEnergyLogs = $DailyEnergyLogsTable(
    this,
  );
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $ChatSessionsTable chatSessions = $ChatSessionsTable(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $DrillRecordsTable drillRecords = $DrillRecordsTable(this);
  late final $DrillQuestionsTable drillQuestions = $DrillQuestionsTable(this);
  late final $SpacedReviewItemsTable spacedReviewItems =
      $SpacedReviewItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    weakTopics,
    examSchedules,
    dailyEnergyLogs,
    appSettings,
    chatSessions,
    chatMessages,
    drillRecords,
    drillQuestions,
    spacedReviewItems,
  ];
}

typedef $$WeakTopicsTableCreateCompanionBuilder = WeakTopicsCompanion Function({
  Value<int> id,
  required String subject,
  required String topicName,
  required ProficiencyLevel proficiencyLevel,
  Value<DateTime?> lastReviewedAt,
  Value<String?> notes,
  Value<DateTime> createdAt,
});
typedef $$WeakTopicsTableUpdateCompanionBuilder = WeakTopicsCompanion Function({
  Value<int> id,
  Value<String> subject,
  Value<String> topicName,
  Value<ProficiencyLevel> proficiencyLevel,
  Value<DateTime?> lastReviewedAt,
  Value<String?> notes,
  Value<DateTime> createdAt,
});

class $$WeakTopicsTableFilterComposer
    extends Composer<_$AppDatabase, $WeakTopicsTable> {
  $$WeakTopicsTableFilterComposer({
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

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topicName => $composableBuilder(
    column: $table.topicName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ProficiencyLevel, ProficiencyLevel, String>
  get proficiencyLevel => $composableBuilder(
    column: $table.proficiencyLevel,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get lastReviewedAt => $composableBuilder(
    column: $table.lastReviewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WeakTopicsTableOrderingComposer
    extends Composer<_$AppDatabase, $WeakTopicsTable> {
  $$WeakTopicsTableOrderingComposer({
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

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topicName => $composableBuilder(
    column: $table.topicName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proficiencyLevel => $composableBuilder(
    column: $table.proficiencyLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastReviewedAt => $composableBuilder(
    column: $table.lastReviewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WeakTopicsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WeakTopicsTable> {
  $$WeakTopicsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get topicName =>
      $composableBuilder(column: $table.topicName, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ProficiencyLevel, String>
  get proficiencyLevel => $composableBuilder(
    column: $table.proficiencyLevel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastReviewedAt => $composableBuilder(
    column: $table.lastReviewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$WeakTopicsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WeakTopicsTable,
          WeakTopic,
          $$WeakTopicsTableFilterComposer,
          $$WeakTopicsTableOrderingComposer,
          $$WeakTopicsTableAnnotationComposer,
          $$WeakTopicsTableCreateCompanionBuilder,
          $$WeakTopicsTableUpdateCompanionBuilder,
          (
            WeakTopic,
            BaseReferences<_$AppDatabase, $WeakTopicsTable, WeakTopic>,
          ),
          WeakTopic,
          PrefetchHooks Function()
        > {
  $$WeakTopicsTableTableManager(_$AppDatabase db, $WeakTopicsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WeakTopicsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WeakTopicsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WeakTopicsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> topicName = const Value.absent(),
                Value<ProficiencyLevel> proficiencyLevel = const Value.absent(),
                Value<DateTime?> lastReviewedAt = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => WeakTopicsCompanion(
                id: id,
                subject: subject,
                topicName: topicName,
                proficiencyLevel: proficiencyLevel,
                lastReviewedAt: lastReviewedAt,
                notes: notes,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String subject,
                required String topicName,
                required ProficiencyLevel proficiencyLevel,
                Value<DateTime?> lastReviewedAt = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => WeakTopicsCompanion.insert(
                id: id,
                subject: subject,
                topicName: topicName,
                proficiencyLevel: proficiencyLevel,
                lastReviewedAt: lastReviewedAt,
                notes: notes,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WeakTopicsTable, WeakTopic>(table),
                  BaseReferences<_$AppDatabase, $WeakTopicsTable, WeakTopic>(
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

typedef $$WeakTopicsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WeakTopicsTable,
      WeakTopic,
      $$WeakTopicsTableFilterComposer,
      $$WeakTopicsTableOrderingComposer,
      $$WeakTopicsTableAnnotationComposer,
      $$WeakTopicsTableCreateCompanionBuilder,
      $$WeakTopicsTableUpdateCompanionBuilder,
      (WeakTopic, BaseReferences<_$AppDatabase, $WeakTopicsTable, WeakTopic>),
      WeakTopic,
      PrefetchHooks Function()
    >;
typedef $$ExamSchedulesTableCreateCompanionBuilder =
    ExamSchedulesCompanion Function({
      Value<int> id,
      required DateTime examDate,
      Value<String> examTime,
      Value<String> subject,
      required String title,
      required String topicsCovered,
      Value<String> examType,
      Value<String> trackName,
      Value<String?> resourceSummary,
      Value<String?> rawReference,
      Value<bool> completedStatus,
      Value<double?> score,
      Value<DateTime> createdAt,
    });
typedef $$ExamSchedulesTableUpdateCompanionBuilder =
    ExamSchedulesCompanion Function({
      Value<int> id,
      Value<DateTime> examDate,
      Value<String> examTime,
      Value<String> subject,
      Value<String> title,
      Value<String> topicsCovered,
      Value<String> examType,
      Value<String> trackName,
      Value<String?> resourceSummary,
      Value<String?> rawReference,
      Value<bool> completedStatus,
      Value<double?> score,
      Value<DateTime> createdAt,
    });

class $$ExamSchedulesTableFilterComposer
    extends Composer<_$AppDatabase, $ExamSchedulesTable> {
  $$ExamSchedulesTableFilterComposer({
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

  ColumnFilters<DateTime> get examDate => $composableBuilder(
    column: $table.examDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get examTime => $composableBuilder(
    column: $table.examTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topicsCovered => $composableBuilder(
    column: $table.topicsCovered,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get examType => $composableBuilder(
    column: $table.examType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackName => $composableBuilder(
    column: $table.trackName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resourceSummary => $composableBuilder(
    column: $table.resourceSummary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawReference => $composableBuilder(
    column: $table.rawReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completedStatus => $composableBuilder(
    column: $table.completedStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExamSchedulesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExamSchedulesTable> {
  $$ExamSchedulesTableOrderingComposer({
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

  ColumnOrderings<DateTime> get examDate => $composableBuilder(
    column: $table.examDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get examTime => $composableBuilder(
    column: $table.examTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topicsCovered => $composableBuilder(
    column: $table.topicsCovered,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get examType => $composableBuilder(
    column: $table.examType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackName => $composableBuilder(
    column: $table.trackName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resourceSummary => $composableBuilder(
    column: $table.resourceSummary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawReference => $composableBuilder(
    column: $table.rawReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completedStatus => $composableBuilder(
    column: $table.completedStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExamSchedulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExamSchedulesTable> {
  $$ExamSchedulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get examDate =>
      $composableBuilder(column: $table.examDate, builder: (column) => column);

  GeneratedColumn<String> get examTime =>
      $composableBuilder(column: $table.examTime, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get topicsCovered => $composableBuilder(
    column: $table.topicsCovered,
    builder: (column) => column,
  );

  GeneratedColumn<String> get examType =>
      $composableBuilder(column: $table.examType, builder: (column) => column);

  GeneratedColumn<String> get trackName =>
      $composableBuilder(column: $table.trackName, builder: (column) => column);

  GeneratedColumn<String> get resourceSummary => $composableBuilder(
    column: $table.resourceSummary,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawReference => $composableBuilder(
    column: $table.rawReference,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get completedStatus => $composableBuilder(
    column: $table.completedStatus,
    builder: (column) => column,
  );

  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ExamSchedulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExamSchedulesTable,
          ExamSchedule,
          $$ExamSchedulesTableFilterComposer,
          $$ExamSchedulesTableOrderingComposer,
          $$ExamSchedulesTableAnnotationComposer,
          $$ExamSchedulesTableCreateCompanionBuilder,
          $$ExamSchedulesTableUpdateCompanionBuilder,
          (
            ExamSchedule,
            BaseReferences<_$AppDatabase, $ExamSchedulesTable, ExamSchedule>,
          ),
          ExamSchedule,
          PrefetchHooks Function()
        > {
  $$ExamSchedulesTableTableManager(_$AppDatabase db, $ExamSchedulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExamSchedulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExamSchedulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExamSchedulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> examDate = const Value.absent(),
                Value<String> examTime = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> topicsCovered = const Value.absent(),
                Value<String> examType = const Value.absent(),
                Value<String> trackName = const Value.absent(),
                Value<String?> resourceSummary = const Value.absent(),
                Value<String?> rawReference = const Value.absent(),
                Value<bool> completedStatus = const Value.absent(),
                Value<double?> score = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ExamSchedulesCompanion(
                id: id,
                examDate: examDate,
                examTime: examTime,
                subject: subject,
                title: title,
                topicsCovered: topicsCovered,
                examType: examType,
                trackName: trackName,
                resourceSummary: resourceSummary,
                rawReference: rawReference,
                completedStatus: completedStatus,
                score: score,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime examDate,
                Value<String> examTime = const Value.absent(),
                Value<String> subject = const Value.absent(),
                required String title,
                required String topicsCovered,
                Value<String> examType = const Value.absent(),
                Value<String> trackName = const Value.absent(),
                Value<String?> resourceSummary = const Value.absent(),
                Value<String?> rawReference = const Value.absent(),
                Value<bool> completedStatus = const Value.absent(),
                Value<double?> score = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ExamSchedulesCompanion.insert(
                id: id,
                examDate: examDate,
                examTime: examTime,
                subject: subject,
                title: title,
                topicsCovered: topicsCovered,
                examType: examType,
                trackName: trackName,
                resourceSummary: resourceSummary,
                rawReference: rawReference,
                completedStatus: completedStatus,
                score: score,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExamSchedulesTable, ExamSchedule>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ExamSchedulesTable,
                    ExamSchedule
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExamSchedulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExamSchedulesTable,
      ExamSchedule,
      $$ExamSchedulesTableFilterComposer,
      $$ExamSchedulesTableOrderingComposer,
      $$ExamSchedulesTableAnnotationComposer,
      $$ExamSchedulesTableCreateCompanionBuilder,
      $$ExamSchedulesTableUpdateCompanionBuilder,
      (
        ExamSchedule,
        BaseReferences<_$AppDatabase, $ExamSchedulesTable, ExamSchedule>,
      ),
      ExamSchedule,
      PrefetchHooks Function()
    >;
typedef $$DailyEnergyLogsTableCreateCompanionBuilder =
    DailyEnergyLogsCompanion Function({
      Value<int> id,
      required DateTime date,
      required EnergyLevel energyLevel,
      Value<int> officeFatigueScore,
      Value<String> completedTasks,
      Value<String?> notes,
      Value<DateTime> createdAt,
    });
typedef $$DailyEnergyLogsTableUpdateCompanionBuilder =
    DailyEnergyLogsCompanion Function({
      Value<int> id,
      Value<DateTime> date,
      Value<EnergyLevel> energyLevel,
      Value<int> officeFatigueScore,
      Value<String> completedTasks,
      Value<String?> notes,
      Value<DateTime> createdAt,
    });

class $$DailyEnergyLogsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyEnergyLogsTable> {
  $$DailyEnergyLogsTableFilterComposer({
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

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EnergyLevel, EnergyLevel, String>
  get energyLevel => $composableBuilder(
    column: $table.energyLevel,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get officeFatigueScore => $composableBuilder(
    column: $table.officeFatigueScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get completedTasks => $composableBuilder(
    column: $table.completedTasks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyEnergyLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyEnergyLogsTable> {
  $$DailyEnergyLogsTableOrderingComposer({
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

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get energyLevel => $composableBuilder(
    column: $table.energyLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get officeFatigueScore => $composableBuilder(
    column: $table.officeFatigueScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get completedTasks => $composableBuilder(
    column: $table.completedTasks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyEnergyLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyEnergyLogsTable> {
  $$DailyEnergyLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EnergyLevel, String> get energyLevel =>
      $composableBuilder(
        column: $table.energyLevel,
        builder: (column) => column,
      );

  GeneratedColumn<int> get officeFatigueScore => $composableBuilder(
    column: $table.officeFatigueScore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get completedTasks => $composableBuilder(
    column: $table.completedTasks,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DailyEnergyLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyEnergyLogsTable,
          DailyEnergyLog,
          $$DailyEnergyLogsTableFilterComposer,
          $$DailyEnergyLogsTableOrderingComposer,
          $$DailyEnergyLogsTableAnnotationComposer,
          $$DailyEnergyLogsTableCreateCompanionBuilder,
          $$DailyEnergyLogsTableUpdateCompanionBuilder,
          (
            DailyEnergyLog,
            BaseReferences<
              _$AppDatabase,
              $DailyEnergyLogsTable,
              DailyEnergyLog
            >,
          ),
          DailyEnergyLog,
          PrefetchHooks Function()
        > {
  $$DailyEnergyLogsTableTableManager(
    _$AppDatabase db,
    $DailyEnergyLogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyEnergyLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyEnergyLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyEnergyLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<EnergyLevel> energyLevel = const Value.absent(),
                Value<int> officeFatigueScore = const Value.absent(),
                Value<String> completedTasks = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => DailyEnergyLogsCompanion(
                id: id,
                date: date,
                energyLevel: energyLevel,
                officeFatigueScore: officeFatigueScore,
                completedTasks: completedTasks,
                notes: notes,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime date,
                required EnergyLevel energyLevel,
                Value<int> officeFatigueScore = const Value.absent(),
                Value<String> completedTasks = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => DailyEnergyLogsCompanion.insert(
                id: id,
                date: date,
                energyLevel: energyLevel,
                officeFatigueScore: officeFatigueScore,
                completedTasks: completedTasks,
                notes: notes,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DailyEnergyLogsTable, DailyEnergyLog>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DailyEnergyLogsTable,
                    DailyEnergyLog
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyEnergyLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyEnergyLogsTable,
      DailyEnergyLog,
      $$DailyEnergyLogsTableFilterComposer,
      $$DailyEnergyLogsTableOrderingComposer,
      $$DailyEnergyLogsTableAnnotationComposer,
      $$DailyEnergyLogsTableCreateCompanionBuilder,
      $$DailyEnergyLogsTableUpdateCompanionBuilder,
      (
        DailyEnergyLog,
        BaseReferences<_$AppDatabase, $DailyEnergyLogsTable, DailyEnergyLog>,
      ),
      DailyEnergyLog,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
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

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
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

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
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

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>(
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

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$ChatSessionsTableCreateCompanionBuilder =
    ChatSessionsCompanion Function({
      Value<int> id,
      required String title,
      Value<String?> subject,
      Value<String?> topic,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> summary,
      Value<int?> summarizedUpToId,
    });
typedef $$ChatSessionsTableUpdateCompanionBuilder =
    ChatSessionsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String?> subject,
      Value<String?> topic,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> summary,
      Value<int?> summarizedUpToId,
    });

class $$ChatSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get summarizedUpToId => $composableBuilder(
    column: $table.summarizedUpToId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get summarizedUpToId => $composableBuilder(
    column: $table.summarizedUpToId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<int> get summarizedUpToId => $composableBuilder(
    column: $table.summarizedUpToId,
    builder: (column) => column,
  );
}

class $$ChatSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatSessionsTable,
          ChatSession,
          $$ChatSessionsTableFilterComposer,
          $$ChatSessionsTableOrderingComposer,
          $$ChatSessionsTableAnnotationComposer,
          $$ChatSessionsTableCreateCompanionBuilder,
          $$ChatSessionsTableUpdateCompanionBuilder,
          (
            ChatSession,
            BaseReferences<_$AppDatabase, $ChatSessionsTable, ChatSession>,
          ),
          ChatSession,
          PrefetchHooks Function()
        > {
  $$ChatSessionsTableTableManager(_$AppDatabase db, $ChatSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> subject = const Value.absent(),
                Value<String?> topic = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<int?> summarizedUpToId = const Value.absent(),
              }) => ChatSessionsCompanion(
                id: id,
                title: title,
                subject: subject,
                topic: topic,
                createdAt: createdAt,
                updatedAt: updatedAt,
                summary: summary,
                summarizedUpToId: summarizedUpToId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                Value<String?> subject = const Value.absent(),
                Value<String?> topic = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<int?> summarizedUpToId = const Value.absent(),
              }) => ChatSessionsCompanion.insert(
                id: id,
                title: title,
                subject: subject,
                topic: topic,
                createdAt: createdAt,
                updatedAt: updatedAt,
                summary: summary,
                summarizedUpToId: summarizedUpToId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatSessionsTable, ChatSession>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatSessionsTable,
                    ChatSession
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatSessionsTable,
      ChatSession,
      $$ChatSessionsTableFilterComposer,
      $$ChatSessionsTableOrderingComposer,
      $$ChatSessionsTableAnnotationComposer,
      $$ChatSessionsTableCreateCompanionBuilder,
      $$ChatSessionsTableUpdateCompanionBuilder,
      (
        ChatSession,
        BaseReferences<_$AppDatabase, $ChatSessionsTable, ChatSession>,
      ),
      ChatSession,
      PrefetchHooks Function()
    >;
typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> id,
      Value<int?> sessionId,
      required String role,
      required String textContent,
      Value<String?> suggestedAction,
      Value<DateTime> timestamp,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> id,
      Value<int?> sessionId,
      Value<String> role,
      Value<String> textContent,
      Value<String?> suggestedAction,
      Value<DateTime> timestamp,
    });

class $$ChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
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

  ColumnFilters<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textContent => $composableBuilder(
    column: $table.textContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suggestedAction => $composableBuilder(
    column: $table.suggestedAction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
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

  ColumnOrderings<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textContent => $composableBuilder(
    column: $table.textContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suggestedAction => $composableBuilder(
    column: $table.suggestedAction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get textContent => $composableBuilder(
    column: $table.textContent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get suggestedAction => $composableBuilder(
    column: $table.suggestedAction,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatMessagesTable,
          ChatMessage,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (
            ChatMessage,
            BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessage>,
          ),
          ChatMessage,
          PrefetchHooks Function()
        > {
  $$ChatMessagesTableTableManager(_$AppDatabase db, $ChatMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> sessionId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> textContent = const Value.absent(),
                Value<String?> suggestedAction = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => ChatMessagesCompanion(
                id: id,
                sessionId: sessionId,
                role: role,
                textContent: textContent,
                suggestedAction: suggestedAction,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> sessionId = const Value.absent(),
                required String role,
                required String textContent,
                Value<String?> suggestedAction = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => ChatMessagesCompanion.insert(
                id: id,
                sessionId: sessionId,
                role: role,
                textContent: textContent,
                suggestedAction: suggestedAction,
                timestamp: timestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatMessagesTable, ChatMessage>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatMessagesTable,
                    ChatMessage
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatMessagesTable,
      ChatMessage,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (
        ChatMessage,
        BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessage>,
      ),
      ChatMessage,
      PrefetchHooks Function()
    >;
typedef $$DrillRecordsTableCreateCompanionBuilder =
    DrillRecordsCompanion Function({
      Value<int> id,
      required String subject,
      required String topic,
      required int totalQuestions,
      required int correctCount,
      required int incorrectCount,
      required double scorePercentage,
      Value<DateTime> createdAt,
    });
typedef $$DrillRecordsTableUpdateCompanionBuilder =
    DrillRecordsCompanion Function({
      Value<int> id,
      Value<String> subject,
      Value<String> topic,
      Value<int> totalQuestions,
      Value<int> correctCount,
      Value<int> incorrectCount,
      Value<double> scorePercentage,
      Value<DateTime> createdAt,
    });

class $$DrillRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $DrillRecordsTable> {
  $$DrillRecordsTableFilterComposer({
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

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalQuestions => $composableBuilder(
    column: $table.totalQuestions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get correctCount => $composableBuilder(
    column: $table.correctCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get incorrectCount => $composableBuilder(
    column: $table.incorrectCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get scorePercentage => $composableBuilder(
    column: $table.scorePercentage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DrillRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $DrillRecordsTable> {
  $$DrillRecordsTableOrderingComposer({
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

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalQuestions => $composableBuilder(
    column: $table.totalQuestions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get correctCount => $composableBuilder(
    column: $table.correctCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get incorrectCount => $composableBuilder(
    column: $table.incorrectCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get scorePercentage => $composableBuilder(
    column: $table.scorePercentage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DrillRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DrillRecordsTable> {
  $$DrillRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<int> get totalQuestions => $composableBuilder(
    column: $table.totalQuestions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get correctCount => $composableBuilder(
    column: $table.correctCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get incorrectCount => $composableBuilder(
    column: $table.incorrectCount,
    builder: (column) => column,
  );

  GeneratedColumn<double> get scorePercentage => $composableBuilder(
    column: $table.scorePercentage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DrillRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DrillRecordsTable,
          DrillRecord,
          $$DrillRecordsTableFilterComposer,
          $$DrillRecordsTableOrderingComposer,
          $$DrillRecordsTableAnnotationComposer,
          $$DrillRecordsTableCreateCompanionBuilder,
          $$DrillRecordsTableUpdateCompanionBuilder,
          (
            DrillRecord,
            BaseReferences<_$AppDatabase, $DrillRecordsTable, DrillRecord>,
          ),
          DrillRecord,
          PrefetchHooks Function()
        > {
  $$DrillRecordsTableTableManager(_$AppDatabase db, $DrillRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DrillRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DrillRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DrillRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> topic = const Value.absent(),
                Value<int> totalQuestions = const Value.absent(),
                Value<int> correctCount = const Value.absent(),
                Value<int> incorrectCount = const Value.absent(),
                Value<double> scorePercentage = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => DrillRecordsCompanion(
                id: id,
                subject: subject,
                topic: topic,
                totalQuestions: totalQuestions,
                correctCount: correctCount,
                incorrectCount: incorrectCount,
                scorePercentage: scorePercentage,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String subject,
                required String topic,
                required int totalQuestions,
                required int correctCount,
                required int incorrectCount,
                required double scorePercentage,
                Value<DateTime> createdAt = const Value.absent(),
              }) => DrillRecordsCompanion.insert(
                id: id,
                subject: subject,
                topic: topic,
                totalQuestions: totalQuestions,
                correctCount: correctCount,
                incorrectCount: incorrectCount,
                scorePercentage: scorePercentage,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DrillRecordsTable, DrillRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DrillRecordsTable,
                    DrillRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DrillRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DrillRecordsTable,
      DrillRecord,
      $$DrillRecordsTableFilterComposer,
      $$DrillRecordsTableOrderingComposer,
      $$DrillRecordsTableAnnotationComposer,
      $$DrillRecordsTableCreateCompanionBuilder,
      $$DrillRecordsTableUpdateCompanionBuilder,
      (
        DrillRecord,
        BaseReferences<_$AppDatabase, $DrillRecordsTable, DrillRecord>,
      ),
      DrillRecord,
      PrefetchHooks Function()
    >;
typedef $$DrillQuestionsTableCreateCompanionBuilder =
    DrillQuestionsCompanion Function({
      Value<int> id,
      Value<int?> drillRecordId,
      required String subject,
      required String topic,
      required String questionText,
      required String optionsJson,
      required int correctIndex,
      required int selectedIndex,
      required bool isCorrect,
      Value<String> explanation,
      Value<bool> isMastered,
      Value<DateTime> attemptedAt,
      Value<int?> originalCorrectIndex,
      Value<String?> originalExplanation,
      Value<String?> originalQuestionText,
      Value<String?> originalOptionsJson,
      Value<DateTime?> correctedAt,
      Value<String?> verificationStatus,
      Value<String?> verificationNote,
      Value<DateTime?> verifiedAt,
    });
typedef $$DrillQuestionsTableUpdateCompanionBuilder =
    DrillQuestionsCompanion Function({
      Value<int> id,
      Value<int?> drillRecordId,
      Value<String> subject,
      Value<String> topic,
      Value<String> questionText,
      Value<String> optionsJson,
      Value<int> correctIndex,
      Value<int> selectedIndex,
      Value<bool> isCorrect,
      Value<String> explanation,
      Value<bool> isMastered,
      Value<DateTime> attemptedAt,
      Value<int?> originalCorrectIndex,
      Value<String?> originalExplanation,
      Value<String?> originalQuestionText,
      Value<String?> originalOptionsJson,
      Value<DateTime?> correctedAt,
      Value<String?> verificationStatus,
      Value<String?> verificationNote,
      Value<DateTime?> verifiedAt,
    });

class $$DrillQuestionsTableFilterComposer
    extends Composer<_$AppDatabase, $DrillQuestionsTable> {
  $$DrillQuestionsTableFilterComposer({
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

  ColumnFilters<int> get drillRecordId => $composableBuilder(
    column: $table.drillRecordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionText => $composableBuilder(
    column: $table.questionText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get correctIndex => $composableBuilder(
    column: $table.correctIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get selectedIndex => $composableBuilder(
    column: $table.selectedIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCorrect => $composableBuilder(
    column: $table.isCorrect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMastered => $composableBuilder(
    column: $table.isMastered,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get attemptedAt => $composableBuilder(
    column: $table.attemptedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get originalCorrectIndex => $composableBuilder(
    column: $table.originalCorrectIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalExplanation => $composableBuilder(
    column: $table.originalExplanation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalQuestionText => $composableBuilder(
    column: $table.originalQuestionText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalOptionsJson => $composableBuilder(
    column: $table.originalOptionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verificationNote => $composableBuilder(
    column: $table.verificationNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DrillQuestionsTableOrderingComposer
    extends Composer<_$AppDatabase, $DrillQuestionsTable> {
  $$DrillQuestionsTableOrderingComposer({
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

  ColumnOrderings<int> get drillRecordId => $composableBuilder(
    column: $table.drillRecordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionText => $composableBuilder(
    column: $table.questionText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get correctIndex => $composableBuilder(
    column: $table.correctIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get selectedIndex => $composableBuilder(
    column: $table.selectedIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCorrect => $composableBuilder(
    column: $table.isCorrect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMastered => $composableBuilder(
    column: $table.isMastered,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get attemptedAt => $composableBuilder(
    column: $table.attemptedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get originalCorrectIndex => $composableBuilder(
    column: $table.originalCorrectIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalExplanation => $composableBuilder(
    column: $table.originalExplanation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalQuestionText => $composableBuilder(
    column: $table.originalQuestionText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalOptionsJson => $composableBuilder(
    column: $table.originalOptionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verificationNote => $composableBuilder(
    column: $table.verificationNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DrillQuestionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DrillQuestionsTable> {
  $$DrillQuestionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get drillRecordId => $composableBuilder(
    column: $table.drillRecordId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<String> get questionText => $composableBuilder(
    column: $table.questionText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get optionsJson => $composableBuilder(
    column: $table.optionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get correctIndex => $composableBuilder(
    column: $table.correctIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get selectedIndex => $composableBuilder(
    column: $table.selectedIndex,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCorrect =>
      $composableBuilder(column: $table.isCorrect, builder: (column) => column);

  GeneratedColumn<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isMastered => $composableBuilder(
    column: $table.isMastered,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get attemptedAt => $composableBuilder(
    column: $table.attemptedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get originalCorrectIndex => $composableBuilder(
    column: $table.originalCorrectIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalExplanation => $composableBuilder(
    column: $table.originalExplanation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalQuestionText => $composableBuilder(
    column: $table.originalQuestionText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalOptionsJson => $composableBuilder(
    column: $table.originalOptionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get verificationStatus => $composableBuilder(
    column: $table.verificationStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get verificationNote => $composableBuilder(
    column: $table.verificationNote,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => column,
  );
}

class $$DrillQuestionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DrillQuestionsTable,
          DrillQuestion,
          $$DrillQuestionsTableFilterComposer,
          $$DrillQuestionsTableOrderingComposer,
          $$DrillQuestionsTableAnnotationComposer,
          $$DrillQuestionsTableCreateCompanionBuilder,
          $$DrillQuestionsTableUpdateCompanionBuilder,
          (
            DrillQuestion,
            BaseReferences<_$AppDatabase, $DrillQuestionsTable, DrillQuestion>,
          ),
          DrillQuestion,
          PrefetchHooks Function()
        > {
  $$DrillQuestionsTableTableManager(
    _$AppDatabase db,
    $DrillQuestionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DrillQuestionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DrillQuestionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DrillQuestionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> drillRecordId = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> topic = const Value.absent(),
                Value<String> questionText = const Value.absent(),
                Value<String> optionsJson = const Value.absent(),
                Value<int> correctIndex = const Value.absent(),
                Value<int> selectedIndex = const Value.absent(),
                Value<bool> isCorrect = const Value.absent(),
                Value<String> explanation = const Value.absent(),
                Value<bool> isMastered = const Value.absent(),
                Value<DateTime> attemptedAt = const Value.absent(),
                Value<int?> originalCorrectIndex = const Value.absent(),
                Value<String?> originalExplanation = const Value.absent(),
                Value<String?> originalQuestionText = const Value.absent(),
                Value<String?> originalOptionsJson = const Value.absent(),
                Value<DateTime?> correctedAt = const Value.absent(),
                Value<String?> verificationStatus = const Value.absent(),
                Value<String?> verificationNote = const Value.absent(),
                Value<DateTime?> verifiedAt = const Value.absent(),
              }) => DrillQuestionsCompanion(
                id: id,
                drillRecordId: drillRecordId,
                subject: subject,
                topic: topic,
                questionText: questionText,
                optionsJson: optionsJson,
                correctIndex: correctIndex,
                selectedIndex: selectedIndex,
                isCorrect: isCorrect,
                explanation: explanation,
                isMastered: isMastered,
                attemptedAt: attemptedAt,
                originalCorrectIndex: originalCorrectIndex,
                originalExplanation: originalExplanation,
                originalQuestionText: originalQuestionText,
                originalOptionsJson: originalOptionsJson,
                correctedAt: correctedAt,
                verificationStatus: verificationStatus,
                verificationNote: verificationNote,
                verifiedAt: verifiedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> drillRecordId = const Value.absent(),
                required String subject,
                required String topic,
                required String questionText,
                required String optionsJson,
                required int correctIndex,
                required int selectedIndex,
                required bool isCorrect,
                Value<String> explanation = const Value.absent(),
                Value<bool> isMastered = const Value.absent(),
                Value<DateTime> attemptedAt = const Value.absent(),
                Value<int?> originalCorrectIndex = const Value.absent(),
                Value<String?> originalExplanation = const Value.absent(),
                Value<String?> originalQuestionText = const Value.absent(),
                Value<String?> originalOptionsJson = const Value.absent(),
                Value<DateTime?> correctedAt = const Value.absent(),
                Value<String?> verificationStatus = const Value.absent(),
                Value<String?> verificationNote = const Value.absent(),
                Value<DateTime?> verifiedAt = const Value.absent(),
              }) => DrillQuestionsCompanion.insert(
                id: id,
                drillRecordId: drillRecordId,
                subject: subject,
                topic: topic,
                questionText: questionText,
                optionsJson: optionsJson,
                correctIndex: correctIndex,
                selectedIndex: selectedIndex,
                isCorrect: isCorrect,
                explanation: explanation,
                isMastered: isMastered,
                attemptedAt: attemptedAt,
                originalCorrectIndex: originalCorrectIndex,
                originalExplanation: originalExplanation,
                originalQuestionText: originalQuestionText,
                originalOptionsJson: originalOptionsJson,
                correctedAt: correctedAt,
                verificationStatus: verificationStatus,
                verificationNote: verificationNote,
                verifiedAt: verifiedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DrillQuestionsTable, DrillQuestion>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DrillQuestionsTable,
                    DrillQuestion
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DrillQuestionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DrillQuestionsTable,
      DrillQuestion,
      $$DrillQuestionsTableFilterComposer,
      $$DrillQuestionsTableOrderingComposer,
      $$DrillQuestionsTableAnnotationComposer,
      $$DrillQuestionsTableCreateCompanionBuilder,
      $$DrillQuestionsTableUpdateCompanionBuilder,
      (
        DrillQuestion,
        BaseReferences<_$AppDatabase, $DrillQuestionsTable, DrillQuestion>,
      ),
      DrillQuestion,
      PrefetchHooks Function()
    >;
typedef $$SpacedReviewItemsTableCreateCompanionBuilder =
    SpacedReviewItemsCompanion Function({
      Value<int> id,
      required String subject,
      required String topic,
      required String title,
      required String keyRule,
      Value<int> repetitionLevel,
      Value<int> intervalDays,
      required DateTime nextReviewDate,
      Value<DateTime?> lastReviewedAt,
      Value<bool> isMastered,
      Value<DateTime> createdAt,
    });
typedef $$SpacedReviewItemsTableUpdateCompanionBuilder =
    SpacedReviewItemsCompanion Function({
      Value<int> id,
      Value<String> subject,
      Value<String> topic,
      Value<String> title,
      Value<String> keyRule,
      Value<int> repetitionLevel,
      Value<int> intervalDays,
      Value<DateTime> nextReviewDate,
      Value<DateTime?> lastReviewedAt,
      Value<bool> isMastered,
      Value<DateTime> createdAt,
    });

class $$SpacedReviewItemsTableFilterComposer
    extends Composer<_$AppDatabase, $SpacedReviewItemsTable> {
  $$SpacedReviewItemsTableFilterComposer({
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

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyRule => $composableBuilder(
    column: $table.keyRule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repetitionLevel => $composableBuilder(
    column: $table.repetitionLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intervalDays => $composableBuilder(
    column: $table.intervalDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextReviewDate => $composableBuilder(
    column: $table.nextReviewDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastReviewedAt => $composableBuilder(
    column: $table.lastReviewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMastered => $composableBuilder(
    column: $table.isMastered,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SpacedReviewItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $SpacedReviewItemsTable> {
  $$SpacedReviewItemsTableOrderingComposer({
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

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyRule => $composableBuilder(
    column: $table.keyRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repetitionLevel => $composableBuilder(
    column: $table.repetitionLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intervalDays => $composableBuilder(
    column: $table.intervalDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextReviewDate => $composableBuilder(
    column: $table.nextReviewDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastReviewedAt => $composableBuilder(
    column: $table.lastReviewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMastered => $composableBuilder(
    column: $table.isMastered,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SpacedReviewItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpacedReviewItemsTable> {
  $$SpacedReviewItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get keyRule =>
      $composableBuilder(column: $table.keyRule, builder: (column) => column);

  GeneratedColumn<int> get repetitionLevel => $composableBuilder(
    column: $table.repetitionLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get intervalDays => $composableBuilder(
    column: $table.intervalDays,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextReviewDate => $composableBuilder(
    column: $table.nextReviewDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastReviewedAt => $composableBuilder(
    column: $table.lastReviewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isMastered => $composableBuilder(
    column: $table.isMastered,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SpacedReviewItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpacedReviewItemsTable,
          SpacedReviewItem,
          $$SpacedReviewItemsTableFilterComposer,
          $$SpacedReviewItemsTableOrderingComposer,
          $$SpacedReviewItemsTableAnnotationComposer,
          $$SpacedReviewItemsTableCreateCompanionBuilder,
          $$SpacedReviewItemsTableUpdateCompanionBuilder,
          (
            SpacedReviewItem,
            BaseReferences<
              _$AppDatabase,
              $SpacedReviewItemsTable,
              SpacedReviewItem
            >,
          ),
          SpacedReviewItem,
          PrefetchHooks Function()
        > {
  $$SpacedReviewItemsTableTableManager(
    _$AppDatabase db,
    $SpacedReviewItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SpacedReviewItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SpacedReviewItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SpacedReviewItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> topic = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> keyRule = const Value.absent(),
                Value<int> repetitionLevel = const Value.absent(),
                Value<int> intervalDays = const Value.absent(),
                Value<DateTime> nextReviewDate = const Value.absent(),
                Value<DateTime?> lastReviewedAt = const Value.absent(),
                Value<bool> isMastered = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SpacedReviewItemsCompanion(
                id: id,
                subject: subject,
                topic: topic,
                title: title,
                keyRule: keyRule,
                repetitionLevel: repetitionLevel,
                intervalDays: intervalDays,
                nextReviewDate: nextReviewDate,
                lastReviewedAt: lastReviewedAt,
                isMastered: isMastered,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String subject,
                required String topic,
                required String title,
                required String keyRule,
                Value<int> repetitionLevel = const Value.absent(),
                Value<int> intervalDays = const Value.absent(),
                required DateTime nextReviewDate,
                Value<DateTime?> lastReviewedAt = const Value.absent(),
                Value<bool> isMastered = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SpacedReviewItemsCompanion.insert(
                id: id,
                subject: subject,
                topic: topic,
                title: title,
                keyRule: keyRule,
                repetitionLevel: repetitionLevel,
                intervalDays: intervalDays,
                nextReviewDate: nextReviewDate,
                lastReviewedAt: lastReviewedAt,
                isMastered: isMastered,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SpacedReviewItemsTable, SpacedReviewItem>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SpacedReviewItemsTable,
                    SpacedReviewItem
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SpacedReviewItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpacedReviewItemsTable,
      SpacedReviewItem,
      $$SpacedReviewItemsTableFilterComposer,
      $$SpacedReviewItemsTableOrderingComposer,
      $$SpacedReviewItemsTableAnnotationComposer,
      $$SpacedReviewItemsTableCreateCompanionBuilder,
      $$SpacedReviewItemsTableUpdateCompanionBuilder,
      (
        SpacedReviewItem,
        BaseReferences<
          _$AppDatabase,
          $SpacedReviewItemsTable,
          SpacedReviewItem
        >,
      ),
      SpacedReviewItem,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WeakTopicsTableTableManager get weakTopics =>
      $$WeakTopicsTableTableManager(_db, _db.weakTopics);
  $$ExamSchedulesTableTableManager get examSchedules =>
      $$ExamSchedulesTableTableManager(_db, _db.examSchedules);
  $$DailyEnergyLogsTableTableManager get dailyEnergyLogs =>
      $$DailyEnergyLogsTableTableManager(_db, _db.dailyEnergyLogs);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$ChatSessionsTableTableManager get chatSessions =>
      $$ChatSessionsTableTableManager(_db, _db.chatSessions);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$DrillRecordsTableTableManager get drillRecords =>
      $$DrillRecordsTableTableManager(_db, _db.drillRecords);
  $$DrillQuestionsTableTableManager get drillQuestions =>
      $$DrillQuestionsTableTableManager(_db, _db.drillQuestions);
  $$SpacedReviewItemsTableTableManager get spacedReviewItems =>
      $$SpacedReviewItemsTableTableManager(_db, _db.spacedReviewItems);
}
