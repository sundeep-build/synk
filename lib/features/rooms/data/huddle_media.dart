import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/logging/app_logger.dart';

/// The phone's own microphone and camera during a huddle, and the audio
/// routing that lets voices play over the room's music.
///
/// The camera is opened only while it's on and fully released when turned
/// off (capture, encoder and preview memory), not just muted.
class HuddleMedia {
  /// Holds the mic track. Its id is also the stream id peers file our audio
  /// and video under, so the camera can come and go without renegotiating.
  MediaStream? _stream;
  MediaStream? _camera;
  bool _front = true;

  /// Audio was switched to call mode and must be handed back on [close].
  bool _routed = false;

  MediaStream? get stream => _stream;
  MediaStreamTrack? get audioTrack => _stream?.getAudioTracks().firstOrNull;

  /// Local preview (self view). Null while the camera is off.
  MediaStream? get cameraStream => _camera;
  MediaStreamTrack? get videoTrack => _camera?.getVideoTracks().firstOrNull;
  bool get frontCamera => _front;

  /// Routes audio for talking and opens the mic (this shows the permission
  /// prompt the first time).
  Future<void> open({required bool mic}) async {
    _routed = true;
    await _routeForCall();
    _stream = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
      'video': false,
    });
    setMic(mic);
  }

  /// Muting sends silence, which Opus DTX shrinks to almost nothing.
  void setMic(bool on) {
    audioTrack?.enabled = on;
  }

  /// 640×480 is the ceiling: tiles are small, and each peer gets its own
  /// encode (scaled down further as the huddle grows; see HuddleRules).
  Future<MediaStreamTrack> openCamera() async {
    final existing = videoTrack;
    if (existing != null) return existing;
    _camera = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {'facingMode': _front ? 'user' : 'environment', 'width': 640, 'height': 480, 'frameRate': 24},
    });
    return videoTrack!;
  }

  Future<void> closeCamera() async {
    final camera = _camera;
    _camera = null;
    if (camera == null) return;
    for (final t in camera.getTracks()) {
      await t.stop();
    }
    await camera.dispose();
  }

  Future<void> flipCamera() async {
    final track = videoTrack;
    if (track == null) return;
    await Helper.switchCamera(track);
    _front = !_front;
  }

  Future<void> setSpeaker(bool on) => Helper.setSpeakerphoneOn(on);

  /// Releases the mic and camera and gives the audio back to the music player.
  Future<void> close() async {
    await closeCamera();
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final t in stream.getTracks()) {
        await t.stop();
      }
      await stream.dispose();
    }
    // Also when a leave raced the mic opening: getUserMedia switched modes.
    if (_routed || stream != null) {
      _routed = false;
      await _routeForMusic();
    }
  }

  Future<void> _routeForCall() async {
    if (WebRTC.platformIsAndroid) {
      await Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration(
          // Taking audio focus would pause the room's radio (just_audio gives
          // focus up on request). Voices mix over the music instead.
          manageAudioFocus: false,
          // Communication mode switches on the phone's echo canceller.
          androidAudioMode: AndroidAudioMode.inCommunication,
          androidAudioFocusMode: AndroidAudioFocusMode.gain,
          androidAudioStreamType: AndroidAudioStreamType.voiceCall,
          androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.voiceCommunication,
          androidAudioAttributesContentType: AndroidAudioAttributesContentType.speech,
        ),
      );
    } else if (WebRTC.platformIsIOS) {
      await Helper.setAppleAudioConfiguration(
        AppleAudioConfiguration(
          appleAudioCategory: AppleAudioCategory.playAndRecord,
          appleAudioCategoryOptions: {
            AppleAudioCategoryOption.defaultToSpeaker,
            AppleAudioCategoryOption.allowBluetooth,
            AppleAudioCategoryOption.allowBluetoothA2DP,
          },
          // Video chat mode: loudspeaker by default, like a group call.
          appleAudioMode: AppleAudioMode.videoChat,
        ),
      );
    }
  }

  Future<void> _routeForMusic() async {
    try {
      if (WebRTC.platformIsAndroid) {
        // The plugin puts the phone back in normal audio mode only when its
        // last peer connection is disposed. A huddle nobody else joined never
        // made one, so dispose a throwaway connection to trigger it.
        final pc = await createPeerConnection({});
        await pc.close();
        await pc.dispose();
      } else if (WebRTC.platformIsIOS) {
        // Back to the app's music session (bootstrap.dart), which the call's
        // record category replaced.
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
        await session.setActive(true);
      }
    } catch (e, st) {
      AppLogger.error('HuddleAudio', e, st);
    }
  }
}
