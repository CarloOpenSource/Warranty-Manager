use strict;
use warnings;
use utf8;

open(my $fh, "<:encoding(UTF-8)", "lib/Screens/edit_screen.dart") or die $!;
my $content = do { local $/; <$fh> };
close $fh;

# Find the position of the first "/// Parameter für Hintergrund-Speichern"
my $marker_pos = rindex($content, "/// Parameter für Hintergrund-Speichern");
print "Marker position: $marker_pos\n";

# Find the closing brace of _EditScreenState class before the duplicate methods
my $class_end_pos = rindex($content, "}\n\n/// Parameter für Hintergrund-Speichern");
print "Class end position: $class_end_pos\n";

if ($class_end_pos >= 0) {
    # Keep everything up to and including the closing brace of _EditScreenState
    my $new_content = substr($content, 0, $class_end_pos + 1) . "\n\n" . substr($content, $marker_pos);
    open(my $fh, ">:encoding(UTF-8)", "lib/Screens/edit_screen.dart") or die $!;
    print $fh $new_content;
    close $fh;
    print "Fixed duplicate methods\n";
} else {
    print "Could not find class end\n";
}
