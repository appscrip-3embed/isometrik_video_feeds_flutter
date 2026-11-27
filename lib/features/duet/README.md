# Standalone Duet (Instagram-style)

Self-contained duet module for `ism_video_reel_player`. **Do not** wire this into the create-post gallery flow.

## Enable (host)

```dart
IsrVideoReelConfig.setUpConfig(
  postConfig: PostConfig(
    enableDuet: true,
    duetConfig: DuetConfig(
      defaultLayout: DuetLayout.leftRight,
      allowGalleryPick: true,
      maxDurationSeconds: 60,
    ),
  ),
);
```

When enabled, more-options on an existing **video** reel shows **Duet** if `settings.duet_enabled` is not `false`.

## Flow

1. More options → Duet  
2. Layout picker: left-right / top-bottom / PiP  
3. `DuetCaptureView` — original + camera (gallery optional)  
4. `DuetComposer` (FFmpeg, letterbox + black bars, **original audio only**) → single MP4  
5. Existing media editor → post attributes  

## Camera

Front camera opens by default (selfie duet). Live preview is **not** double-mirrored
(no UI `Transform`); platform already mirrors front preview. Front **recordings** set
`userFrontCamera: true` so FFmpeg `hflip` matches that preview in the editor. Gallery
clips are not flipped. Mic off — original reel audio only.

## Reuse

| Piece | Reuse for |
|-------|-----------|
| `DuetCaptureCoordinator.handleFromPost` | Any “start duet from TimeLineData” entry |
| `DuetLayout` / `DuetLayoutGeometry` | Preview + export geometry |
| `DuetStage` | Any split / PiP preview UI |
| `DuetComposer` | Offline compose of two local videos |

## Dependency

`ffmpeg_kit_flutter_new_min` (pinned `3.6.8`) — used only by `DuetComposer` for hstack / vstack / overlay. Segment merge in `MediaUtil` cannot do layouts.
