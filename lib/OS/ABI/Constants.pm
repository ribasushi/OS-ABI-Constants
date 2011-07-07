package OS::ABI::Constants;

use warnings;
use strict;

use 5.006002;

our $VERSION = '0.00_03'; # pre-alpha - this is the smoker survey stage!

# init our namespace
my $known_constants = { map
  { %$_ }
  values %{ constants() || {} }
};
eval "sub $_ () { $known_constants->{$_} }" for keys %$known_constants;


sub import {
  my $class = shift;

  my $const = $class->constants;
  for (@_) {
    no strict 'refs';

    my @imp;
    if ($_ =~ /^:(.+)/) {
      my $subc = $const->{$1}
        or __croak("$class does not define constants export group '$_'");
      @imp = keys %$subc;
    }
    else {
      @imp = $_;
    }

    for (@imp) {
      __croak("$class does not define constant '$_'")
        unless exists $known_constants->{$_};

      *{ caller() . "::$_" } = $class->can($_);
    }
  }
}

sub __croak {
  $Carp::Internal{__PACKAGE__}++;
  require Carp;
  Carp::croak( @_ );
}

sub constants {
  if ( do { local $@; eval "require OS::ABI::MyConstants" } ) {
    OS::ABI::MyConstants->constants;
  }
  else {
    # TODO - unimplemented
    # need to invoke sysinfo and return constants determined by the survey
    {},
  }
}

sub sysinfo {
  require Sys::Info;
  require Config;

  my $s = Sys::Info->new;
  my $o = $s->os;
  my $c = $s->device('CPU');
  my @c = $c->identify;

  return {
    fingerprint => 'will hash some crucial stuff here, TBD',
    os => {
      $o->meta,
      ( map { $_ => scalar $o->$_ } qw/bitness name version product_type/ ),
      fullname => $o->name (edition => 1, long => 1),
    },
    cpu => {
      (map {( "cpu$_" => $c[$_] )} (0 .. $#c) ),
      (map { $_ => scalar $c->$_ } qw/bitness count speed hyper_threading/ ),
    },
    perl => { %Config::Config },  # lose the tie
  }
}

sub __encode_struct {
  require Storable;
  require IO::Compress::Bzip2;
  require MIME::Base64;

  my $blob = do { no warnings 'once'; local $Storable::canoncial = 1; Storable::nfreeze(shift) };
  my $bz2;
  IO::Compress::Bzip2::bzip2 (\$blob, \$bz2,
    BlockSize100K => 9,
    WorkFactor => 250,
  );
  my $enc = MIME::Base64::encode_base64($bz2);
  chomp $enc;
  return $enc;
}

1;

=head1 NAME

OS::ABI::Constants - A libray of system-specific ABI constants

=head1 DESCRIPTION

TODO

=head1 AUTHOR

ribasushi: Peter Rabbitson <ribasushi@cpan.org>

=head1 CONTRIBUTORS

None as of yet

=head1 COPYRIGHT

Copyright (c) 2011 the OS::ABI:Constants L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms
as perl itself.

=cut
