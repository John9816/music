import '../models/membership.dart';
import 'api_client.dart';

class MembershipApi {
  final ApiClient _client = ApiClient.instance;

  Future<Membership> getMembership(String token) async {
    final data = await _client.getJson(
      'api/user/membership',
      headers: {'Authorization': 'Bearer $token'},
    );
    return Membership.fromJson(data);
  }

  Future<RedeemResult> redeem(String code, String token) async {
    final data = await _client.postJson(
      'api/user/membership/redeem',
      body: {'code': code.trim().toUpperCase().replaceAll(' ', '')},
      headers: {'Authorization': 'Bearer $token'},
    );
    return RedeemResult.fromJson(data);
  }
}
