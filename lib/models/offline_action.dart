class OfflineAction {
  final int id;
  final String actionType;
  final String payload;
  final String status;
  final int retryCount;

  OfflineAction({
    required this.id,
    required this.actionType,
    required this.payload,
    required this.status,
    required this.retryCount,
  });

  factory OfflineAction.fromMap(Map<String, dynamic> map) {
    return OfflineAction(
      id: map['id'],
      actionType: map['action_type'],
      payload: map['payload'],
      status: map['status'],
      retryCount: map['retry_count'] ?? 0,
    );
  }
}