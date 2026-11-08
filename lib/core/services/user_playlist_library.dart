import 'package:flutter/foundation.dart';

/// 用户音乐库发生线上变更时，通知收藏、侧栏和资料库重新拉取账号数据。
class UserPlaylistLibrary extends ChangeNotifier {
  UserPlaylistLibrary._();

  static final UserPlaylistLibrary instance = UserPlaylistLibrary._();

  int _revision = 0;
  int get revision => _revision;

  void markChanged() {
    _revision++;
    notifyListeners();
  }
}
