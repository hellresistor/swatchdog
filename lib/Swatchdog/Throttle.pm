package Swatchdog::Throttle;
require 5.000;
require Exporter;

use strict;
use Carp;
use Date::Calc;
use Date::Manip;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

@ISA = qw(Exporter);
@EXPORT = qw/
  flushLogRecords
  throttle
  readHistory
  saveHistory
/;
$VERSION = '20030701';

#
# %LogRecords = (
#          <string> =>  { # keyed by "key" below
#                       KEY => <string>, # generated key
#                       FIRST => @dmyhms,  # time of first log
#                       LAST => @dmyhms,   # time of last log
#                       COUNT => <int>,  # num of logs seen since last report
#                       },
#             );
my %LogRecords = ();


################################################################
sub readHistory {
  my $file = shift;
  my $return;

  if (-f $file) {
    unless ($return = do $file) {
      warn "couldn't parse $file: $@" if $@;
      warn "couldn't do $file: $!" unless defined $return;
      warn "couldn't run file" unless $return;
    }
  }
  return;
}

################################################################
sub saveHistory {
  my $file = shift;
  my $fh = new FileHandle $file, "w";
  my $date = localtime(time);

  if (defined $fh) {
    $fh->print(q/
################################################################
# THIS FILE WAS GENERATED BY SWATCH AT $date.
# DO NOT EDIT!!!
################################################################
$Swatchdog::Throttle::LogRecords = (
/);

    foreach my $key ( keys %LogRecords ) {
      $fh->print("\t'$key' => {\n");
      foreach my $attr ( keys %{ $LogRecords{$key} } ) {
	$fh->print("\t\t$attr => ");
	if ($attr =~ /FIRST|LAST|HOLD_DHMS/) {
	  $fh->print("[ ");
	  foreach my $elem (@{ $LogRecords{$key}{$attr} }) {
	    $fh->print("\'$elem\', ");
	  }
	  $fh->print("],\n");
        } else {
	  $fh->print("\"$LogRecords{$key}{$attr}\",\n");
	}
      }
      $fh->print("\t},\n");
    }
    $fh->print(");\n");
    $fh->close;
  } else {
  }
}

################################################################
# throttle() - returns the 
################################################################
sub throttle {
  my %opts = (
	      MESSAGE       => $_,
	      EXTRA_CUTS => [],  # regex(s) used for creating key if key=log
	      KEY        => 'log',
	      TIME_FROM  => 'realtime',
	      TIME_REGEX => '^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+', 
	      @_
	     );

  my @dmyhms;
  my $key;
  my $cur_rec;
  my $msg = $opts{"MESSAGE"};

  ## get the time ##
  if ($opts{TIME_FROM} eq 'realtime') {
    @dmyhms = Date::Calc::Today_and_Now();
  } else {
    if ($opts{MESSAGE} =~ /$opts{TIME_REGEX}/ and $1 ne '') {
      my $date = Date::Calc::ParseDate($1);
      if (not $date) {
	warn "Cannot parse date from \"$opts{MESSAGE}\" using \"$opts{TIME_REGEX}\"\n";
      } else {
	@dmyhms = Date::Manip::UnixDate($date, "%Y", "%m", "%d", "%H", "%M", "%S");
      }
    }
  }

  ## get the key ##
  if ($opts{KEY} eq 'log') {
    $key = $opts{MESSAGE};
    $key =~ s/$opts{TIME_REGEX}//;
    if (defined $opts{EXTRA_CUTS}) {
      foreach my $re (@{ $opts{EXTRA_CUTS} }) {
	$key =~ s/$re//g;
      }
    }
  } else {
    $key = $opts{KEY};
  }

  ## just make the record if it doesn't exist yet ##
  if (not defined $LogRecords{$key}) {
    my $rec = ();
    $rec->{KEY} = $key;
    $rec->{FIRST} = [ @dmyhms ];
    $rec->{LAST} = [ @dmyhms ];
    $rec->{HOLD_DHMS} = $opts{HOLD_DHMS} if defined $opts{HOLD_DHMS};
    $rec->{COUNT} = 1;
    $LogRecords{$key} = $rec;
    return $msg;
  } else {
    $cur_rec = $LogRecords{$key};
    $cur_rec->{COUNT}++;
    if (defined $opts{THRESHOLD} and $cur_rec->{COUNT} == $opts{THRESHOLD}) {
      ## threshold exceeded ##
      chomp $msg;
      $msg = "$msg (threshold $opts{THRESHOLD} exceeded)";
      $cur_rec->{COUNT} = 0;
    } elsif (defined $opts{HOLD_DHMS} 
	     and past_hold_time($cur_rec->{LAST},
				\@dmyhms, $opts{HOLD_DHMS})) {
      ## hold time exceeded ##
      chomp $msg;
      $msg = "$msg (seen $cur_rec->{COUNT} times)";
      $cur_rec->{COUNT} = 0;
      $cur_rec->{LAST} = [ @dmyhms ];
    } else {
      $msg = '';
    }
    $LogRecords{$key} = $cur_rec if exists($LogRecords{$key});  ## save any new values ##
  }
  return $msg;
}

################################################################
# Checks to see if the current time is less than the last
# time plus the minimum hold time.
################################################################
sub past_hold_time {
  my $last = shift; ## pointer to YMDHMS array of last message
  my $cur  = shift; ## pointer to YMDHMS array of current message
  my $hold = shift; ## pointer to DHMS array of min. hold time

  my @ymdhms = Date::Calc::Add_Delta_DHMS( @{ $last }, @{ $hold } );
  my @delta = Date::Calc::Delta_DHMS( @ymdhms, @{ $cur } );
  return(   $delta[0] > 0 or $delta[1] > 0
	 or $delta[2] > 0 or $delta[3] > 0 );

}

################
sub flushOldLogRecords {
  my @dmyhms = Date::Calc::Today_and_Now();

  foreach my $key (keys %LogRecords) {
    if (defined $LogRecords{$key}->{HOLD_DHMS}) {
      if (past_hold_time($LogRecords{$key}->{LAST}, \@dmyhms, $LogRecords{$key}->{HOLD_DHMS})
	 and $LogRecords{$key}->{COUNT} == 0) {
	delete($LogRecords{$key});
      }
    }
  }
}

## The POD ###

=head1 NAME

  Swatchdog::Throttle - Perl extension for throttling and thresholding in swatchdog(1)

=head1 SYNOPSIS

  use Swatchdog::Throttle;

  throttle(
	   extra_cuts => @array_of_regular_expressions,
	   hold_dhms => @DHMS,
	   key => 'log'|<regex>|<user defined>,
	   log_msg => <message>,
	   threshold => <n>,
	   time_from => 'realtime'|'timestamp',
	   time_regex => <regex>,
          );

=head1 SWATCH SYNTAX

  throttle threshold=<n>,\
           delay=<hours>:<minutes>:<seconds>,\
           key=log|regex|<regex>

=head1 DESCRIPTION

=head1 AUTHOR

E. Todd Atkins, todd.atkins@stanfordalumni.org

=head1 SEE ALSO

perl(1), swatchdog(1).

=cut
  
1;
