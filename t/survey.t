# the idea is:
# prove -l t/survey.t 2>&1 | maint/decode_survey.pl | less


use warnings;
use strict;

use Test::More;

use Storable 'nfreeze';
use IO::Compress::Bzip2 'bzip2';
use MIME::Base64 'encode_base64';

use_ok ('OS::ABI::Constants');

my $survey = {
  constants => OS::ABI::Constants->constants,
  sysinfo => OS::ABI::Constants->sysinfo,
};

my $title = "Perl $] on $survey->{sysinfo}{os}{bitness}bit $survey->{sysinfo}{os}{fullname}";

$survey = do { no warnings 'once'; local $Storable::canoncial = 1; nfreeze($survey) };
my $bz2;
bzip2 (\$survey, \$bz2,
  BlockSize100K => 9,
  WorkFactor => 250,
);
$survey = encode_base64($bz2);
$survey = "\n=== BEGIN ABI Survey for $title \n${survey}=== END ABI Survey\n";

print STDERR $survey;

done_testing;
