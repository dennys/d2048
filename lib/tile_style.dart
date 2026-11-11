import 'package:flutter/material.dart';

/// 方塊配色（game board 與快照 mini 預覽共用）。
Color tileColor(int value) {
  switch (value) {
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
      // 4096 以上：四檔紅循環，高方塊可分辨
      return [Colors.red[400]!, Colors.red[500]!, Colors.red[600]!, Colors.red[700]!][(value ~/ 2048) % 4];
  }
}

Color tileTextColor(int value) => value <= 4 ? Colors.grey[800]! : Colors.white;