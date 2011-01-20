use strict;
use warnings;

package RSSBot;
use base qw (Bot::BasicBot);
use LWP::UserAgent;
use Storable;
use FindBin;
use XML::Feed;

sub init {
    # used for configuration file parsing 
    my ($self) = @_;
    $self->{status_file} = $FindBin::Bin."/rss-bot.dat";
    $self->{last_check} = "";

    if (-e $self->{status_file}) {
        $self->{last_check}= retrieve($self->{status_file});
    }
    return 1;
}

sub _check_feeds {

    my ($self) = @_;
    my $cf = ${$self->{config}};
    $self->{tick_timeout} = $cf->{timeout};
    use Data::Dumper ; print Dumper $cf;

    # for each defined feed, fetch it and load it into memory in $self->{last_entries}
    # using the timestamp in form YYYYmmddHHMM as hash key
    foreach my $f (@{$cf->{feeds}}) {

        my $url=$f->{url};
        if(not defined $self->{last_check}->{$url}) {
            $self->{last_check}->{$url} = DateTime->now->subtract(hours => 5);
        }

        my $ua = LWP::UserAgent->new(keep_alive => 5, timeout => 30);
        if (defined $f->{username} or defined $f->{password}) {
            # extract hostname and port
            my ($host, $port);
            if ($f->{url} =~ /^https?:\/\/(.*):(.*)\// ) {
                ($host, $port) = ($1, $2);
            }
            $ua->credentials( $host.":".$port, "protected-area", $f->{username} => $f->{password} );
        }
        $ua->agent("Newbay RSS Bot/0.1 ");
        $ua->timeout(30);

        my $res = $ua->get($url);
        if($res->is_success) {
            my $xmlfile = $res->content;
            my $feed = XML::Feed->parse(\$xmlfile) or die XML::Feed->errstr;
            for my $e ($feed->entries) {
                my $timestamp = $e->issued->strftime("%Y%m%d%H%M");
                $self->{last_entries}->{$timestamp}->{title}=$e->title;
                $self->{last_entries}->{$timestamp}->{link}=$e->link;
                $self->{last_entries}->{$timestamp}->{author}=$e->author;
                $self->{last_entries}->{$timestamp}->{issued}=$e->issued;
                $self->{last_entries}->{$timestamp}->{channels}=$f->{channels};
                $self->{last_entries}->{$timestamp}->{feed_url}=$f->{url};
           }
        } else {
            print STDERR "[ERROR]: Problem fetching $url\n";
        }
    }

    # now browse the sorted entries
    foreach my $e (sort keys(%{$self->{last_entries}})) {

        my $url = $self->{last_entries}->{$e}->{feed_url};

        #if $url does not exist in $cf->{feeds} skip it
        my $res = grep { $_->{url} eq $url } @{$cf->{feeds}};
        next unless $res>0;

        printf "entry date: %s, %s\n",$self->{last_entries}->{$e}->{issued}->strftime("%d/%m/%Y %H:%M"),$self->{last_entries}->{$e}->{issued}->epoch();
        printf "last check date: %s, %s\n",$self->{last_check}->{$url}->strftime("%d/%m/%Y %H:%M"),$self->{last_check}->{$url}->epoch();
        print "datediff: ",$self->{last_entries}->{$e}->{issued}->epoch()-$self->{last_check}->{$url}->epoch(),"\n";
        print "feed title: ",$self->{last_entries}->{$e}->{title},"\n\n";

        if( $self->{last_check}->{$url}->epoch() < $self->{last_entries}->{$e}->{issued}->epoch() ) {
            print "it's a new feed \n";
            my $msg = sprintf ("%s @ %s UTC - %s [ %s ]", 
                $self->{last_entries}->{$e}->{author},
                $self->{last_entries}->{$e}->{issued}->strftime("%d/%m/%Y %H:%M"), 
                $self->{last_entries}->{$e}->{title},
                $self->{last_entries}->{$e}->{link});
            foreach my $c (@{$self->{last_entries}->{$e}->{channels}}) {
                #print "channel $c : $msg\n";
                $self->say( channel => $c, body => "$msg");
            }
            $self->{last_check}->{$url} = DateTime->now;
            store($self->{last_check}, $self->{status_file});;
        }
    }
}

sub tick {

    my ($self) = @_;

    # http get feed
    $self->_check_feeds();

    return $self->{tick_timeout};
}

1;
