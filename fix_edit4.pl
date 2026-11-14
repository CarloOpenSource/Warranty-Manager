use strict;
use warnings;

my $path = "lib/Screens/edit_screen.dart";
open(my $fh, "<:encoding(UTF-8)", $path) or die $!;
my @lines = <$fh>;
close $fh;

# Find duplicate _restoreOriginal method (the old one)
my $start = -1;
my $count = 0;
for my $i (0..$#lines) {
    if ($lines[$i] =~ m{^\s+void _restoreOriginal\(\) \{}) {
        $count++;
        if ($count == 2) {
            $start = $i;
            last;
        }
    }
}
die "second _restoreOriginal not found" if $start < 0;

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
print "duplicate _restoreOriginal start=$start end=$end\n";

# Remove the duplicate
splice(@lines, $start, $end - $start + 1, ());

open(my $out, ">:encoding(UTF-8)", $path) or die $!;
print $out @lines;
close $out;
print "done 3\n";