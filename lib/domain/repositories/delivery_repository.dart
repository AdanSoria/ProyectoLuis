import '../../core/utils/result.dart';
import '../entities/delivery_person.dart';

abstract class DeliveryRepository {
  Future<List<DeliveryPerson>> getActive();

  Future<Result<DeliveryPerson>> save(
    DeliveryPerson person, {
    required bool isNew,
  });
}
