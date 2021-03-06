#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use 5.10.0;
use Data::Dumper;
use Readonly;
use HTML::TreeBuilder::XPath;
use LWP::Simple;
use CGI::Fast;
use POSIX qw(strftime);

binmode STDOUT, 'utf8';

Readonly my $BASEURL => 'https://twitter.com';


while (my $q = CGI::Fast->new) {
	my $user = $q->param('user') || 'ciderpunx';

	$user = lc $user;
	# die if $user eq 'KaleTicaret1979' || $user eq 'pastasanati' || $user eq 'weightloss';
	die if $user =~ '^#';

	$user=~s/(@|\s)//g;
	$user=~s/%40//g;

	my $max_age=1800;

	open my $in, '<', 'heavy_users' or die 'No heavy_users file';
	my @heavy_users = <$in>;
	close $in;

	$max_age = '86400' if grep {/$user/} @heavy_users; 

	my $replies = $q->param('replies') || 0;

	my $url = "$BASEURL/$user";
	$url .= "/with_replies" if $replies;



	open my $out, '>>', 'twitter_rss_uses' or die 'No twitter rss uses file';
	print $out (localtime time) . " $user\n";
	close $out;

	my $content = get("$BASEURL/$user");
	unless (defined $content) {
		err('Can&#8217;t screenscrape Twitter');
		next;
	}


	my @items;

	my $tree= HTML::TreeBuilder::XPath->new;
	$tree->parse($content);
	my $tweets = $tree->findnodes( '//li' . class_contains('js-stream-item') );  

	for my $li (@$tweets) {    
		my $tweet = $li->findnodes('./div' 
																. class_contains("tweet") 
																. '/div' 
																. class_contains("content") )->[0]
		;
		my $header = $tweet->findnodes('./div' . class_contains("stream-item-header"))->[0];
		my $body   = $tweet->findvalue('./p' . class_contains("tweet-text"));
		$body = "<![CDATA[$body]]>";
		my $avatar = $header->findvalue('./a/img' . class_contains("avatar") . "/\@src"); 
		my $fullname = $header->findvalue('./a/strong' . class_contains("fullname"));
		my $username = '@' . $header->findvalue('./a/span' . class_contains("username") . '/b');
		my $uri = $BASEURL . $header->findvalue('./small' 
																. class_contains("time") 
																. '/a'
																. class_contains("tweet-timestamp") 
																. '/@href'
		);  
		my $timestamp = $header->findvalue('./small' 
										. class_contains("time") 
										. '/a'
										. class_contains("tweet-timestamp") 
										. '/span/@data-time'
		);  

		my $pub_date = strftime("%a, %d %b %Y %H:%M:%S %z", localtime($timestamp));

		push @items, {
			username => $username,
			fullname => $fullname,
			link => $uri,
			guid => $uri,
			title => $body,
			description => $body,
			timestamp => $timestamp,
			pubDate => $pub_date
		}
	}
	$tree->delete; 


	# now print as an rss feed, with header
print<<ENDHEAD
Content-type: application/rss+xml
Cache-control: max-age=$max_age

<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:atom="http://www.w3.org/2005/Atom" xmlns:georss="http://www.georss.org/georss" xmlns:twitter="http://api.twitter.com" version="2.0">
  <channel>
    <title>Twitter Search / $user </title>
    <link>http://twitter.com/$user</link>
    <description>Twitter feed for: $user.</description>
    <language>en-us</language>
    <ttl>40</ttl>
ENDHEAD
;

for (@items) {
  print<<ENDITEM
    <item>
      <title>$_->{username}: $_->{title}</title>
      <description>$_->{description}</description>
      <pubDate>$_->{pubDate}</pubDate>
      <guid>$_->{guid}</guid>
      <link>$_->{link}</link>
      <twitter:source/>
      <twitter:place/>
    </item>
ENDITEM
;
}

print<<ENDRSS
  </channel>
</rss>      
ENDRSS
;
}

sub class_contains {
  my $classname = shift;
  "[contains(concat(' ',normalize-space(\@class),' '),' $classname ')]";
}

sub err {
	my $msg = shift;
	print<<ENDHEAD
Content-type: text/html
Cache-control: max-age=86400
Refresh: 5; url=http://twitrss.me

<html><head></head><body><h2>ERR: $msg</h2><p>Redirecting you back to <a href="http://twitrss.me">TwitRSS.me</a> in a few seconds. You might have spelled the username wrong or something</p></body></html>
ENDHEAD
;
}
