# Phusion Passenger collectd plugin
# Author: Giuliano Cioffi <giuliano at 108.bz>

package Collectd::Plugins::Passenger;

use strict;
use Collectd qw( :all );
use MiniXML;
use PassengerStatus;

sub sanitize_instance_name($) {
    my $name = shift;
    $name = substr $name, -63;
    $name =~ s|[/-]|_|g;
    $name =~ s|^_||g;
    return $name;
}

sub get_values($$;$) {
    my ($values, $type, $plugin_instance) = @_;
    my $v = {
        plugin        => 'passenger',
        type          => $type,
        values        => $values
    };
    $v->{plugin_instance} = sanitize_instance_name($plugin_instance) if $plugin_instance;
    return $v;
}

my $logged_events_count = 0;

my $global_dataset_processes = [
    {name => 'active'           , type => DS_TYPE_GAUGE  , min => 0, max => 65535},
    {name => 'count'            , type => DS_TYPE_GAUGE  , min => 0, max => 65535},
    {name => 'max'              , type => DS_TYPE_GAUGE  , min => 0, max => 65535},
    {name => 'global_queue_size', type => DS_TYPE_GAUGE  , min => 0, max => 65535},
    {name => 'groups'           , type => DS_TYPE_GAUGE  , min => 0, max => 65535},
    {name => 'processes'        , type => DS_TYPE_GAUGE  , min => 0, max => 65535}
];
my @global_dataset_processes_keys = qw/active count max global_queue_size/;

my $global_dataset_requests = [
    {name => 'processed'        , type => DS_TYPE_DERIVE, min => 0, max => 65535}
];

my $per_group_dataset_memory = [
    {name => 'private_dirty'    , type => DS_TYPE_GAUGE  , min => 0, max => 4294967295},
    {name => 'pss'              , type => DS_TYPE_GAUGE  , min => 0, max => 4294967295},
    {name => 'real_memory'      , type => DS_TYPE_GAUGE  , min => 0, max => 4294967295},
    {name => 'rss'              , type => DS_TYPE_GAUGE  , min => 0, max => 4294967295},
    {name => 'swap'             , type => DS_TYPE_GAUGE  , min => 0, max => 4294967295},
    {name => 'vmsize'           , type => DS_TYPE_GAUGE  , min => 0, max => 4294967295}
];
my @per_group_dataset_memory_keys = qw/private_dirty pss real_memory rss swap vmsize/;


my $per_group_dataset_processes = [
    {name => 'processes'        , type => DS_TYPE_GAUGE  , min => 0, max => 4294967295}
];

my $per_group_dataset_sessions = [
    {name => 'sessions'         , type => DS_TYPE_GAUGE  , min => 0, max => 4294967295}
];

my $per_group_dataset_requests = [
    {name => 'processed'        , type => DS_TYPE_DERIVE, min => 0, max => 65535}
];

sub dataset_to_typedb($$) {
    my ($name,$defs) = @_;
    my $s = sprintf "%-30s", $name;
    my %type_map = (&DS_TYPE_GAUGE=>'GAUGE', &DS_TYPE_DERIVE=>'DERIVE', &DS_TYPE_COUNTER=>'COUNTER');
    sub mm {my $v = shift; defined $v ? $v : 'U'}
    return sprintf "%-30s %s\n", ($name), (join ', ', map { "$_->{name}:$type_map{$_->{type}}:${\(mm($_->{min}))}:${\(mm($_->{max}))}" } @$defs);
}

sub passenger_read  {
    my $xml = PassengerStatus::status();
    unless (defined $xml) {
        plugin_log(PassengerStatus::last_error) if ++$logged_events_count < 10;
        return 0;
    }
    my $status = MiniXML::Parse($xml);

    my ($global_groups_count, $global_processes_count, $global_requests) = (0,0,0);
    my $groups = $status->{info}->{groups}->{group};
    $groups = [$groups] unless ref $groups eq 'ARRAY';
    foreach my $group (@$groups) {
        my $app_name = $group->{name};
        my $processes = $group->{processes}->{process};
        $processes = [$processes] unless ref $processes eq 'ARRAY';
        my @totals = ((0) x scalar(@per_group_dataset_memory_keys));
        my ($processes_count,$sessions,$requests) = (0,0,0);
        foreach my $process (@$processes) {
             foreach my $i (0..$#per_group_dataset_memory_keys) {
                    $totals[$i] += int($process->{$per_group_dataset_memory_keys[$i]});
             }
             $processes_count += 1;
             $sessions += int($process->{sessions}) if $process->{sessions};
             $requests += int($process->{processed}) if $process->{processed};
        }
        plugin_dispatch_values(get_values(\@totals,'per_group_memory',$app_name));
        plugin_dispatch_values(get_values([$processes_count],'per_group_processes',$app_name));
        plugin_dispatch_values(get_values([$sessions],'per_group_sessions',$app_name));
        plugin_dispatch_values(get_values([$requests],'per_group_requests',$app_name));
        $global_processes_count += $processes_count;
        $global_groups_count += 1;
        $global_requests += $requests;
    }
    my @globals = ();
    foreach my $key (@global_dataset_processes_keys) {
        push @globals, int($status->{info}->{$key});
    }
    push @globals, $global_groups_count;
    push @globals, $global_processes_count;
    plugin_dispatch_values(get_values(\@globals,'global_processes'));
    plugin_dispatch_values(get_values([$global_requests],'global_requests'));
    return 1;
}

=pod
The following is deprecated:
  plugin_register(TYPE_DATASET, 'global_processes'    , $global_dataset_processes);
  plugin_register(TYPE_DATASET, 'global_requests'     , $global_dataset_requests);
  plugin_register(TYPE_DATASET, 'per_group_memory'    , $per_group_dataset_memory);
  plugin_register(TYPE_DATASET, 'per_group_processes' , $per_group_dataset_processes);
  plugin_register(TYPE_DATASET, 'per_group_sessions'  , $per_group_dataset_sessions);
  plugin_register(TYPE_DATASET, 'per_group_requests'  , $per_group_dataset_requests);

Hence this has been used to generate the "types.db" entries: 
  open FH, '>/tmp/passenger_types.db';
  print FH dataset_to_typedb('global_processes'    , $global_dataset_processes);
  print FH dataset_to_typedb('global_requests'     , $global_dataset_requests);
  print FH dataset_to_typedb('per_group_memory'    , $per_group_dataset_memory);
  print FH dataset_to_typedb('per_group_processes' , $per_group_dataset_processes);
  print FH dataset_to_typedb('per_group_sessions'  , $per_group_dataset_sessions);
  print FH dataset_to_typedb('per_group_requests'  , $per_group_dataset_requests);
  close FH;
=cut

plugin_register(TYPE_READ, 'Passenger', 'passenger_read');

1;
