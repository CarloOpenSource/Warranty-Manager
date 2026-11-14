use strict;
use warnings;
use utf8;

open(my $fh, "<:encoding(UTF-8)", "lib/Screens/edit_screen.dart") or die $!;
my $content = do { local $/; <$fh> };
close $fh;

# Find the _CropPainter class
my $marker = "/// CustomPainter f\x{C3}\x{BC}r professionellen Crop-Overlay";
my $pos = index($content, $marker);
print "Marker position: $pos\n";

if ($pos >= 0) {
    # Find the end of the constructor
    my $constructor_end = index($content, "}) : super();", $pos);
    print "Constructor end position: $constructor_end\n";
    
    if ($constructor_end >= 0) {
        # Find the @override after constructor
        my $override_pos = index($content, "@override", $constructor_end);
        print "Override position: $override_pos\n";
        
        # Check what's actually there
        print "Content around constructor: " . substr($content, $constructor_end - 10, 30) . "\n";
        
        # Check if there's a missing closing brace for the class
        my $class_end = index($content, "}\n\n/// Crop-Handle Typen", $pos);
        print "Class end position: $class_end\n";
        
        # Check if there's a missing closing brace
        my $open_braces = 0;
        my $close_braces = 0;
        for (my $i = $pos; $i < length($content); $i++) {
            my $char = substr($content, $i, 1);
            if ($char eq '{') { $open_braces++; }
            if ($char eq '}') { $close_braces++; }
            if ($open_braces > 0 && $open_braces == $close_braces) {
                print "Class should end at position $i\n";
                print "Content at that position: " . substr($content, $i - 20, 40) . "\n";
                last;
            }
        }
    }
}
