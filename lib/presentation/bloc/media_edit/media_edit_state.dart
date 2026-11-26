part of 'media_edit_bloc.dart';

abstract class MediaEditState {}

class MediaEditInitialState extends MediaEditState {
  MediaEditInitialState({this.isLoading = true});

  final bool isLoading;
}

class MediaEditLoadedState extends MediaEditState {
  MediaEditLoadedState({
    required this.mediaEditItems,
    required this.currentIndex,
    this.isApplyingSound = false,
    this.isProcessingNext = false,
  });

  final List<MediaEditItem> mediaEditItems;
  final int currentIndex;
  final bool isApplyingSound;

  /// Mux / finalize before opening the post screen.
  final bool isProcessingNext;
}

class MediaEditErrorState extends MediaEditState {
  MediaEditErrorState({required this.message});

  final String message;
}

class MediaEditCompletedState extends MediaEditState {
  MediaEditCompletedState({required this.mediaEditItems});

  final List<MediaEditItem> mediaEditItems;
}

class MediaEditEmptyState extends MediaEditState {}
