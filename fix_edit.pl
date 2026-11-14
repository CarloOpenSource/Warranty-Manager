use strict;
use warnings;

my $path = "lib/Screens/edit_screen.dart";
open(my $fh, "<:encoding(UTF-8)", $path) or die $!;
my @lines = <$fh>;
close $fh;

# Find _loadImage method start
my $start = -1;
for my $i (0..$#lines) {
    if ($lines[$i] =~ m{^\s+Future<void> _loadImage\(\) async \{}) {
        $start = $i;
        last;
    }
}
die "start not found" if $start < 0;

# Find matching closing brace (first line that is exactly "  }" after start)
my $end = -1;
for my $i ($start+1..$#lines) {
    if ($lines[$i] =~ m{^  \}\s*$}) {
        $end = $i;
        last;
    }
}
die "end not found" if $end < 0;
print "start=$start end=$end\n";

my @new = (
"  Future<void> _loadImage() async {\n",
"    setState(() {\n",
"      _isLoading = true;\n",
"    });\n",
"\n",
"    try {\n",
"      final bytes = await File(widget.imageDataPath).readAsBytes();\n",
"      final result = await Isolate.run(_decodeAndPrepare, bytes);\n",
"      _originalBytes = result.bytes;\n",
"      _displayBytes = result.displayBytes;\n",
"      _imgWidth = result.width;\n",
"      _imgHeight = result.height;\n",
"      _setCropRectForDisplay();\n",
"    } catch (e) {\n",
"      if (mounted) {\n",
"        ScaffoldMessenger.of(context).showSnackbar(\n",
"          Snack(content: Text(\"Fehler beim Laden des Bildes: \$e\")),\n",
"        );\n",
"        Navigator.pop(context);\n",
"      }\n",
"    }\n",
"\n",
"    if (mounted) {\n",
"      setState(() {\n",
"        _isLoading = false;\n",
"      });\n",
"    }\n",
"  }\n",
"\n",
"  /// Berechnet den Crop-Bereich (in Bildschirm-Koordinaten) für das geladene Bild.\n",
"  void _setCropRectForDisplay() {\n",
"    if (_imgWidth == 0 || _imgHeight == 0) return;\n",
"    final screenWidth = MediaQuery.of(context).size.width;\n",
"    final screenHeight = MediaQuery.of(context).size.height;\n",
"    final scale = math.min(screenWidth / _imgWidth, screenHeight / _imgHeight);\n",
"    final scaledWidth = _imgWidth * scale;\n",
"    final scaledHeight = _imgHeight * scale;\n",
"    _cropRect = Rect.fromLTWH(\n",
"      (screenWidth - scaledWidth) / 2,\n",
"      (screenHeight - scaledHeight) / 2,\n",
"      scaledWidth,\n",
"      scaledHeight,\n",
"    );\n",
"  }\n",
"\n",
"  /// Wird im Isolate ausgeführt, damit die CPU-intensive Bildverarbeitung\n",
"  /// den Main-Thread nicht blockiert (verhindert das \"App froze\"-Problem).\n",
"  static _ImageResult _decodeAndPrepare(Uint8List bytes) {\n",
"    final img.Image? original = img.decodeImage(bytes);\n",
"    if (original == null) {\n",
"      throw FileSystemException(\"Bild nicht decodierbar\", \"\");\n",
"    }\n",
"\n",
"    // Für die Anzeige als JPEG kodieren (verringert den Speicherverbrauch)\n",
"    final Uint8List displayBytes = Uint8List.fromList(\n",
"      img.encodeJpg(original, quality: 85),\n",
"    );\n",
"\n",
"    return _ImageResult(\n",
"      bytes: displayBytes,\n",
"      width: original.width,\n",
"      height: original.height,\n",
"    );\n",
"  }\n",
);

splice(@lines, $start, $end - $start + 1, @new);

open(my $out, ">:encoding(UTF-8)", $path) or die $!;
print $out @lines;
close $out;
print "done\n";