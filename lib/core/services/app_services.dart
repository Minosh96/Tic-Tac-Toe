import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/friends_repository.dart';
import '../../data/repositories/game_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/rivalry_repository.dart';
import '../../data/repositories/single_player_repository.dart';
import '../../data/repositories/voice_call_repository.dart';
import 'preferences_controller.dart';
import 'sound_service.dart';

/// Single dependency container wiring all Melow v3.7 repositories & services.
class AppServices {
  AppServices({
    required this.preferences,
    required this.sound,
    required this.game,
    required this.profile,
    required this.friends,
    required this.rivalry,
    required this.leaderboard,
    required this.chat,
    required this.voiceCall,
    SinglePlayerRepository? singlePlayer,
    GroupRepository? groups,
  })  : singlePlayer = singlePlayer ?? SinglePlayerRepository(),
        groups = groups ??
            GroupRepository(
              gameRepository: game,
              friendsRepository: friends,
            );

  factory AppServices.production({String databaseId = 'melow-game'}) {
    final preferences = PreferencesController();
    final sound = SoundService(preferences: preferences);
    final game = GameRepository(databaseId: databaseId);
    final profile = ProfileRepository(databaseId: databaseId);
    final friends = FriendsRepository(
      gameRepository: game,
      databaseId: databaseId,
    );
    final rivalry = RivalryRepository(databaseId: databaseId);
    final leaderboard = LeaderboardRepository(databaseId: databaseId);
    final chat = ChatRepository(databaseId: databaseId);
    final voiceCall = VoiceCallRepository(databaseId: databaseId);
    final singlePlayer = SinglePlayerRepository(databaseId: databaseId);
    final groups = GroupRepository(
      gameRepository: game,
      friendsRepository: friends,
      databaseId: databaseId,
    );

    preferences.onCloudSync = (prefs) => profile.savePrivatePreferences(prefs);

    return AppServices(
      preferences: preferences,
      sound: sound,
      game: game,
      profile: profile,
      friends: friends,
      rivalry: rivalry,
      leaderboard: leaderboard,
      chat: chat,
      voiceCall: voiceCall,
      singlePlayer: singlePlayer,
      groups: groups,
    );
  }

  final PreferencesController preferences;
  final SoundService sound;
  final GameRepository game;
  final ProfileRepository profile;
  final FriendsRepository friends;
  final RivalryRepository rivalry;
  final LeaderboardRepository leaderboard;
  final ChatRepository chat;
  final VoiceCallRepository voiceCall;
  final SinglePlayerRepository singlePlayer;
  final GroupRepository groups;

  Future<void> dispose() async {
    await sound.dispose();
    preferences.dispose();
    singlePlayer.dispose();
  }
}
