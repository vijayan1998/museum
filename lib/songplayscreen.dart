import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Neumorphism color palette. Every soft/extruded element is drawn on top of
/// [kBackground] using a light shadow (top-left) and a dark shadow (bottom-right).
const Color kBackground = Color(0xFFE0E5EC);
const Color kLightShadow = Color(0xFFFFFFFF);
const Color kDarkShadow = Color(0xFFA3B1C6);
const Color kAccent = Color(0xFF5B7CFA);
const Color kText = Color(0xFF4A5568);

/// A single track in the playlist.
class Song {
  const Song({required this.title, required this.artist, required this.url});

  final String title;
  final String artist;
  final String url;
}

class SongplayScreen extends StatefulWidget {
  const SongplayScreen({super.key});

  @override
  State<SongplayScreen> createState() => _SongplayScreenState();
}

class _SongplayScreenState extends State<SongplayScreen> {
  final AudioPlayer _player = AudioPlayer();

  // Demo playlist — streamed from the network so the screen works out of the
  // box. Swap the urls for AssetSource paths to play bundled files.
  static const List<Song> _playlist = [
    Song(
      title: 'Midnight Serenade',
      artist: 'SoundHelix',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    ),
    Song(
      title: 'Electric Dreams',
      artist: 'SoundHelix',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    ),
    Song(
      title: 'Neon Skyline',
      artist: 'SoundHelix',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    ),
  ];

  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  Song get _currentSong => _playlist[_currentIndex];

  @override
  void initState() {
    super.initState();
    _player.setSourceUrl(_currentSong.url);

    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    // Auto-advance to the next track when the current one finishes.
    _player.onPlayerComplete.listen((_) {
      if (mounted) _playNext();
    });
  }

  /// Load the track at [index] (wrapping around the playlist) and start it.
  Future<void> _playAt(int index) async {
    final next = (index + _playlist.length) % _playlist.length;
    await _player.stop();
    setState(() {
      _currentIndex = next;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    await _player.play(UrlSource(_currentSong.url));
  }

  Future<void> _playNext() => _playAt(_currentIndex + 1);

  /// Restart the current track if we're past the first few seconds, otherwise
  /// jump to the previous one.
  Future<void> _playPrevious() {
    if (_position > const Duration(seconds: 3)) {
      _player.seek(Duration.zero);
      return _player.resume();
    }
    return _playAt(_currentIndex - 1);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  /// Seek relative to the current position, clamped to the track bounds.
  Future<void> _seekBy(Duration offset) async {
    var target = _position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (_duration != Duration.zero && target > _duration) target = _duration;
    await _player.seek(target);
    setState(() => _position = target);
  }

  String _formatTime(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final maxMillis = _duration.inMilliseconds == 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final currentMillis = _position.inMilliseconds
        .clamp(0, maxMillis.toInt())
        .toDouble();

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            // Album art scales with the smaller of the available width/height so
            // it never overflows a short phone in landscape yet grows nicely on
            // a tablet. Clamped to a sensible range.
            final artSize = math
                .min(width * 0.62, height * 0.34)
                .clamp(150.0, 300.0);
            final horizontalPadding = width >= 640 ? 40.0 : 28.0;

            return Center(
              child: ConstrainedBox(
                // Keep the player a comfortable width on tablets / desktop
                // instead of stretching edge to edge.
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      _buildTopBar(),
                      const Spacer(),
                      _buildAlbumArt(artSize),
                      SizedBox(height: artSize * 0.18),
                      Text(
                        _currentSong.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: kText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentSong.artist,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: kText.withValues(alpha: 0.6),
                        ),
                      ),
                      const Spacer(),
                      _buildProgressBar(currentMillis, maxMillis),
                      const SizedBox(height: 32),
                      _buildControls(),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _NeuButton(
          size: 48,
          borderRadius: 14,
          icon: Icons.arrow_back_ios_new,
          iconSize: 18,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const Text(
          'NOW PLAYING',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
            color: kText,
          ),
        ),
        _NeuButton(
          size: 48,
          borderRadius: 14,
          icon: Icons.favorite_border,
          iconSize: 20,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildAlbumArt(double size) {
    final inner = size - 10;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kBackground,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: kDarkShadow, offset: Offset(14, 14), blurRadius: 28),
          BoxShadow(
            color: kLightShadow,
            offset: Offset(-14, -14),
            blurRadius: 28,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: inner,
          height: inner,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: kBackground,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: kDarkShadow,
                offset: Offset(-6, -6),
                blurRadius: 12,
              ),
              BoxShadow(
                color: kLightShadow,
                offset: Offset(6, 6),
                blurRadius: 12,
              ),
            ],
          ),
          child: SizedBox(
            width: 100,
            height: 60,
            child: _PlayingWave(isPlaying: _isPlaying),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(double currentMillis, double maxMillis) {
    return Column(
      children: [
        _NeuLinearProgress(
          progress: maxMillis == 0 ? 0 : currentMillis / maxMillis,
          onSeek: (fraction) {
            final target = Duration(
              milliseconds: (maxMillis * fraction).toInt(),
            );
            _player.seek(target);
            setState(() => _position = target);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatTime(_position),
                style: TextStyle(
                  color: kText.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              Text(
                _formatTime(_duration),
                style: TextStyle(
                  color: kText.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    // The buttons have fixed sizes; on the narrowest phones their combined
    // width can exceed the row, so a FittedBox scales the whole cluster down
    // to fit while keeping it centred and full-size on larger screens.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Previous track.
          _NeuButton(
            size: 52,
            borderRadius: 18,
            icon: Icons.skip_previous,
            iconSize: 26,
            onTap: _playPrevious,
          ),
          const SizedBox(width: 14),
          // Backward 10 seconds.
          _NeuButton(
            size: 56,
            borderRadius: 20,
            icon: Icons.replay_10,
            iconSize: 24,
            onTap: () => _seekBy(const Duration(seconds: -10)),
          ),
          const SizedBox(width: 14),
          // Play / pause.
          _NeuButton(
            size: 76,
            borderRadius: 28,
            icon: _isPlaying ? Icons.pause : Icons.play_arrow,
            iconSize: 38,
            iconColor: kAccent,
            onTap: _togglePlay,
          ),
          const SizedBox(width: 14),
          // Forward 10 seconds.
          _NeuButton(
            size: 56,
            borderRadius: 20,
            icon: Icons.forward_10,
            iconSize: 24,
            onTap: () => _seekBy(const Duration(seconds: 10)),
          ),
          const SizedBox(width: 14),
          // Next track.
          _NeuButton(
            size: 52,
            borderRadius: 18,
            icon: Icons.skip_next,
            iconSize: 26,
            onTap: _playNext,
          ),
        ],
      ),
    );
  }
}

/// A tappable neumorphic button. Extruded (raised) in its resting state and
/// pressed (inset-looking) while held, by swapping the shadow direction.
class _NeuButton extends StatefulWidget {
  const _NeuButton({
    required this.size,
    required this.borderRadius,
    required this.icon,
    required this.onTap,
    this.iconSize = 24,
    this.iconColor = kText,
  });

  final double size;
  final double borderRadius;
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  State<_NeuButton> createState() => _NeuButtonState();
}

class _NeuButtonState extends State<_NeuButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: _pressed
              ? const [
                  // Pressed: shadows tucked inward for an inset feel.
                  BoxShadow(
                    color: kDarkShadow,
                    offset: Offset(3, 3),
                    blurRadius: 6,
                  ),
                  BoxShadow(
                    color: kLightShadow,
                    offset: Offset(-3, -3),
                    blurRadius: 6,
                  ),
                ]
              : const [
                  // Resting: raised off the surface.
                  BoxShadow(
                    color: kDarkShadow,
                    offset: Offset(6, 6),
                    blurRadius: 12,
                  ),
                  BoxShadow(
                    color: kLightShadow,
                    offset: Offset(-6, -6),
                    blurRadius: 12,
                  ),
                ],
        ),
        child: Icon(
          widget.icon,
          size: widget.iconSize,
          color: widget.iconColor,
        ),
      ),
    );
  }
}

/// An animated equalizer-style waveform. The bars ripple continuously while
/// [isPlaying] is true and rest flat when paused.
class _PlayingWave extends StatefulWidget {
  const _PlayingWave({required this.isPlaying});

  final bool isPlaying;

  @override
  State<_PlayingWave> createState() => _PlayingWaveState();
}

class _PlayingWaveState extends State<_PlayingWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(_PlayingWave old) {
    super.didUpdateWidget(old);
    // Start / stop the ripple as playback state changes.
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _PlayingWavePainter(
            phase: _controller.value,
            playing: widget.isPlaying,
          ),
        );
      },
    );
  }
}

class _PlayingWavePainter extends CustomPainter {
  _PlayingWavePainter({required this.phase, required this.playing});

  /// Animation progress, 0..1, looping.
  final double phase;
  final bool playing;

  static const int _barCount = 9;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 6.0;
    final barWidth = (size.width - gap * (_barCount - 1)) / _barCount;
    final centerY = size.height / 2;
    final paint = Paint()
      ..color = kAccent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < _barCount; i++) {
      final x = i * (barWidth + gap) + barWidth / 2;
      // Each bar is offset in phase so the row ripples like an equalizer.
      final wave = math.sin((phase * 2 * math.pi) + i * 0.7);
      // Rest at a small flat height when paused.
      final amplitude = playing ? (0.35 + 0.65 * (wave * 0.5 + 0.5)) : 0.22;
      final h = amplitude * size.height;
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlayingWavePainter old) =>
      old.phase != phase || old.playing != playing;
}

/// A neumorphic linear progress bar. The track sits recessed into the surface
/// (a soft groove), the played portion is filled with the accent colour, and a
/// raised knob marks the playhead. Tap or drag anywhere to seek.
class _NeuLinearProgress extends StatelessWidget {
  const _NeuLinearProgress({required this.progress, required this.onSeek});

  /// Playback position as a fraction of the track length (0..1).
  final double progress;

  /// Called with the seek target as a fraction (0..1) on tap / drag.
  final ValueChanged<double> onSeek;

  static const double _trackHeight = 14;
  static const double _thumbSize = 26;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    return SizedBox(
      height: _thumbSize,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          void handle(double dx) => onSeek((dx / width).clamp(0.0, 1.0));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => handle(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => handle(d.localPosition.dx),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Recessed groove — the gradient fakes an inset (top-left dark,
                // bottom-right light) since Flutter has no inner box shadow.
                Container(
                  height: _trackHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_trackHeight / 2),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [kDarkShadow, kBackground],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: kLightShadow,
                        offset: Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
                // Accent fill up to the current position.
                Container(
                  height: _trackHeight,
                  width: (width * p).clamp(_trackHeight, width),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_trackHeight / 2),
                    gradient: LinearGradient(
                      colors: [kAccent.withValues(alpha: 0.75), kAccent],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kAccent.withValues(alpha: 0.35),
                        offset: const Offset(0, 2),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                // Raised neumorphic knob at the playhead.
                Positioned(
                  left: ((width - _thumbSize) * p).clamp(
                    0.0,
                    width - _thumbSize,
                  ),
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: const BoxDecoration(
                      color: kBackground,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kDarkShadow,
                          offset: Offset(3, 3),
                          blurRadius: 6,
                        ),
                        BoxShadow(
                          color: kLightShadow,
                          offset: Offset(-3, -3),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: kAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
