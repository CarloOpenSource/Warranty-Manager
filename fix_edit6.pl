use strict;
use warnings;

my $path = "lib/Screens/edit_screen.dart";
open(my $fh, "<:encoding(UTF-8)", $path) or die $!;
my @lines = <$fh>;
close $fh;

# Find the duplicate stack start (second "children: [" after the first replacement)
my $start = -1;
my $count = 0;
for my $i (0..$#lines) {
    if ($lines[$i] =~ m{^\s+children: \[$}) {
        $count++;
        if ($count == 2) {
            $start = $i;
            last;
        }
    }
}
die "second children not found" if $start < 0;

# Find matching closing braces (need to find the end of the second stack)
my $end = -1;
my $brace_count = 0;
for my $i ($start..$#lines) {
    $brace_count += ($lines[$i] =~ tr/{/{/);
    $brace_count -= ($lines[$i] =~ tr/}/}/);
    # Look for closing "}," or "}," pattern after the stack content
    if ($brace_count == 0 && $lines[$i] =~ m{^\s+\},\s*$}) {
        $end = $i;
        last;
    }
}
die "end not found" if $end < 0;
print "duplicate start=$start end=$end\n";

# Remove the duplicate
splice(@lines, $start, $end - $start + 1, ());

open(my $out, ">:encoding(UTF-8)", $path) or die $!;
print $out @lines;
close $out;
print "done 5\n";