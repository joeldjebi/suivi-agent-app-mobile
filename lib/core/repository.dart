import 'package:dio/dio.dart';

import 'api_client.dart';
import 'models.dart';

/// Appels de l'API utilisés par l'app de l'agent.
class Repository {
  Repository(this.api);

  final ApiClient api;

  /// Connexion à l'app mobile : numéro de téléphone et mot de passe.
  Future<Map<String, dynamic>> login(String phone, String password) =>
      api.post<Map<String, dynamic>>('/auth/login', {
        'phone': phone,
        'password': password,
      });

  /// Profil brut (/auth/me) : utilisateur, structure, réglages, formule.
  Future<Map<String, dynamic>> meJson() =>
      api.get<Map<String, dynamic>>('/auth/me');

  Future<void> logout(String refreshToken) =>
      api.post<void>('/auth/logout', {'refreshToken': refreshToken});

  // Profil de l'utilisateur connecté : chaque appel renvoie le profil à jour.

  Future<Map<String, dynamic>> updateProfile({
    String? firstName,
    String? lastName,
    String? email,
  }) => api.patch<Map<String, dynamic>>('/auth/me', {
    if (firstName != null) 'firstName': firstName,
    if (lastName != null) 'lastName': lastName,
    if (email != null) 'email': email,
  });

  /// Renvoie de nouveaux jetons : les autres appareils sont déconnectés, pas celui-ci.
  Future<Map<String, dynamic>> changePassword(String current, String next) =>
      api.patch<Map<String, dynamic>>('/auth/password', {
        'currentPassword': current,
        'newPassword': next,
      });

  Future<Map<String, dynamic>> uploadAvatar(List<int> bytes) =>
      api.put<Map<String, dynamic>>(
        '/auth/me/avatar',
        FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: 'photo.jpg'),
        }),
      );

  Future<Map<String, dynamic>> deleteAvatar() =>
      api.delete<Map<String, dynamic>>('/auth/me/avatar');

  /// Photo de profil d'un utilisateur (soi, ou un agent pour le chef).
  Future<List<int>?> avatarBytes(String userId) async {
    try {
      return (await api.dio.get<List<int>>(
        '/users/$userId/avatar',
        options: _bytes,
      )).data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.from(e);
    }
  }

  Future<Me> me() async =>
      Me.fromJson(await api.get<Map<String, dynamic>>('/auth/me'));

  Future<Map<String, dynamic>> branding() =>
      api.get<Map<String, dynamic>>('/branding');

  Future<List<int>> logoBytes() async =>
      (await api.dio.get<List<int>>('/branding/logo', options: _bytes)).data!;

  Future<DayState> currentDay() async =>
      DayState.fromJson(await api.get<Map<String, dynamic>>('/days/current'));

  Future<AvailableZones> availableZones() async => AvailableZones.fromJson(
    await api.get<Map<String, dynamic>>('/zones/available'),
  );

  Future<ZoneRequest> requestZone(String zoneId) async => ZoneRequest.fromJson(
    await api.post<Map<String, dynamic>>('/zone-requests', {'zoneId': zoneId}),
  );

  Future<void> cancelRequest(String id) =>
      api.post<Map<String, dynamic>>('/zone-requests/$id/cancel');

  Future<WorkDay> dayAction(String action) async =>
      WorkDay.fromJson(await api.post<Map<String, dynamic>>('/days/$action'));

  Future<Map<String, dynamic>> sendPositions(
    String dayId,
    List<Map<String, dynamic>> points,
  ) => api.post<Map<String, dynamic>>('/positions/batch', {
    'dayId': dayId,
    'points': points,
  });

  /// Missions visibles ; le chef voit aussi celles qu'il a désactivées (pour les réactiver).
  Future<List<Map<String, dynamic>>> missionsJson() async =>
      ((await api.get<Map<String, dynamic>>(
                '/missions',
                query: {'limit': 100, 'includeInactive': true},
              ))['items']
              as List)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> missionJson(String id) =>
      api.get<Map<String, dynamic>>('/missions/$id');

  Future<List<Submission>> submissions(
    String missionId, {
    SubmissionFilter filter = const SubmissionFilter(),
  }) async => (await api.get<List<dynamic>>(
    '/missions/$missionId/submissions',
    query: filter.query(DateTime.now()),
  )).map((s) => Submission.fromJson(s as Map<String, dynamic>)).toList();

  Future<void> submit(String missionId, Map<String, dynamic> body) =>
      api.post<Map<String, dynamic>>('/missions/$missionId/submissions', body);

  Future<List<AppNotification>> notifications() async =>
      (await api.get<List<dynamic>>('/notifications'))
          .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
          .toList();

  Future<void> markAllRead() => api.post<void>('/notifications/read-all');

  // --- Chef d'équipe -------------------------------------------------------

  Future<List<LiveAgent>> live() async => (await api.get<List<dynamic>>(
    '/live',
  )).map((a) => LiveAgent.fromJson(a as Map<String, dynamic>)).toList();

  /// Itinéraire complet d'une journée (chef : agents de son groupe).
  Future<List<TrackPoint>> track(String dayId) async =>
      (await api.get<List<dynamic>>(
        '/days/$dayId/positions',
      )).map((p) => TrackPoint.fromJson(p as Map<String, dynamic>)).toList();

  /// Mes gains : estimation de la période en cours et paies validées.
  Future<MyPay> myPay() async =>
      MyPay.fromJson(await api.get<Map<String, dynamic>>('/pay/me'));

  /// Chef d'équipe : estimation de la période en cours pour son équipe.
  Future<CurrentPay> teamPay() async =>
      CurrentPay.fromJson(await api.get<Map<String, dynamic>>('/pay/current'));

  Future<List<TeamMember>> team() async =>
      ((await api.get<Map<String, dynamic>>(
                '/users',
                query: {'role': 'agent', 'limit': 200},
              ))['items']
              as List)
          .map((u) => TeamMember.fromJson(u as Map<String, dynamic>))
          .where((u) => u.isActive)
          .toList();

  /// Zones des groupes du chef : identifiant → nom et places.
  Future<List<Zone>> leaderZones() async => (await api.get<List<dynamic>>(
    '/zones',
  )).map((z) => Zone.fromJson(z as Map<String, dynamic>)).toList();

  Future<List<PendingRequest>> pendingRequests() async =>
      ((await api.get<Map<String, dynamic>>(
                '/zone-requests',
                query: {'status': 'pending', 'limit': 100},
              ))['items']
              as List)
          .map((r) => PendingRequest.fromJson(r as Map<String, dynamic>))
          .toList();

  Future<void> decide(
    String requestId, {
    required bool approve,
    String? reason,
  }) => api.post<Map<String, dynamic>>('/zone-requests/$requestId/decision', {
    'approve': approve,
    if (reason != null && reason.isNotEmpty) 'reason': reason,
  });

  /// Bilan d'une journée de l'équipe (aujourd'hui par défaut).
  Future<DailyReport> dailyReport({
    DateTime? date,
  }) async => DailyReport.fromJson(
    await api.get<Map<String, dynamic>>(
      '/reports/daily',
      query: {
        if (date != null)
          'date':
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      },
    ),
  );

  /// Message du chef à toute son équipe, ou à des agents choisis. Renvoie le nombre de destinataires.
  Future<int> sendTeamMessage(String body, {List<String>? agentIds}) async =>
      ((await api.post<Map<String, dynamic>>('/team-messages', {
                'body': body,
                if (agentIds != null && agentIds.isNotEmpty)
                  'agentIds': agentIds,
              }))['recipients']
              as num)
          .toInt();

  /// Centre d'alertes du chef : en cours (open) ou refermées (resolved).
  Future<List<AgentAlert>> alerts({String status = 'open'}) async =>
      (await api.get<List<dynamic>>(
        '/alerts',
        query: {
          'status': status,
          if (status == 'resolved')
            'from': DateTime.now()
                .subtract(const Duration(days: 7))
                .toUtc()
                .toIso8601String(),
        },
      )).map((a) => AgentAlert.fromJson(a as Map<String, dynamic>)).toList();

  /// « Je m'en occupe », avec une note facultative.
  Future<void> acknowledgeAlert(String id, {String? note}) =>
      api.post<Map<String, dynamic>>('/alerts/$id/ack', {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  Future<void> reassign(String agentId, String zoneId) =>
      api.post<Map<String, dynamic>>('/zone-requests/reassign', {
        'agentId': agentId,
        'zoneId': zoneId,
      });

  // --- Chef d'équipe : missions --------------------------------------------

  Future<List<MissionType>> missionTypes() async =>
      (await api.get<List<dynamic>>(
        '/mission-types',
      )).map((t) => MissionType.fromJson(t as Map<String, dynamic>)).toList();

  /// Groupes dirigés par le chef (vide si la formule n'inclut pas les groupes).
  Future<List<TeamGroup>> leaderGroups() async {
    try {
      return (await api.get<List<dynamic>>(
        '/groups',
      )).map((g) => TeamGroup.fromJson(g as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (e.status == 402) return [];
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createMission(Map<String, dynamic> body) =>
      api.post<Map<String, dynamic>>('/missions', body);

  Future<Map<String, dynamic>> updateMission(
    String id,
    Map<String, dynamic> body,
  ) => api.patch<Map<String, dynamic>>('/missions/$id', body);

  /// Mission en validation manuelle : atteinte ou échouée.
  Future<void> setMissionResult(String id, {required bool achieved}) =>
      api.post<Map<String, dynamic>>('/missions/$id/result', {
        'achieved': achieved,
      });

  /// Suppression définitive (refusée si des formulaires ont été reçus).
  Future<void> deleteMission(String id) => api.delete<void>('/missions/$id');

  // --- Chef d'équipe : rémunération ----------------------------------------

  Future<List<PayRunSummary>> payRuns() async => (await api.get<List<dynamic>>(
    '/pay/runs',
  )).map((r) => PayRunSummary.fromJson(r as Map<String, dynamic>)).toList();

  Future<PayRunDetail> payRun(String id) async => PayRunDetail.fromJson(
    await api.get<Map<String, dynamic>>('/pay/runs/$id'),
  );

  /// Proposition d'ajustement (prime ou retenue), décidée par l'administrateur.
  Future<void> proposeAdjustment(
    String runId, {
    required String userId,
    required int amount,
    required String reason,
  }) => api.post<Map<String, dynamic>>('/pay/runs/$runId/adjustments', {
    'userId': userId,
    'amount': amount,
    'reason': reason,
  });

  Future<void> rejectSubmission(String submissionId, String reason) =>
      api.post<Map<String, dynamic>>('/submissions/$submissionId/reject', {
        'reason': reason,
      });
}

final _bytes = Options(responseType: ResponseType.bytes);
