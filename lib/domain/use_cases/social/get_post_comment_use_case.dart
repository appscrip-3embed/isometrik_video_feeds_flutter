import 'package:ism_video_reel_player/core/core.dart';
import 'package:ism_video_reel_player/domain/domain.dart';

class GetPostCommentUseCase extends BaseUseCase {
  GetPostCommentUseCase(this._repository);

  final SocialRepository _repository;

  Future<ApiResult<CommentsResponse?>> executeGetPostComment({
    required bool isLoading,
    required String postId,
    String? parentCommitId,
    int? page = 1,
    int? pageLimit = 50,
  }) async {
    try {
      final response = await _repository.getPostComments(
        isLoading: isLoading,
        postId: postId,
        parentCommitId: parentCommitId,
        page: page,
        pageLimit: pageLimit,
      );
      return ApiResult(
        data: response.responseCode == 200 ? response.data : null,
        statusCode: response.responseCode,
      );
    } on ApiError catch (e, stackTrace) {
      // A brand-new post often has no comment thread yet. That 404 is not a
      // deleted post; logging it and treating it as failure makes the only
      // post get evicted and the player close.
      if (_isEmptyCommentThread(e)) {
        return ApiResult(
          data: CommentsResponse(data: [], totalComments: 0),
          statusCode: e.statusCode ?? 404,
        );
      }
      final appError = handleError(e, stackTrace);
      return ApiResult(error: appError, statusCode: appError.statusCode);
    } catch (e, stackTrace) {
      final appError = handleError(e, stackTrace);
      return ApiResult(error: appError, statusCode: appError.statusCode);
    }
  }

  /// 404/410 on the comments endpoint is an empty thread until post detail
  /// says otherwise. Callers still see [ApiResult.statusCode] and can confirm.
  bool _isEmptyCommentThread(ApiError error) {
    final code = error.statusCode;
    return code == 404 || code == 410;
  }
}
