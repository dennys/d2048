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
    List<List<int>> oldBoard = List.generate(
      4,
      (i) => List.generate(4, (j) => board[i][j]),
    );
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

    if (moved) {
      _addRandomTile();

      if (!_canMove()) {
        gameOver = true;
      }
    }

    return moved;
  }

  bool _moveLeft() {
    bool moved = false;

    for (int i = 0; i < 4; i++) {
      List<int> row = board[i].toList();
      List<int> newRow = _compressAndMerge(row);

      if (!_listsEqual(row, newRow)) {
        moved = true;
      }

      board[i] = newRow;
    }

    return moved;
  }

  bool _moveRight() {
    bool moved = false;

    for (int i = 0; i < 4; i++) {
      List<int> row = board[i].toList();
      row = row.reversed.toList();
      List<int> newRow = _compressAndMerge(row);
      newRow = newRow.reversed.toList();

      if (!_listsEqual(row.reversed.toList(), newRow)) {
        moved = true;
      }

      board[i] = newRow;
    }

    return moved;
  }

  bool _moveUp() {
    bool moved = false;

    for (int j = 0; j < 4; j++) {
      List<int> col = [board[0][j], board[1][j], board[2][j], board[3][j]];
      List<int> newCol = _compressAndMerge(col);

      if (!_listsEqual(col, newCol)) {
        moved = true;

        for (int i = 0; i < 4; i++) {
          board[i][j] = newCol[i];
        }
      }
    }

    return moved;
  }

  bool _moveDown() {
    bool moved = false;

    for (int j = 0; j < 4; j++) {
      List<int> col = [board[0][j], board[1][j], board[2][j], board[3][j]];
      col = col.reversed.toList();
      List<int> newCol = _compressAndMerge(col);
      newCol = newCol.reversed.toList();

      if (!_listsEqual(col.reversed.toList(), newCol)) {
        moved = true;

        for (int i = 0; i < 4; i++) {
          board[i][j] = newCol[i];
        }
      }
    }

    return moved;
  }

  List<int> _compressAndMerge(List<int> line) {
    // Remove zeros (compress)
    List<int> nonZeros = line.where((value) => value != 0).toList();

    // Merge adjacent equal values
    for (int i = 0; i < nonZeros.length - 1; i++) {
      if (nonZeros[i] == nonZeros[i + 1]) {
        nonZeros[i] *= 2;
        score += nonZeros[i];
        nonZeros[i + 1] = 0;
      }
    }

    // Remove zeros again after merging
    nonZeros = nonZeros.where((value) => value != 0).toList();

    // Fill the remaining spaces with zeros
    while (nonZeros.length < 4) {
      nonZeros.add(0);
    }

    return nonZeros;
  }

  bool _listsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
            ),

            // Game board
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: GestureDetector(
                    onVerticalDragEnd: (details) {
                      if (details.velocity.pixelsPerSecond.dy < 0) {
                        // Swiped up
                        if (!gameOver) {
                          setState(() {
                            _move(Direction.up);
                          });
                        }
                      } else if (details.velocity.pixelsPerSecond.dy > 0) {
                        // Swiped down
                        if (!gameOver) {
                          setState(() {
                            _move(Direction.down);
                          });
                        }
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      if (details.velocity.pixelsPerSecond.dx < 0) {
                        // Swiped left
                        if (!gameOver) {
                          setState(() {
                            _move(Direction.left);
                          });
                        }
                      } else if (details.velocity.pixelsPerSecond.dx > 0) {
                        // Swiped right
                        if (!gameOver) {
                          setState(() {
                            _move(Direction.right);
                          });
                        }
                      }
                    },
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
