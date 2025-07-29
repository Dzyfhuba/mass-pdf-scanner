class OCRResult {
  final String text;
  final int left;
  final int top;
  final int width;
  final int height;
  final int right;
  final int bottom;
  final double centerX;
  final double centerY;

  OCRResult({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.right,
    required this.bottom,
    required this.centerX,
    required this.centerY,
  });

  @override
  String toString() =>
      'OCRResult(text: $text, left: $left, top: $top, width: $width, height: $height, right: $right, bottom: $bottom, centerX: $centerX, centerY: $centerY)';
}

extension MergeOCR on OCRResult {
  OCRResult merge(OCRResult other) {
    final l = left < other.left ? left : other.left;
    final t = top < other.top ? top : other.top;
    final r = right > other.right ? right : other.right;
    final b = bottom > other.bottom ? bottom : other.bottom;

    final w = r - l;
    final h = b - t;
    final cx = l + w / 2;
    final cy = t + h / 2;

    return OCRResult(
      text: '$text ${other.text}',
      left: l,
      top: t,
      width: w,
      height: h,
      right: r,
      bottom: b,
      centerX: cx,
      centerY: cy,
    );
  }
}
