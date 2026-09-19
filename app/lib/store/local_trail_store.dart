export 'local_trail_store_legacy.dart' hide saveNewLocalTrail;

import 'package:wanderer/entities/trail_entity.dart';
import 'package:wanderer/models/trail.dart';
import 'package:wanderer/objectbox.g.dart';
import 'package:wanderer/store/local_trail_store_legacy.dart' as legacy;

/// Live Ride keeps a route created on this device in the creator's offline
/// library automatically.
///
/// The upstream capture store intentionally separates authorship from library
/// membership and would normally retire (delete) the local row after a
/// successful upload. For a cycling app that reads as data loss: the route is
/// on the server, but vanishes from the phone and from Library. We reuse the
/// battle-tested upstream write first, then add the current account to
/// savedByUserIds. retireUploadedLocalTrail will therefore demote the capture
/// to an ordinary synced/downloaded row instead of deleting it.
String saveNewLocalTrail(
  Store store, {
  required Trail trail,
  required String ownerAccountId,
  String? authorActorId,
  required String localId,
  required List<String> trailLocalPhotos,
  required Map<String, List<String>> waypointLocalPhotosByKey,
}) {
  final result = legacy.saveNewLocalTrail(
    store,
    trail: trail,
    ownerAccountId: ownerAccountId,
    authorActorId: authorActorId,
    localId: localId,
    trailLocalPhotos: trailLocalPhotos,
    waypointLocalPhotosByKey: waypointLocalPhotosByKey,
  );

  store.runInTransaction(TxMode.write, () {
    final box = store.box<TrailEntity>();
    final query = box.query(TrailEntity_.localId.equals(localId)).build();
    final entity = query.findFirst();
    query.close();
    if (entity == null) return;

    entity.savedByUserIds = <String>{
      ...entity.savedByUserIds,
      ownerAccountId,
    }.toList(growable: false);
    box.put(entity);
  });

  return result;
}
