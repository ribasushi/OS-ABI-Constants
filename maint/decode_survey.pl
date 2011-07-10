#!/usr/bin/env perl

use warnings;
use strict;

use MIME::Base64 'decode_base64';
use IO::Uncompress::Bunzip2 'bunzip2';
use Storable 'thaw';
use Data::Dumper;

my ($in) = do { local $/; <STDIN> } =~ /=== BEGIN ABI Survey.+?\n(.+?)\n=== END ABI Survey/ms;

die "No encoded ABI survey results found on STDIN\n"
  unless $in;

$in = decode_base64($in);
my $out;
bunzip2(\$in, \$out);

print Data::Dumper->new([ thaw $out ])->Indent(1)->Terse(1)->Quotekeys(0)->Sortkeys(1)->Dump;
