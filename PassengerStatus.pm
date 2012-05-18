# Inspects Phusion Passenger’s internal status by querying its socket interface.
# Supports Passenger 3.
# Author: Giuliano Cioffi <giuliano@108.bz>

package PassengerStatus;

use strict;
use IO::Socket::UNIX;

use constant HEADER_SIZE        => 2;
use constant DELIMITER          => "\0";
use constant UINT16_PACK_FORMAT => "n";
use constant UINT32_PACK_FORMAT => "N";
use constant TMPDIR             => '/tmp';

use constant E_SOCKCREATE       => 'Error while creating socket';
use constant E_SOCKREAD         => 'Error while reading from socket';
use constant E_SOCKWRITE        => 'Error while writing to socket';
use constant E_PIDOPEN          => 'Cannot open PID file';
use constant E_PIDWRONG         => 'PID doesn\'t look right';
use constant E_NOPID            => 'Passenger/nginx is not running or invalid permissions';
use constant E_PWOPEN           => 'Cannot open password file';
use constant E_PWREAD           => 'Cannot read password file';
use constant E_SECNOTPASSED     => 'Security not passed';
use constant E_UNEXPCONN        => 'Unexpected reply on connection';
use constant E_NOTOK            => 'Passenger replied not ok';

my $err = '';

sub last_error {
    return $err;
}

sub error {
    my $message = shift;
    my ($filename, $line) = (caller)[1,2];
    $err = "$message at $filename:$line";
    return undef;
}

sub get_generation_path {
    my @dirs = glob TMPDIR."/passenger.*";
    my $pid = 0;
    my $path = '';
    foreach my $dir (@dirs) {
        if (-r "$dir/control_process.pid") {
            my $fh;
            open $fh, "<$dir/control_process.pid" or return error(E_PIDOPEN);
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
    return error(E_PIDWRONG) unless defined $pid and $pid > 0;
    return error(E_NOPID) unless kill 0, $pid;

    my $highest_generation = -1;
    my @gens = glob "$path/generation-*";
    map {/generation-(\d+)/; my $g = $1; $highest_generation = $g if $g > $highest_generation} @gens;
    return "$path/generation-$highest_generation";
}

# phusion_passenger/message_channel.rb
# MessageChannel.write_scalar
sub messagechannel_write_scalar($$) {
    my ($sock,$data) = @_;
    my $rc = $sock->write(pack('N',length $data).$data);
    return error(E_SOCKWRITE) if $rc == undef;
    $sock->flush;
}

# phusion_passenger/message_channel.rb
# MessageChannel.read
sub messagechannel_read($) {
    my $sock = shift;
    my $buffer = '';
    my $tmp = '';
    return error(E_SOCKREAD) unless $sock->read($buffer,HEADER_SIZE);
    while (length($buffer) < HEADER_SIZE) {
        return error(E_SOCKREAD) unless $sock->read($tmp,HEADER_SIZE - length($buffer));
        $buffer .= $tmp;
    }

    my $chunk_size = (unpack UINT16_PACK_FORMAT, $buffer)[0];
    return error(E_SOCKREAD) unless $sock->read($buffer,$chunk_size);
    while (length($buffer) < $chunk_size) {
        return error(E_SOCKREAD) unless $sock->read($tmp,HEADER_SIZE - length($buffer));
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
        Timeout => 1) or return error(E_SOCKCREATE);
    binmode($sock);
    return $sock;
}

# phusion_passenger/message_client.rb
# MessageClient.initialize
sub messageclient_initialize($$$) {
    my ($username, $password, $address) = @_;
    my $sock = init_socket($address);
    my $messages;
    $messages = messagechannel_read($sock) or return undef;
    return error(E_UNEXPCONN) unless @$messages
        and @$messages == 2
        and $messages->[0] eq 'version'
        and $messages->[1] eq '1';

    messagechannel_write_scalar($sock, $username);
    messagechannel_write_scalar($sock, $password);

    $messages = messagechannel_read($sock) or return undef;
    return error(E_NOTOK) unless $messages->[0] eq 'ok';

    return $sock;
}

sub read_password($) {
    my $passwordfile = shift;
    my ($fh, $password);
    my $size = -s $passwordfile; 
    open $fh, "<$passwordfile" or return error(E_PWOPEN);
    binmode $fh;
    return error(E_PWREAD) if sysread($fh, $password, $size) != $size;
    return $password;
}

sub message_client_xml($) {
    my $sock = shift;
    my $command = 'toXml'.DELIMITER.'true'.DELIMITER;
    my $rc = $sock->write(pack('n',length $command).$command);
    return error(E_SOCKWRITE) if $rc == undef;
    $sock->flush;
    my $messages = messagechannel_read($sock) or return undef;
    return error(E_SECNOTPASSED) unless $messages->[0] eq 'Passed security';

    my $tmp = '';
    my $buffer = '';
    return error(E_SOCKREAD) unless $sock->read($buffer,4);
    while (length($buffer) < 4) {
        return error(E_SOCKREAD) unless $sock->read($tmp,4 - length($buffer));
        $buffer .= $tmp;
    }
    my $size = (unpack UINT32_PACK_FORMAT, $buffer)[0];
    return error(E_SOCKREAD) if $size == 0;

    $tmp = '';
    return error(E_SOCKREAD) unless $sock->read($buffer,$size);
    while (length($buffer) < $size) {
        return error(E_SOCKREAD) unless $sock->read($tmp,$size - length($buffer));
        $buffer .= $tmp;
    }
    return $buffer;
}

sub status {
    my $generation_path = get_generation_path() or return undef;
    my $password = read_password("$generation_path/passenger-status-password.txt") or return undef;
    my $sock = messageclient_initialize('_passenger-status',$password,"$generation_path/socket") or return undef;
    my $xml = message_client_xml($sock) or return undef;
    $sock->close;
    return $xml;
}

1;
