use strict;
use warnings;

my $path = "lib/Screens/edit_screen.dart";
open(my $fh, "<:encoding(UTF-8)", $path) or die $!;
my @lines = <$fh>;
close $fh;

# Find _applyImageSettings method start
my $start = -1;
for my $i (0..$#lines) {
    if ($lines[$i] =~ m{^\s+void _applyImageSettings\(\) \{}) {
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
print "applyImageSettings start=$start end=$end\n";

my @new = (
"  Future<void> _applyImageSettings() async {\n",
"    if (_originalBytes == null) return;\n",
"\n",
"    try {\n",
"      final result = await Isolate.run(\n",
"        (msg) => _processImage(\n",
"          msg['bytes'] as Uint8List,\n",
"          msg['brightness'] as double,\n",
"          msg['contrast'] as double,\n",
"          msg['saturation'] as double,\n",
"          msg['rotation'] as int,\n",
"        ),\n",
"        {\n",
"          'bytes': _originalBytes!,\n",
"          'brightness': _brightness,\n",
"          'contrast': _contrast,\n",
"          'saturation': _saturation,\n",
"          'rotation': _rotation,\n",
"        },\n",
"      );\n",
"\n",
"      setState(() {\n",
"        _displayBytes = result.displayBytes;\n",
"        _imgWidth = result.width;\n",
"        _imgHeight = result.height;\n",
"      });\n",
"      _setCropRectForDisplay();\n",
"    } catch (e) {\n",
"      if (mounted) {\n",
"        ScaffoldMessenger.of(context).showSnackbar(\n",
"          Snack(content: Text('Fehler bei der Bildbearbeitung: \$e')),\n",
"        );\n",
"      }\n",
"    }\n",
"  }\n",
"\n",
"  static _ImageResult _processImage(\n",
"    Uint8List bytes,\n",
"    double brightness,\n",
"    double contrast,\n",
"    double saturation,\n",
"    int rotation,\n",
"  ) {\n",
"    final img.Image? original = img.decodeImage(bytes);\n",
"    if (original == null) {\n",
"      throw FileSystemException('Bild nicht decodierbar', '');\n",
"    }\n",
"\n",
"    img.Image image = img.Image.from(original);\n",
"\n",
"    // Drehung anwenden (0, 90, -90)\n",
"    if (rotation == 90) {\n",
"      image = img.copyRotate(image, angle: 90);\n",
"    } else if (rotation == -90) {\n",
"      image = img.copyRotate(image, angle: -90);\n",
"    }\n",
"\n",
"    // Helligkeit, Kontrast, Sättigung anwenden\n",
"    image = img.adjustColor(\n",
"      image,\n",
"      brightness: brightness,\n",
"      contrast: contrast,\n",
"      saturation: saturation,\n",
"    );\n",
"\n",
"    // Für die Anzeige als JPEG kodieren (verringert den Speicherverbrauch)\n",
"    final Uint8List displayBytes = Uint8List.fromList(img.encodeJpg(image, quality: 85));\n",
"\n",
"    return _ImageResult(\n",
"      bytes: displayBytes,\n",
"      width: image.width,\n",
"      height: image.height,\n",
"    );\n",
"  }\n",
);

splice(@lines, $start, $end - $start + 1, @new);

open(my $out, ">:encoding(UTF-8)", $path) or die $!;
print $out @lines;
close $out;
print "done 1\n";