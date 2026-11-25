import 'package:ism_video_reel_player/core/core.dart';
import 'package:ism_video_reel_player/domain/domain.dart';
import 'package:ism_video_reel_player/utils/utils.dart';

class SavePostUseCase extends BaseUseCase {
  SavePostUseCase(this._repository);

  final SocialRepository _repository;

  Future<ApiResult<ResponseClass?>> executeSavePost({
    required bool isLoading,
    required String postId,
    required SocialPostAction socialPostAction,
  }) async =>
      await super.execute(() async {
        final response = await _repository.savePost(
          isLoading: isLoading,
          postId: postId,
          socialPostAction: socialPostAction,
        );
        final statusCode = response.responseCode;
        final ok = statusCode == 200 || statusCode == 201;
        return ApiResult(
          data: ok ? response.data : null,
          statusCode: statusCode,
        );
      });

  Future<ApiResult<TimelineResponse?>> executeGetProfileSavedPostData({
    required bool isLoading,
    required int page,
    required int pageSize,
    String collectionId = '',
  }) async =>
      await super.execute(() async {
        final response = await _repository.getProfileSavedPostData(
          isLoading: isLoading,
          page: page,
          pageSize: pageSize,
          collectionId: collectionId,
        );
        return ApiResult(
            data: response.responseCode == 200 && response.responseCode != 204
                ? response.data
                : null);
      });
}
