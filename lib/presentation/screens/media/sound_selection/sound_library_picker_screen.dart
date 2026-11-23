import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/model/media_edit_audio_model.dart';
import 'package:ism_video_reel_player/presentation/screens/media/sound_selection/sound_selection_api_body.dart';
/// Opens the live sounds library and returns a [MediaEditSoundItem]
/// (media edit / gallery flow).
class SoundLibraryPickerScreen extends StatelessWidget {
  const SoundLibraryPickerScreen({super.key});

  static Future<MediaEditSoundItem?> show(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push<MediaEditSoundItem>(
        MaterialPageRoute(
          builder: (_) => const SoundLibraryPickerScreen(),
        ),
      );

  @override
  Widget build(BuildContext context) => SoundSelectionApiBody(
        // Non-null enables create-post flow: confirm + start picker, then pop.
        onTrackSelected: (_) {},
      );
}
