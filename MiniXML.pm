package MiniXML;

use strict;

# Minimal XML parser.
# Author: Giuliano Cioffi <giuliano@108.bz>
# ShallowParser (taken from http://www.cs.sfu.ca/~cameron/REX.html#AppA) turns
# XML into a list of tokens. ToTree transforms the list into a parse tree.

###################
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
###################

sub ToTree {
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
				if (!exists $node->{$token}) {
					$node->{$token} = $newnode;
				}
                ToTree($newnode,$node,$token,$list);
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
