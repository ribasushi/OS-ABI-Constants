use warnings;
use strict;

use inc::Module::Install '1.01';

use 5.006002;

# this is used by gen_my_abi iff we detect a compiler toolchain
# keeping it up here for easy reference
my $examine = {

  time => {

    # how to build the initial #include lines
    # absolute paths are #include "..."ed, and relative are #include <...>ed
    headers => {

      generic => [ $Config::Config{timeincl} ? split / /, $Config::Config{timeincl} : 'sys/time.h' ],

      linux => [qw| linux/time.h time.h |],

      MSWin32 => undef, # win32 pretty much does not support *ANY* of the POSIX time stuff,
                        # Time::HiRes ends up emulating everything :(
    },

    # how to scan the contents of *all* .h files fished from the result of cpp -E (or equivalent)
    # a coderef is expected to return a list of individual constants
    # a regex is applied as $headers =~ /$re/g
    find_constants => {

      generic => qr/^ \s* \#define \s+ ( ITIMER_\w+ | CLOCK_\w+ ) \s+ \S /mx,

      # hpux has some crazy definitions sitting in enums
      hpux => sub {
        my $hdrs = shift;
        my @clock_tdefs = $hdrs =~ / \b typedef \s+ enum \s+ __clockid_t \s+ \{ (.*? \bCLOCK_\w+ .*? ) \}/xmgs;
        return (
          ( $hdrs =~ /^ \s* \#define \s+ ( ITIMER_\w+ | CLOCK_\w+ ) \s+ \S /mxg ),
          ( map { $_ =~ / (\b CLOCK_\w+ ) /xg } @clock_tdefs ),
        );
      },

    },

    # things that should be implemented anywhere (as optional sanity check) - scalar or arrayref of constant names
    mandatory_constants => 'CLOCK_REALTIME',
  },

  # not everything implements syscall()
  ! $Config::Config{d_syscall} ? () : (
  syscall => {

    headers => {
      generic => 'sys/syscall.h',
    },

    find_constants => {
      generic => qr/^ \s* \#define \s+ ( SYS_[a-z]\w+ ) \s+ \S /mx,
    },

    mandatory_constants => 'SYS_read',
  }),

  # other interesting stuff to detect...?
};


use File::Spec;
my $IS_SMOKER = (
  $ENV{AUTOMATED_TESTING}
    and
  ! $ENV{PERL5_CPANM_IS_RUNNING}
    and
  ! $ENV{RELEASE_TESTING}
    and
  ! -d '.git'
    and
  -d 'inc'
    and
  ! -e File::Spec->catfile('inc', $^O eq 'VMS' ? '_author' : '.author')
);


all_from 'lib/OS/ABI/Constants.pm';

requires 'Sys::Info' => '0.78';

if (can_cc and my $cpp = can_cpp() ) {
  # this is a horrendous hack to force an UNKNOWN report as opposed to N/A
  # because of the destructiveness we go to great lengths above to make sure
  # we are in fact a smoker
  local $SIG{__DIE__} = sub {
    my $err = shift;

    # this is not guaranteed to work, but could :)
    require File::Path;
    File::Path::rmtree('t');
    print STDERR "$err\n";
    WriteAll;
    exit 0;
  } if $IS_SMOKER;

  gen_my_abi($cpp);
}
### FIXME - temporary, for the duration of the survey
else {
  warn "The survey stage requires a C compiler and pre-processor\n";
  exit 0;
}

# these are also temporary
configure_requires 'MIME::Base64' => 0;
configure_requires 'IO::Compress::Bzip2' => 0;
configure_requires 'Storable' => 0;

resources 'repository'  => 'http://github.com/ribasushi/OS-ABI-Constants';

WriteAll;

sub gen_my_abi {
  my $cpp = shift;

  warn "C pre-processor `$cpp` detected - gathering ABI constants from your system\n";
  my $abi = examine_abi($cpp);

  my $fn = 'lib/OS/ABI/MyConstants.pm';
  unlink $fn; # don't care if there or not

  if (grep { keys %$_ } values %$abi) {
    write_my_abi ($fn, $abi);
  }
  else {
    warn "No interesting constants found during ABI examination - skipping creation of $fn\n";
    # FIXME - temporary
    die "OS unsupported\n";
  }
}

sub examine_abi {
  my $cpp = shift;

  require IO::Handle;
  require IPC::Open3;
  require B;

  my $quoter = B->can( $] > 5.008 ? 'perlstring' : 'cstring' );

  my ($my_abi, $errors);

  for my $type (keys %$examine) {
    $my_abi->{$type} = {};

    my $conf = $examine->{$type};

    my $h = $conf->{headers};
    $h = ( exists $h->{$^O} ? $h->{$^O} : $h->{generic} );

    next unless defined $h;

    my $c_src;
    for (ref $h eq 'ARRAY' ? @$h : $h) {
      $c_src .= sprintf( "#include %s\n",
        # quote or bracket inclusion?
        $_ =~ m|^/|
          ? qq|"$_"|
          : "<$_>"
      );
    }

    my ($out, $err) = _run_cpp ($cpp, $c_src);
    if ($err) {
      $err->{err} = "Execution of `$err->{cmd}` failed ($err->{exit})";
      warn "$err->{err}\n";
      $errors->{$type} = $err;
      next;
    }

    my %headers;
    while ($out =~ /"(.+?.h)"/g) {
      next if $headers{$1};
      next unless -f $1 and -r $1;
      $headers{$1} = scalar keys %headers;
    }

    my $header_contents;
    for (sort { $headers{$a} <=> $headers{$b} } keys %headers ) {
      $header_contents .= sprintf( "%s\n=== %s\n%s\n%s\n",
        '=' x 70,
        $_,
        '=' x 70,
        do { local (@ARGV, $/) = $_; <> },
      );
    }

    # crude reassembly of multilines (maybe bad idea?)
    $header_contents =~ s/ \\ \n //xg;

    # strip comments/spaces
    $header_contents =~ s! \/ \/ .*? \n | \/ \* .*? \*\/ !!xsg;
    $header_contents =~ s/^\s+^//gm;


    my $find_consts = $conf->{find_constants}{$^O} || $conf->{find_constants}{generic};
    # undef means known but unresolved (I guess unimplemented?)
    # the const regex may have multiple captures, filter out the undef's
    my $consts = { map
      { defined $_ ? ($_ => undef) : () }
      ref $find_consts eq 'CODE'
        ? $find_consts->($header_contents)
        : $header_contents =~ /$find_consts/g
    };

    # consider lack of detected constants as error
    if (
      ! keys %$consts
        or
      grep { ! exists $consts->{$_} } ref $conf->{mandatory_constants} eq 'ARRAY'
        ? @{$conf->{mandatory_constants}}
        : $conf->{mandatory_constants} || ()
    ) {
      my $err = "Did not detect any '$type' constants" . ($conf->{mandatory_constants}
        ? sprintf ' (expected to find the following ubuquitos definitions: %s)', join ', ', @{$conf->{mandatory_constants}}
        : ''
      );
      warn "$err\n";
      $errors->{$type} = {
        err => $err,
        stdin => $c_src,
        stdout => $out,
        header_files => [ sort { $headers{$a} <=> $headers{$b} } keys %headers ],
        header_contents => $header_contents,
      };
      next;
    }

    $my_abi->{$type} = $consts;

    $c_src .= "int main (void)\n{\n";
    $c_src .= "'$_' => \n'__VALUE__START__'\n$_\n'__VALUE__END__'\n,\n" for sort keys %$consts;
    $c_src .= "}\n";

    ($out, $err) = _run_cpp ($cpp, $c_src);
    if ($err) {
      $err->{err} = "Execution of `$err->{cmd}` failed ($err->{exit})";
      warn "$err->{err}\n";
      $errors->{$type} = $err;
      next;
    }

    $out =~ s/ \n'__VALUE__START__'\n (.+?) \n'__VALUE__END__'\n / $quoter->($1) /egxms;
    if ( my ($resolved) = $out =~ /^int \s main \s \(void\) \n ( \{ .+? \} ) $/xms ) {
      my $res = eval $resolved or die "Unable to eval preprocessed pseudo-source:\n$@";

      # if it didn't resolve this means it is unimplemented (or maybe we did not get the right headers?)
      for (keys %$res) {
        $consts->{$_} = $res->{$_} unless $res->{$_} eq $_ 
      }
    }

    if (my @unresolved = grep { ! defined $consts->{$_} } keys %$consts ) {
      warn (
        "\nThe following constants were detected but failed to resolve to an actual value, assuming unimplemented (maybe the header spec for '$^O' is insufficient...):\n=============\n"
       . join (', ', sort @unresolved ) . "\n\n"
      );
    }
  }

  # shit hit the fan - die if a smoker, otherwise just warn
  if ($errors) {
    my $err = _encode_error($errors);
    die $err if $IS_SMOKER;
    warn $err;
  }

  $my_abi;
}

sub _encode_error {
  my $error = shift;

  $error->{'~perl_conf'} = { %Config::Config };

  unshift @INC, 'lib';
  if (
    eval { require OS::ABI::Constants }
      and
    my $enc = OS::ABI::Constants::__encode_struct ($error)
  ) {
    $error =
"
=== BEGIN ABI Survey Errors
$enc
=== END ABI Survey Errors
"
    ;
  }
  else {
    my $oac_encode_error = $@ || 'UNKNOWN';
    chomp $oac_encode_error;
    require Data::Dumper;
    $error =
        "Error (encoding failed due to $oac_encode_error)\n\n"
      . Data::Dumper->new([ $error ])->Indent(1)->Terse(1)->Quotekeys(0)->Sortkeys(1)->Dump
    ;
  }

  $error;
}

# use this in lieu of IPC::Run to avoid configure_requires hell, and to not shove
# the dep down everyone's throats (only Win32 can't do open3 IO reliably)
sub _run_cpp {
  my ($cmd, $stdin) = @_;

  my ($infh, $infn);
  if ($^O eq 'MSWin32') {
    require File::Temp;
    $infn = File::Temp->new( UNLINK => 1, SUFFIX => '.c' );
    $infn->print ($stdin);
    $infn->close;
    $cmd .= " $infn";
  }
  else {
    $infh = IO::Handle->new;
    $cmd .= ' -';
  }

  my $outfh = IO::Handle->new;

  # sometimes we hang, don't know why yet - this should gives us enough info
  my $timeout = 10;
  local $SIG{ALRM} = sub {
    die _encode_error {
      cmd => $cmd,
      stdin => $stdin,
      err => "cpp run did not complete within $timeout seconds",
    };
  };
  alarm ($timeout);

  my $pid = IPC::Open3::open3 (
    $infh,
    $outfh,
    undef,  # splitting out/err will hang on win32
    $cmd,
  ) or die "open3 of '$cmd' failed: $!\n";

  if ($infh) {
    $infh->print($stdin);
    $infh->close;
  }

  my $out = do { local $/; $outfh->getline };

  waitpid($pid, 0);
  alarm(0);

  # squash $out a little
  $out =~ s/^\s+^/\n/gm;

  if (my $ex = $?) {
    chomp $_ for ($stdin, $out);

    return (undef, {
      cmd => $cmd,
      exit => $ex >> 8,
      signal => $ex & 127,
      coredump => ($ex & 128) ? 'Y' : 'N',
      stdin => $stdin,
      stdouterr => $out,
    });
  }
  else {
    return $out;
  }
}

sub write_my_abi {
  my ($fn, $abi) = @_;

  warn "Writing constants to $fn\n";

  open (my $fh, '>', $fn) or die "Unable to open $fn: $!\n";

  require Data::Dumper;
  my $cdump = Data::Dumper->new([$abi])->Indent(1)->Useqq(1)->Terse(1)->Quotekeys(0)->Sortkeys(1)->Pad('  ')->Dump;
  my $ver = time();
  my $ver_comment = gmtime;

  print $fh <<EOC;
#############################################################
###                                                       ###
###    FILE AUTOGENERATED AT THE TIME OF INSTALLATION     ###
###                    DO NOT EDIT!!!                     ###
###                                                       ###
### If your system has changed drastically since - simply ###
### reinstall OS::ABI::Constants                          ###
###                                                       ###
#############################################################

package # not the package you are looking for
  OS::ABI::MyConstants;

use warnings;
use strict;

our \$VERSION = $ver; # $ver_comment

sub constants { return
$cdump}

1;

EOC

  close $fh;
}

# modelled on Module::Install::Can::can_cc
sub can_cpp {
  require Config;
  require Module::Install::Can;
  my @chunks = split(/ /,
    # activestate braindeath
    ($^O eq 'MSWin32' and $Config::Config{cppstdin} eq 'cppstdin')
      ? $Config::Config{cpp}
      : $Config::Config{cppstdin}
  ) or return;

  # $Config{cppstdin} may contain args; try to find out the program part
  my ($cmd, @args);
  while (@chunks) {
    last if $cmd = Module::Install::Can->can_run("@chunks");
    unshift @args, pop @chunks;
  }

  return unless $cmd;

  return join (' ', $cmd, @args);
}
