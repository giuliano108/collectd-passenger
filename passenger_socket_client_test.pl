#!/usr/bin/perl
use strict;
use File::Basename;
BEGIN { push @INC, dirname($0); }
use MiniXML;
use IO::Socket::UNIX;
use Data::Dumper;

use constant HEADER_SIZE        => 2;
use constant DELIMITER          => "\0";
use constant UINT16_PACK_FORMAT => "n";
use constant UINT32_PACK_FORMAT => "N";
use constant TMPDIR             => '/tmp';

my @dirs = glob TMPDIR."/passenger.*";
my $pid = 0;
my $path = '';
foreach my $dir (@dirs) {
	if (-r "$dir/control_process.pid") {
		my $fh;
		open $fh, "<$dir/control_process.pid" or die;
		$pid = <$fh>;
		chomp $pid;
		close $fh;
		$path = $dir;
	} else {
		$dir =~ /passenger\.\d+\.\d+\.(\d+)\Z/;
		$pid = $1;
		$path = $dir;
	}
}
die unless defined $pid and $pid > 0;
die unless kill 0, $pid;

my $highest_generation = -1;
my @gens = glob "$path/generation-*";
map {/generation-(\d+)/; my $g = $1; $highest_generation = $g if $g > $highest_generation} @gens;
my $generation_path = "$path/generation-$highest_generation";

# phusion_passenger/message_channel.rb
# MessageChannel.write_scalar
sub messagechannel_write_scalar($$) {
	my ($sock,$data) = @_;
	my $rc = $sock->write(pack('N',length $data).$data);
	die if $rc == undef;
	$sock->flush;
}

# phusion_passenger/message_channel.rb
# MessageChannel.read
sub messagechannel_read($) {
	my $sock = shift;
	my $buffer = '';
	my $tmp = '';
	return undef unless $sock->read($buffer,HEADER_SIZE);
	while (length($buffer) < HEADER_SIZE) {
		return undef unless $sock->read($tmp,HEADER_SIZE - length($buffer));
		$buffer .= $tmp;
	}

	my $chunk_size = (unpack UINT16_PACK_FORMAT, $buffer)[0];
	return undef unless $sock->read($buffer,$chunk_size);
	while (length($buffer) < $chunk_size) {
		return undef unless $sock->read($tmp,HEADER_SIZE - length($buffer));
		$buffer .= $tmp;
	}
	my $message = [];
	my $offset = 0;
	my $delimiter_pos = index $buffer, DELIMITER, $offset;
	while ($delimiter_pos >= $offset) {
		if ($delimiter_pos == 0) {
			push @$message, '';
		} else {
			push @$message, substr($buffer, $offset, $delimiter_pos - $offset);
		}
		$offset = $delimiter_pos + 1;
		$delimiter_pos = index $buffer, DELIMITER, $offset;
	}
	return $message;
}

sub init_socket($) {
	my $address = shift;
	my $sock = new IO::Socket::UNIX (
		Peer    => $address,
		Timeout => 1) or return undef;
	binmode($sock);
	return $sock;
}

# phusion_passenger/message_client.rb
# MessageClient.initialize
sub messageclient_initialize($$$) {
	my ($username, $password, $address) = @_;
	my $sock = init_socket($address);
	my $messages;
	$messages = messagechannel_read($sock) or die;
	return undef unless @$messages
		and @$messages == 2
		and $messages->[0] eq 'version'
		and $messages->[1] eq '1';

	messagechannel_write_scalar($sock, $username);
	messagechannel_write_scalar($sock, $password);

	$messages = messagechannel_read($sock) or die;
	return undef unless $messages->[0] eq 'ok';

	return $sock;
}

sub read_password($) {
	my $passwordfile = shift;
	my ($fh, $password);
	my $size = -s $passwordfile; 
	open $fh, "<$passwordfile" or die;
	binmode $fh;
	die if sysread($fh, $password, $size) != $size;
	return $password;
}

sub message_client_xml($) {
	my $sock = shift;
	my $command = 'toXml'.DELIMITER.'true'.DELIMITER;
	my $rc = $sock->write(pack('n',length $command).$command);
	die if $rc == undef;
	$sock->flush;
	my $messages = messagechannel_read($sock) or die;
	return undef unless $messages->[0] eq 'Passed security';

	my $tmp = '';
	my $buffer = '';
	return undef unless $sock->read($buffer,4);
	while (length($buffer) < 4) {
		return undef unless $sock->read($tmp,4 - length($buffer));
		$buffer .= $tmp;
	}
	my $size = (unpack UINT32_PACK_FORMAT, $buffer)[0];
	return '' if $size == 0;

	$tmp = '';
	return undef unless $sock->read($buffer,$size);
	while (length($buffer) < $size) {
		return undef unless $sock->read($tmp,$size - length($buffer));
		$buffer .= $tmp;
	}
	return $buffer;
}

my $password = read_password("$generation_path/passenger-status-password.txt");
my $sock = messageclient_initialize('_passenger-status',$password,"$generation_path/socket") or die;
my $xml = message_client_xml($sock);

$sock->close;

my $stats = MiniXML::Parse($xml);
$Data::Dumper::Indent = 1;
print Dumper($stats);
exit;
