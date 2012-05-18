collectd - Passenger plugin
===========================

Runs inside [collectd](http://www.collectd.org/)'s embedded Perl
interpreter, gathering statistics about [Phusion Passenger](http://www.modrails.com/) internals.
Uses the same unix socket interface than "passenger-status".

Collected global metrics (quoting Passenger nginx [guide](http://www.modrails.com/documentation/Users%20guide%20Nginx.html)):

* `active` - The number of application instances that are currently processing requests. This value is always less than or equal to count.
* `count` - The number of application instances that are currently alive. This value is always less than or equal to max. 
* `max` - The maximum number of application instances that Phusion Passenger will spawn. This equals the value given for `PassengerMaxPoolSize` (Apache) or `passenger_max_pool_size` (Nginx). 
* `global_queue_size` - how many connections are sitting in the global queue (if enabled), waiting to be served.
* `groups` - number of applications (not application instances) that are currently in memory.
* `processes` - sum of all the application instances, as counted by the plugin. Should always be equal to `active`

* `processed` - total number of requests being served per second.

Instances of the same application form a `group`. Collected per-group metrics:

* `private_dirty` - The private dirty RSS field shows the real memory usage of processes.
* `pss` - 
* `real_memory` -
* `rss` - 
* `swap` - 
* `vmsize` - 

* `processes` - total number of instances of the same application.

* `sessions` - total number of HTTP clients queued in each application instance.

* `processed` - total number of requests being served per second, by this group.

