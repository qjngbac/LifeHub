class EntityReference {
  const EntityReference({required this.type, required this.id});

  final String type;
  final String id;

  String get key => '${type.toUpperCase()}:$id';
}

class RelatedEntity {
  const RelatedEntity({
    required this.reference,
    required this.title,
    this.subtitle,
  });

  final EntityReference reference;
  final String title;
  final String? subtitle;
}

class EntityRelation {
  const EntityRelation({
    required this.linkId,
    required this.entity,
    required this.relationType,
    this.note,
  });

  final String linkId;
  final RelatedEntity entity;
  final String relationType;
  final String? note;
}
