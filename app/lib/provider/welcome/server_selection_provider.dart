import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wanderer/models/server_instance.dart';

part 'server_selection_provider.g.dart';

class ServerState {
  List<ServerInstance> availableServers;
  ServerInstance? selectedServer;

  ServerState(this.availableServers, this.selectedServer);
}

@riverpod
class ServerSelectionNotifier extends _$ServerSelectionNotifier {
  static const _liveRide = ServerInstance(
    name: 'Live Ride',
    url: 'https://ride.76-13-3-214.sslip.io',
    description: 'Live Ride self-hosted server',
  );

  @override
  Future<ServerState> build() async {
    // Live Ride is a dedicated self-hosted product, not a generic Wanderer
    // instance browser. Selecting our server up-front removes the upstream
    // wanderer.to directory from onboarding and makes login/register ready
    // immediately.
    return ServerState(const [_liveRide], _liveRide);
  }

  void setSelectedServer(ServerInstance server) {
    final newState = ServerState(state.requireValue.availableServers, server);
    state = AsyncValue.data(newState);
  }
}
