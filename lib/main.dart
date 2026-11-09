import 'package:flutter/material.dart';
import 'dart:math';

void main() {
  runApp(const Game2048App());
}

class Game2048App extends StatelessWidget {
  const Game2048App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '2048 Game',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // Initialize the board directly instead of using 'late'
  List<List<int>> board = List.generate(4, (_) => List.filled(4, 0));
  int score = 0;
  bool gameOver = false;
  final Random random = Random();
  final List<_Snapshot> history = [];

  List<List<int>> _cloneBoard() =>
      List.generate(4, (i) => List.of(board[i]));

  void _undo() {
    if (history.isEmpty) return;
    final snapshot = history.removeLast();
    board = snapshot.board;
    score = snapshot.score;
    gameOver = false;
  }

  @override
  void initState() {
    super.initState();
    _initializeGame();
  }

  void _initializeGame() {
    // Reset the board with zeros
    board = List.generate(4, (_) => List.filled(4, 0));
    score = 0;
    gameOver = false;
    history.clear();

    // Add two random tiles to start
    _addRandomTile();
    _addRandomTile();
  }

  void _addRandomTile() {
    List<List<int>> emptyPositions = [];

    // Find all empty positions
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (board[i][j] == 0) {
          emptyPositions.add([i, j]);
        }
      }
    }

    if (emptyPositions.isEmpty) return;

    // Select a random empty position
    final position = emptyPositions[random.nextInt(emptyPositions.length)];

    // Set it to 2 (90% chance) or 4 (10% chance)
    board[position[0]][position[1]] = random.nextDouble() < 0.9 ? 2 : 4;
  }

  bool _canMove() {
    // Check if there are any empty cells
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (board[i][j] == 0) return true;
      }
    }

    // Check if there are any adjacent cells with the same value
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 3; j++) {
        if (board[i][j] == board[i][j + 1]) return true;
      }
    }

    for (int j = 0; j < 4; j++) {
      for (int i = 0; i < 3; i++) {
        if (board[i][j] == board[i + 1][j]) return true;
      }
    }

    return false;
  }

  bool _move(Direction direction) {
    history.add(_Snapshot(_cloneBoard(), score));
    bool moved = false;

    switch (direction) {
      case Direction.up:
        moved = _moveUp();
        break;
      case Direction.down:
        moved = _moveDown();
        break;
      case Direction.left:
        moved = _moveLeft();
        break;
      case Direction.right:
        moved = _moveRight();
        break;
    }

    if (!moved) {
      history.removeLast();
      return false;
    }

    _addRandomTile();

    if (!_canMove()) {
      gameOver = true;
    }

    return true;
  }

  /// One handler for both axes: the pan recognizer already picked a direction, so pick
  /// the dominant axis here and let a drag with no speed at all do nothing.
  void _swipe(Velocity velocity) {
    if (gameOver) return;
    final dx = velocity.pixelsPerSecond.dx;
    final dy = velocity.pixelsPerSecond.dy;
    if (dx == 0 && dy == 0) return;
    setState(() => _move(dx.abs() >= dy.abs()
        ? (dx < 0 ? Direction.left : Direction.right)
        : (dy < 0 ? Direction.up : Direction.down)));
  }

  // 四方向只把「取哪份 4 格、有没有反面」不同；把 merge rule 在只一处（原本把四份雨段抄略差一份）
  bool _moveLeft() => _slideRows(false);
  bool _moveRight() => _slideRows(true);
  bool _moveUp() => _slideColumns(false);
  bool _moveDown() => _slideColumns(true);

  bool _slideRows(bool reverse) {
    var moved = false;
    for (var i = 0; i < 4; i++) {
      final merged = _mergeLine(board[i], reverse: reverse);
      for (var j = 0; j < 4; j++) {
        if (board[i][j] != merged[j]) moved = true;
        board[i][j] = merged[j];
      }
    }
    return moved;
  }

  bool _slideColumns(bool reverse) {
    var moved = false;
    for (var j = 0; j < 4; j++) {
      final merged = _mergeLine([for (var i = 0; i < 4; i++) board[i][j]], reverse: reverse);
      for (var i = 0; i < 4; i++) {
        if (board[i][j] != merged[i]) moved = true;
        board[i][j] = merged[i];
      }
    }
    return moved;
  }

  /// Slides one line of 4 cells towards the low index; [reverse] slides it the other way.
  List<int> _mergeLine(List<int> line, {bool reverse = false}) {
    final src = reverse ? line.reversed.toList() : line;
    final nonZeros = src.where((value) => value != 0).toList();
    // 單 merge per pair per move（2,2,4 走左 = 4,4，不是 8,0）
    for (var i = 0; i < nonZeros.length - 1; i++) {
      if (nonZeros[i] == nonZeros[i + 1]) {
        nonZeros[i] *= 2;
        score += nonZeros[i];
        nonZeros[i + 1] = 0;
      }
    }
    final merged = nonZeros.where((value) => value != 0).toList();
    while (merged.length < 4) {
      merged.add(0);
    }
    return reverse ? merged.reversed.toList() : merged;
  }

  Color _getTileColor(int value) {
    switch (value) {
      case 0:
        return Colors.grey[300]!;
      case 2:
        return Colors.grey[50]!;
      case 4:
        return Colors.amber[50]!;
      case 8:
        return Colors.orange[200]!;
      case 16:
        return Colors.orange[300]!;
      case 32:
        return Colors.orange[400]!;
      case 64:
        return Colors.orange[700]!;
      case 128:
        return Colors.amber[400]!;
      case 256:
        return Colors.amber[500]!;
      case 512:
        return Colors.amber[600]!;
      case 1024:
        return Colors.amber[700]!;
      case 2048:
        return Colors.amber[800]!;
      default:
        return Colors.red[400]!;
    }
  }

  Color _getTextColor(int value) {
    return value <= 4 ? Colors.grey[800]! : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('2048 Game'), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            // Score and Reset button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Score: $score',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: history.isEmpty
                            ? null
                            : () => setState(_undo),
                        child: const Text('Undo'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _initializeGame();
                          });
                        },
                        child: const Text('New Game'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Game board
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: GestureDetector(
                    // 斜拖 only counts as one move: the pan recognizer fires BOTH drag-end
                    // callbacks when a gesture has speed on both axes, so the old code ran _move
                    // twice for one diagonal swipe. Pick the dominant axis instead.
                    onVerticalDragEnd: (details) => _swipe(details.velocity),
                    onHorizontalDragEnd: (details) => _swipe(details.velocity),
                    child: Container(
                      margin: const EdgeInsets.all(8.0),
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 1.0,
                              crossAxisSpacing: 8.0,
                              mainAxisSpacing: 8.0,
                            ),
                        itemCount: 16,
                        itemBuilder: (context, index) {
                          final row = index ~/ 4;
                          final col = index % 4;
                          final value = board[row][col];

                          return Container(
                            decoration: BoxDecoration(
                              color: _getTileColor(value),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: Center(
                              child: Text(
                                value > 0 ? value.toString() : '',
                                style: TextStyle(
                                  color: _getTextColor(value),
                                  fontSize: value > 512 ? 20 : 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Game over overlay
            if (gameOver)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                color: Colors.black54,
                child: Column(
                  children: [
                    const Text(
                      'Game Over!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _initializeGame();
                        });
                      },
                      child: const Text('Play Again'),
                    ),
                  ],
                ),
              ),

            // Swipe instructions
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Swipe to move tiles. Merge same numbers to get 2048!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum Direction { up, down, left, right }

class _Snapshot {
  final List<List<int>> board;
  final int score;

  _Snapshot(this.board, this.score);
}
