// ignore_for_file: public_member_api_docs

/// This example demonstrates working songs on Android, in particular it shows:
///
///  * fetching songs from `MediaStore`
///  * working with content:// URIs
///    * playing songs from URI
///    * showing song arts in [AudioService]
///    * showing song arts in Dart
///
/// Plugins, used in this example, other than `audio_service`:
///
///  * `flutter_audio_query` - for fetching song data
///  * `android_content_provider` - for loading song arts
///  * `device_info_plus` - for detecting Android version
///  * `just_audio` - for playback
///  * `permission_handler` - for asking for permssions to read
///    the device storage
///
/// In Android there are 3 different ways of loading a song art:
///
/// 1. On any Android version:
///   using ContentResolver and art content:// URI - this is what [AudioService] supports
///   out of the box.
///   You can see this being used in [SongInfoExtension.toMediaItem].
///
/// 2. On Android 10 and above only:
///   using [AndroidContentResolver.loadThumbnail] on the song content:// URI in the `MediaStore`,
///   and NOT the art content:// URI.
///   Used in [SongArt] widget.
///
/// 3. On Android 9 and below only:
///   using [SongInfo.albumArtwork], which contains a direct path to the art file, and
///   NOT the art content:// URI.
///   Used in [SongArt] widget.
///
/// The reasons the methods 2 and 3 are even mentioned here are:
///
///  * because they are a more performant way of loading the thumbnails
///    from `MediaStore`
///  * because [AndroidContentResolver] does not support (yet)
///    `ContentResolver.openFileDescriptor`
///
/// To run this example, use:
///
/// flutter run -t lib/example_android_songs.dart --no-sound-null-safety

import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_audio_query/flutter_audio_query.dart';
import 'package:android_content_provider/android_content_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:permission_handler/permission_handler.dart';

// You might want to provide this using dependency injection rather than a
// global variable.
late AudioPlayerHandler _audioHandler;
late int sdkInt;
List<SongInfo>? _songs;

extension SongInfoExtension on SongInfo {
  /// Converts the song info to [AudioService] media item.
  MediaItem toMediaItem() => MediaItem(
        id: id,
        album: album,
        artist: artist,
        title: title,
        // The direct art content:// URI.
        artUri: Uri.parse('content://media/external/audio/media/$id/albumart'),
      );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
  sdkInt = androidInfo.version.sdkInt!;

  _audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ryanheise.myapp.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Service Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  PermissionStatus? _permissionStatus;

  @override
  void initState() {
    super.initState();
    _fetchSongs();
  }

  Future<void> _fetchSongs() async {
    setState(() {
      _permissionStatus = null;
    });
    _permissionStatus = await Permission.storage.request();
    if (mounted) {
      setState(() {
        // Update to maybe show progress indicator.
      });
    }
    if (_permissionStatus == PermissionStatus.granted) {
      final FlutterAudioQuery audioQuery = FlutterAudioQuery();
      _songs = await audioQuery.getSongs();
      if (_songs!.isNotEmpty) {
        _audioHandler.init();
      }
    } else if (_permissionStatus == PermissionStatus.permanentlyDenied) {
      await openAppSettings();
    }
    if (mounted) {
      setState(() {
        // Update to show the fetch result.
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (_permissionStatus == null) {
      child = const Scaffold();
    } else if (_permissionStatus != PermissionStatus.granted) {
      child = Scaffold(
        body: Center(
          child: ElevatedButton(
            child: const Text('Grant storage permissions'),
            onPressed: _fetchSongs,
          ),
        ),
      );
    } else if (_permissionStatus == PermissionStatus.granted &&
        _songs == null) {
      child = const Center(
        child: CircularProgressIndicator(),
      );
    } else if (_songs != null && _songs!.isEmpty) {
      child = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('There is no music on your device'),
            ElevatedButton(
              child: const Text('Refetch'),
              onPressed: _fetchSongs,
            ),
          ],
        ),
      );
    } else {
      child = const SongListScreen();
    }
    return Scaffold(
      body: child,
    );
  }
}

class SongListScreen extends StatelessWidget {
  const SongListScreen({Key? key}) : super(key: key);

  IconButton _button(IconData iconData, VoidCallback onPressed) => IconButton(
        icon: Icon(iconData),
        onPressed: onPressed,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Service Demo'),
      ),
      bottomNavigationBar: Material(
        color: Colors.white,
        elevation: 12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildControls(),
            _buildCurrentSong(),
          ],
        ),
      ),
      body: ListView.builder(
        itemCount: _songs!.length,
        itemBuilder: (context, index) {
          final song = _songs![index];
          return SongTile(song: song);
        },
      ),
    );
  }

  Widget _buildControls() {
    return StreamBuilder<bool>(
      stream:
          _audioHandler.playbackState.map((state) => state.playing).distinct(),
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _button(Icons.skip_previous, _audioHandler.skipToPrevious),
            if (playing)
              _button(Icons.pause, _audioHandler.pause)
            else
              _button(Icons.play_arrow, _audioHandler.play),
            _button(Icons.stop, _audioHandler.stop),
            _button(Icons.skip_next, _audioHandler.skipToNext),
          ],
        );
      },
    );
  }

  Widget _buildCurrentSong() {
    return StreamBuilder<SongInfo?>(
      stream: _audioHandler.currentSong,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox();
        }
        final song = snapshot.data!;
        return SongTile(
          song: song,
          tappable: false,
        );
      },
    );
  }
}

class SongTile extends StatelessWidget {
  const SongTile({
    Key? key,
    required this.song,
    this.tappable = true,
  }) : super(key: key);

  final SongInfo song;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(song.title),
      subtitle: Text(song.artist),
      leading: SongArt(song: song),
      onTap: !tappable
          ? null
          : () {
              _audioHandler.setSong(song);
              _audioHandler.play();
            },
    );
  }
}

/// Shows local song art from Android `MediaStore`.
///
/// On Android 10 and above album arts should be fetched with
/// a special method [AndroidContentResolver.loadThumbnail].
///
/// Lower Android 10 album arts ared displayed directly from the file path
/// of album art from [SongInfo.albumArtwork] (which was removed in Android 10).
///
/// See the comment at the top of the example for the full context.
class SongArt extends StatefulWidget {
  const SongArt({Key? key, required this.song}) : super(key: key);

  final SongInfo song;

  @override
  State<SongArt> createState() => _SongArtState();
}

class _SongArtState extends State<SongArt> {
  CancellationSignal? _loadSignal;
  Uint8List? _bytes;
  bool loaded = false;

  static const int _artSize = 60;

  /// Whether running on scoped storage (Android 10 and above),
  /// and should use bytes to load album arts from `MediaStore`.
  bool get _useScopedStorage => sdkInt >= 29;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_useScopedStorage) {
      _fetchArt();
    }
  }

  @override
  void didUpdateWidget(covariant SongArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.song.id != oldWidget.song.id) {
      _fetchArt();
    }
  }

  int getCacheSize() {
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    return (_artSize * devicePixelRatio).toInt();
  }

  Future<void> _fetchArt() async {
    _loadSignal?.cancel();
    _loadSignal = CancellationSignal();
    final cacheSize = getCacheSize();
    _bytes = await AndroidContentResolver.instance.loadThumbnail(
      uri: widget.song.uri,
      width: cacheSize,
      height: cacheSize,
      cancellationSignal: _loadSignal,
    );
    if (mounted) {
      setState(() {
        loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _loadSignal?.cancel();
    super.dispose();
  }

  Widget _buildPlaceholder() => Container(
        color: Colors.blue,
        child: const Icon(
          Icons.music_note,
          color: Colors.white,
          size: _artSize / 1.5,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (_useScopedStorage) {
      final cacheSize = getCacheSize();
      child = !loaded
          ? SizedBox.square(dimension: _artSize.toDouble())
          : _bytes == null
              ? _buildPlaceholder()
              : Image.memory(
                  _bytes!,
                  cacheHeight: cacheSize,
                  cacheWidth: cacheSize,
                );
    } else {
      final artPath = widget.song.albumArtwork;
      var file = artPath == null ? null : File(artPath);
      if (artPath == null || !file!.existsSync()) {
        child = _buildPlaceholder();
      } else {
        final cacheSize = getCacheSize();
        child = Image.file(
          file,
          cacheHeight: cacheSize,
          cacheWidth: cacheSize,
        );
      }
    }
    return SizedBox.square(
      dimension: _artSize.toDouble(),
      child: child,
    );
  }
}

class AudioPlayerHandler extends BaseAudioHandler with QueueHandler {
  final _player = AudioPlayer();
  final currentSong = BehaviorSubject<SongInfo>();

  void init() {
    // Propagate all events from the audio player to AudioService clients.
    _player.playbackEventStream.listen(_broadcastState);
    // Put the songs into queue.
    queue.add(_songs!.map((song) => song.toMediaItem()).toList());
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) skipToNext();
    });

    setSong(_songs!.first);
  }

  Future<void> setSong(SongInfo song) async {
    currentSong.add(song);
    mediaItem.add(song.toMediaItem());
    await _player.setAudioSource(
      ProgressiveAudioSource(Uri.parse(song.uri)),
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await playbackState.firstWhere(
        (state) => state.processingState == AudioProcessingState.idle);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index <= 0 || index >= queue.value.length) {
      // TODO: remove this when QueueHandler._skip is fixed
      return;
    }
    await setSong(_songs![index]);
  }

  /// Broadcasts the current state to all clients.
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final queueIndex = _songs!.indexOf(currentSong.value);
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: queueIndex,
    ));
  }
}
