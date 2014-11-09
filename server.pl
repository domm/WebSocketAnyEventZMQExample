package My::Server;
use 5.18.1;
use Twiggy::Server;
use Plack::App::WebSocket;
use ZMQx::Class;
use AnyEvent;
use JSON::XS qw(encode_json decode_json);

my %events;
my @connections;

sub run {
    my ($class) = @_;

    my $server = Twiggy::Server->new(
        host => '127.0.0.1',
        port => 4040,
    );

    my $app = Plack::App::WebSocket->new(
        on_error => sub {
            my $env = shift;
            say $env->{"plack.app.websocket.error"};
            return [
                500,
                [ "Content-Type" => "text/plain" ],
                [ "Error: " . $env->{"plack.app.websocket.error"} ]
            ];
        },
        on_establish => sub {
            my $conn = shift;
            my $env  = shift;

            my $key = "" . $conn;
            say "New client connected: " . $key;
            push( @connections, $conn );

            $conn->on(
                message => sub {
                    my ( $conn, $rawmsg ) = @_;
                    my $msg    = decode_json($rawmsg);
                    my $method = 'handle_' . $msg->{type};
                    if ( $class->can($method) ) {
                        $class->$method( $conn, $msg );
                    }
                    else {
                        say "Got unsupported message type $msg";
                        $conn->send(
                            encode_json(
                                {   type    => 'error',
                                    message => 'unknown type ' . $msg->{type}
                                }
                            )
                        );
                    }
                },
                finish => sub {
                    undef $conn;
                    delete $events{$key};
                    say "Client $key disconnected";
                },
            );
        }
    )->to_app;

    my $receiver = ZMQx::Class->socket( 'SUB', bind => 'tcp://*:4041' );
    $receiver->subscribe('');
    say "set up SUB receiver at " . $receiver->get_last_endpoint;

    my $sub_watcher = $receiver->anyevent_watcher(
        sub {
            while ( my $msg = $receiver->receive ) {
                foreach my $c (@connections) {
                    $c->send(
                        encode_json(
                            {   type  => 'increment',
                                key   => $msg->[0],
                                value => $msg->[1] || 1
                            }
                        )
                    );
                }
            }
        }
    );

    my $stopit = sub {
        say "Server stopped";
        exit 1;
    };
    my @stopper;
    foreach (qw(INT HUP TERM KILL)) {
        push( @stopper, AnyEvent->signal( signal => $_, cb => $stopit ) );
    }

    $server->register_service($app);

    say "Server started up on 4040";
    AnyEvent->condvar->recv;
}

sub collect_current_data {
    my $class = shift;

    return {
        verified_user   => 100,
        unverified_user => 7,
        participations  => 2_000,
        points_gained   => 100_000,
        points_spent    => 80_000,
    };
}

sub handle_setup {
    my ( $class, $conn, $msg ) = @_;
    my $key = "" . $conn;

    my $data = $class->collect_current_data;
    $conn->send(
        encode_json(
            {   type        => 'setup',
                startuptime => scalar localtime(),
                data        => $data
            }
        )
    );

    return 1;
}

1;

package main;
My::Server->run;

