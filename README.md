collectd - Passenger plugin
===========================

Runs inside [collectd](http://www.collectd.org/)'s embedded Perl
interpreter, gathering statistics about [Phusion Passenger](http://www.modrails.com/) internals.
Uses the same unix socket interface than "passenger-status".

Tested on Ubuntu 10.04 LTS (i386 and amd64), collectd 4.8.2-1, Phusion Passenger 3.0.5 and 3.0.12.

Collected global metrics 
------------------------

See also the Passenger/nginx [guide](http://www.modrails.com/documentation/Users%20guide%20Nginx.html).

* `active` - The number of application instances that are currently processing requests. This value is always less than or equal to count.
* `count` - The number of application instances that are currently alive. This value is always less than or equal to max. 
* `max` - The maximum number of application instances that Phusion Passenger will spawn. This equals the value given for `PassengerMaxPoolSize` (Apache) or `passenger_max_pool_size` (Nginx). 
* `global_queue_size` - how many connections are sitting in the global queue (if enabled), waiting to be served.
* `groups` - total number of applications currently loaded in memory.
* `processes` - total number of application instances currently loaded in memory.

* `processed` - total number of requests being served per second.

Collected per-group metrics
---------------------------

Instances of the same application form a `group`.

* `private_dirty` - The private dirty RSS field shows the real memory usage of processes.
* `pss` - 
* `real_memory` -
* `rss` - 
* `swap` - 
* `vmsize` - 

* `processes` - total number of instances of the same application.

* `sessions` - total number of HTTP clients queued in each application instance.

* `processed` - total number of requests being served per second by this group.

How to install
--------------

No dependencies other than `libperl` are required.

1. Clone this repo somewhere, f.e. in `/opt/collectd-passenger`.

2. Add the following to `collectd.conf`:

Enable collectd's embedded perl interpreter.

    <LoadPlugin "perl">
      Globals true
    </LoadPlugin>
    LoadPlugin perl

On collectd clients and servers, add support for the plugin's types. You'll also need to list the default `types.db`.

    TypesDB "/usr/share/collectd/types.db"
    TypesDB "/opt/collectd-passenger/passenger_types.db"

Enable the plugin.

    <Plugin perl>
      IncludeDir "/opt/collectd-passenger"                                                
      BaseName "Collectd::Plugins"
      LoadPlugin "Passenger"
    </Plugin>
