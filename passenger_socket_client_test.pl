#!/usr/bin/perl
use strict;
use IO::Socket::UNIX;
use Data::Dumper;

package XMLParser;
# ShallowParser regexes/function taken from: http://www.cs.sfu.ca/~cameron/REX.html#AppA
# REX/Perl 1.0 
# Robert D. Cameron "REX: XML Shallow Parsing with Regular Expressions",
# Technical Report TR 1998-17, School of Computing Science, Simon Fraser 
# University, November, 1998.
# Copyright (c) 1998, Robert D. Cameron. 
# The following code may be freely used and distributed provided that
# this copyright and citation notice remains intact and that modifications
# or additions are clearly identified.

my $TextSE = "[^<]+";
my $UntilHyphen = "[^-]*-";
my $Until2Hyphens = "$UntilHyphen(?:[^-]$UntilHyphen)*-";
my $CommentCE = "$Until2Hyphens>?";
my $UntilRSBs = "[^\\]]*](?:[^\\]]+])*]+";
my $CDATA_CE = "$UntilRSBs(?:[^\\]>]$UntilRSBs)*>";
my $S = "[ \\n\\t\\r]+";
my $NameStrt = "[A-Za-z_:]|[^\\x00-\\x7F]";
my $NameChar = "[A-Za-z0-9_:.-]|[^\\x00-\\x7F]";
my $Name = "(?:$NameStrt)(?:$NameChar)*";
my $QuoteSE = "\"[^\"]*\"|'[^']*'";
my $DT_IdentSE = "$S$Name(?:$S(?:$Name|$QuoteSE))*";
my $MarkupDeclCE = "(?:[^\\]\"'><]+|$QuoteSE)*>";
my $S1 = "[\\n\\r\\t ]";
my $UntilQMs = "[^?]*\\?+";
my $PI_Tail = "\\?>|$S1$UntilQMs(?:[^>?]$UntilQMs)*>";
my $DT_ItemSE = "<(?:!(?:--$Until2Hyphens>|[^-]$MarkupDeclCE)|\\?$Name(?:$PI_Tail))|%$Name;|$S";
my $DocTypeCE = "$DT_IdentSE(?:$S)?(?:\\[(?:$DT_ItemSE)*](?:$S)?)?>?";
my $DeclCE = "--(?:$CommentCE)?|\\[CDATA\\[(?:$CDATA_CE)?|DOCTYPE(?:$DocTypeCE)?";
my $PI_CE = "$Name(?:$PI_Tail)?";
my $EndTagCE = "$Name(?:$S)?>?";
my $AttValSE = "\"[^<\"]*\"|'[^<']*'";
my $ElemTagCE = "$Name(?:$S$Name(?:$S)?=(?:$S)?(?:$AttValSE))*(?:$S)?/?>?";
my $MarkupSPE = "<(?:!(?:$DeclCE)?|\\?(?:$PI_CE)?|/(?:$EndTagCE)?|(?:$ElemTagCE)?)";
my $XML_SPE = "$TextSE|$MarkupSPE";

sub ShallowParser { 
	my($XML_document) = @_;
	return $XML_document =~ /$XML_SPE/g;
}

sub ToTree($$$$) {
	my ($node, $parent, $parentel, $list) = @_;
	my $token;
	while (defined ($token = shift @$list)) {
		$token =~ s/[\r\n]//g;
		next if $token eq '';
		next if $token =~ /^<\?xml.*?>$/;
		if ($token =~ s/(^<|>$)//g) {
			if ($token =~ s/^\///) { # closing
				return $node;
			} else { # opening
				my $newnode = {};
				if (exists $node->{$token} and not ref($node->{$token}) eq 'ARRAY') {
					my $sibling = $node->{$token};
					$node->{$token} = [$sibling,$newnode];
				} elsif (exists $node->{$token} and ref($node->{$token}) eq 'ARRAY') {
					push @{$node->{$token}}, $newnode;
				}
				if (exists $node->{$token}) {
					ToTree($newnode,$node,$token,$list);
				} else {
					$node->{$token} = $newnode;
					ToTree($newnode,$node,$token,$list);
				}
			}
		} else { # content
			$parent->{$parentel} = $token;
		}
	}
	return $node;
}

sub Parse($) {
	my @l = ShallowParser(shift);
	my $tree = {};
	ToTree($tree,undef,undef,\@l);
	return $tree;
}

1;

package main;

use constant HEADER_SIZE        => 2;
use constant DELIMITER          => "\0";
use constant UINT16_PACK_FORMAT => "n";
use constant UINT32_PACK_FORMAT => "N";

my $generation_path = "/tmp/passenger.1.0.9877/generation-0";

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

my $stats = XMLParser::Parse($xml);
$Data::Dumper::Indent = 1;
print Dumper($stats);
exit;
