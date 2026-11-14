use strict;
use warnings;

my $path = "lib/Screens/edit_screen.dart";
open(my $fh, "<:encoding(UTF-8)", $path) or die $!;
my @lines = <$fh>;
close $fh;

# Replace the image display stack child (starts at line 315, index 314)
my $start = 314;
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
die "image stack end not found" if $end < 0;
print "image stack start=$start end=$end\n";

my @new = (
"                  child: Stack(\n",
"                    children: [\n",
"                      Center(\n",
"                        child: _displayBytes != null\n",
"                            ? InteractiveViewer(\n",
"                                panEnabled: false,\n",
"                                scaleEnabled: false,\n",
"                                child: SizedBox(\n",
"                                  width: _imgWidth.toDouble(),\n",
"                                  height: _imgHeight.toDouble(),\n",
"                                  child: Image.memory(\n",
"                                    _displayBytes!,\n",
"                                    fit: BoxFit.contain,\n",
"                                  ),\n",
"                                ),\n",
"                              )\n",
"                            : const SizedBox.shrink(),\n",
"                      ),\n",
"                      // --- Crop-Overlay ---\n",
"                      if (_imgWidth > 0)\n",
"                        Positioned.fill(\n",
"                          child: CustomPaint(\n",
"                            painter: _CropPainter(\n",
"                              cropRect: _cropRect,\n",
"                              isDragging: _isDragging,\n",
"                              brightness: Theme.of(context).brightness,\n",
"                            ),\n",
"                          ),\n",
"                        ),\n",
"                    ],\n",
"                  ),\n",
);

splice(@lines, $start, $end - $start + 1, @new);

open(my $out, ">:encoding(UTF-8)", $path) or die $!;
print $out @lines;
close $out;
print "done 4\n";