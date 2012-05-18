# "passenger-status" equivalent.
# Author: Giuliano Cioffi <giuliano at 108.bz>

#!/usr/bin/perl
use strict;
use File::Basename;
BEGIN { push @INC, dirname($0); }
use MiniXML;
use PassengerStatus;
use Data::Dumper;

my $xml = PassengerStatus::status();
die PassengerStatus::last_error."\n" unless defined $xml;

my $stats = MiniXML::Parse($xml);

$Data::Dumper::Indent = 1;
print Dumper($stats);

exit;
