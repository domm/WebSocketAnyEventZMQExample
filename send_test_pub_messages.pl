use strict;
use warnings;
use 5.018;

use ZMQx::Class;

my $endpoint = shift @ARGV;
my $publisher = ZMQx::Class->socket( 'PUB', connect => $endpoint );

# it takes a short time for the publisher to set up
select(undef,undef,undef,0.1);

my @msg = @ARGV;
if (@msg) {
    say "sending ".join(' - ',@msg);
    $publisher->send(\@msg);
}
else {
    for my $val (1..10) {
        $publisher->send(["verified_user", $val]);
        say "sending $val";
        sleep(1);
    }
}

1;
