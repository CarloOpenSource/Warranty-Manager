use strict;
use warnings;

my $path = "lib/Screens/edit_screen.dart";
open(my $fh, "<:encoding(UTF-8)", $path) or die $!;
my @lines = <$fh>;
close $fh;

# Find _applyCrop method start
my $start = -1;
for my $i (0..$#lines) {
    if ($lines[$i] =~ m{^\s+void _applyCrop\(\) async \{}) {
        $start = $i;
        last;
    }
}
die "start not found" if $start < 0;

# Find matching closing brace
my $end = -1;
my $brace_count = 0;
for my $i ($start..$#lines) {
    $brace_count += ($lines[$i] =~ tr/{/{/);
    $brace_count -= ($lines[$i] =~ tr/}/}/);
    if ($brace_count == 0) {
        $end = $i;
        last;
    }
}
die "end not found" if $end < 0;
print "applyCrop start=$start end=$end\n";

my @new = (
"  void _applyCrop() async {\n",
"    if (_imgWidth == 0 || _imgHeight == 0 || _croppingInProgress) return;\n",
"\n",
"    setState(() {\n",
"      _croppingInProgress = true;\n",
"    });\n",
"\n",
"    try {\n",
"      // Berechne Skalierungsfaktor: Bild -> Bildschirm\n",
"      final screenWidth = MediaQuery.of(context).size.width;\n",
"      final screenHeight = MediaQuery.of(context).size.height;\n",
"      final scaleX = screenWidth / _imgWidth;\n",
"      final scaleY = screenHeight / _imgHeight;\n",
"      final scale = math.min(scaleX, scaleY);\n",
"\n",
"      final x = (_cropRect.left / scale).floor().clamp(0, _imgWidth);\n",
"      final y = (_cropRect.top / scale).floor().clamp(0, _imgHeight);\n",
"      final w = (_cropRect.width / scale).floor().clamp(1, _imgWidth - x);\n",
"      final h = (_cropRect.height / scale).floor().clamp(1, _imgHeight - y);\n",
"\n",
"      // Als neue Datei speichern\n",
"      final savedPath = await _cropHelper.cropFile(\n",
"        quelle: widget.originalPath,\n",
"        crop: Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),\n",
"      );\n",
"\n",
"      if (mounted) {\n",
"        Navigator.pop(context, savedPath);\n",
"      }\n",
"    } catch (e) {\n",
"      if (mounted) {\n",
"        ScaffoldMessenger.of(context).showSnackbar(\n",
"          Snack(content: Text('Fehler beim Zuschneiden: \$e')),\n",
"        );\n",
"        setState(() {\n",
"          _croppingInProgress = false;\n",
"        });\n",
"      }\n",
"    }\n",
"  }\n",
"\n",
"  void _restoreOriginal() {\n",
"    setState(() {\n",
"      _brightness = 1.0;\n",
"      _contrast = 1.0;\n",
"      _saturation = 1.0;\n",
"      _rotation = 0;\n",
"      _cropRect = Rect.zero;\n",
"    });\n",
"    _applyImageSettings();\n",
"  }\n",
);

splice(@lines, $start, $end - $start + 1, @new);

open(my $out, ">:encoding(UTF-8)", $path) or die $!;
print $out @lines;
close $out;
print "done 2\n";