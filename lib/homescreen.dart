import 'package:flutter/material.dart';

import 'songplayscreen.dart';

/// A single exhibit / stage in the museum tour.
class Stage {
  const Stage({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // The exhibits shown on the home screen. Swap these for your own content.
  static const List<Stage> _stages = [
    Stage(
      title: 'Ancient Civilizations',
      description:
          'Walk through relics of Egypt, Mesopotamia and the Indus Valley.',
      icon: Icons.account_balance,
    ),
    Stage(
      title: 'Renaissance Art',
      description:
          'Masterpieces from da Vinci to Michelangelo and the age of rebirth.',
      icon: Icons.palette,
    ),
    Stage(
      title: 'Natural History',
      description: 'Fossils, dinosaurs and the story of life across the ages.',
      icon: Icons.pets,
    ),
    Stage(
      title: 'Modern Science',
      description:
          'From steam engines to space travel — inventions that shaped us.',
      icon: Icons.science,
    ),
    Stage(
      title: 'World Cultures',
      description:
          'Textiles, artifacts and traditions from every corner of the globe.',
      icon: Icons.public,
    ),
    Stage(
      title: 'Contemporary Gallery',
      description: 'Bold, experimental works from today\'s leading artists.',
      icon: Icons.brush,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // Responsive layout: a single column on phones, and a grid with
            // more columns as the viewport widens (tablets / desktop). The
            // whole page is also capped and centred on very large screens so
            // the cards never stretch uncomfortably wide.
            final columns = width >= 1100
                ? 3
                : width >= 640
                ? 2
                : 1;
            final horizontalPadding = width >= 640 ? 24.0 : 8.0;
            final isCompact = width < 640;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _buildHeader(isCompact),
                      const SizedBox(height: 24),
                      Expanded(
                        child: columns == 1
                            ? _buildList()
                            : _buildGrid(columns),
                      ),
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

  /// Single-column layout for phones.
  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _stages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (context, index) => _stageCardFor(context, index),
    );
  }

  /// Multi-column grid for tablets and wider screens. Cards size to their
  /// content, so a max-cross-axis-extent grid keeps a comfortable card width
  /// while filling the available space.
  Widget _buildGrid(int columns) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _stages.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        mainAxisExtent: 250,
      ),
      itemBuilder: (context, index) => _stageCardFor(context, index),
    );
  }

  Widget _stageCardFor(BuildContext context, int index) {
    return _StageCard(
      stage: _stages[index],
      index: index,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SongplayScreen()),
      ),
    );
  }

  Widget _buildHeader(bool isCompact) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THE MUSEUM',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                  color: kText.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Explore Exhibits',
                style: TextStyle(
                  fontSize: isCompact ? 28 : 34,
                  fontWeight: FontWeight.w700,
                  color: kText,
                ),
              ),
            ],
          ),
        ),
        // Raised neumorphic menu chip.
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: kBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: kDarkShadow,
                offset: Offset(5, 5),
                blurRadius: 10,
              ),
              BoxShadow(
                color: kLightShadow,
                offset: Offset(-5, -5),
                blurRadius: 10,
              ),
            ],
          ),
          child: const Icon(Icons.museum, color: kAccent, size: 24),
        ),
      ],
    );
  }
}

/// A neumorphic exhibit card: a raised icon badge, a "STAGE NN" eyebrow, the
/// title, a full-width description and a Play Now action.
class _StageCard extends StatelessWidget {
  const _StageCard({
    required this.stage,
    required this.index,
    required this.onTap,
  });

  final Stage stage;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.circular(18),
        // Raised neumorphic surface: light highlight top-left, dark shade
        // bottom-right.
        boxShadow: const [
          BoxShadow(color: kDarkShadow, offset: Offset(4, 4), blurRadius: 8),
          BoxShadow(color: kLightShadow, offset: Offset(-4, -4), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Raised (extruded) icon badge.
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kBackground,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: kDarkShadow,
                      offset: Offset(4, 4),
                      blurRadius: 8,
                    ),
                    BoxShadow(
                      color: kLightShadow,
                      offset: Offset(-4, -4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Icon(stage.icon, color: kAccent, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STAGE ${(index + 1).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: kAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stage.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: kText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            stage.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: kText.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          // Recessed divider groove for depth.
          Container(
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              gradient: const LinearGradient(
                colors: [kDarkShadow, kBackground, kLightShadow],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // "Play Now" button — opens the player screen.
              _PlayNowButton(onTap: onTap),
              // Duration hint chip.
              Row(
                children: [
                  Icon(
                    Icons.headphones,
                    size: 15,
                    color: kText.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Audio guide',
                    style: TextStyle(
                      fontSize: 12,
                      color: kText.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small raised neumorphic "Play Now" button.
class _PlayNowButton extends StatefulWidget {
  const _PlayNowButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_PlayNowButton> createState() => _PlayNowButtonState();
}

class _PlayNowButtonState extends State<_PlayNowButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: kBackground,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _pressed
                ? const [
                    BoxShadow(
                      color: kDarkShadow,
                      offset: Offset(1, 1),
                      blurRadius: 3,
                    ),
                    BoxShadow(
                      color: kLightShadow,
                      offset: Offset(-1, -1),
                      blurRadius: 3,
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: kDarkShadow,
                      offset: Offset(4, 4),
                      blurRadius: 8,
                    ),
                    BoxShadow(
                      color: kLightShadow,
                      offset: Offset(-4, -4),
                      blurRadius: 8,
                    ),
                  ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, color: kAccent, size: 20),
              SizedBox(width: 6),
              Text(
                'Play Now',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
