# the idea is:
# prove -l t/survey.t 2>&1 | maint/decode_survey.pl | less

use warnings;
use strict;

use Test::More;

use Storable 'nfreeze';
use IO::Compress::Bzip2 'bzip2';
use MIME::Base64 'encode_base64';

use_ok ('OS::ABI::Constants') or exit;  # no point continuing

my $survey = {
  constants => OS::ABI::Constants->constants,
  sysinfo => OS::ABI::Constants->sysinfo,
};

sleep 1;  # attempt to sync STDOUT/ERR
printf STDERR (
"
=== BEGIN ABI Survey: %s for perl %s on %s%s
%s
=== END ABI Survey
",
  (join '/', ( keys %{$survey->{constants}} ? sort grep { keys %{$survey->{constants}{$_}} }keys %{$survey->{constants}} : 'NO INTERESTING CONSTANTS DETECTED') ),
  $],
  $survey->{sysinfo}{os}{bitness} ? "$survey->{sysinfo}{os}{bitness}bit " : '',
  $survey->{sysinfo}{os}{fullname},
  OS::ABI::Constants::__encode_struct ($survey),
);
sleep 1;

done_testing;
