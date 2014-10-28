SignalFuse collectd configs
===========================

About
-----

A collection of collectd configs that work well with SignalFuse.

Installation
------------

  ```
  git clone https://github.com/signalfx/signalfx-collectd-configs.git
  cd signalfx-collectd-configs
  ./install.sh /path/to/collectd
  # if you want to add another config cp it into your collectd configuration directory managed_config dir
  cp managed_config/10-bob.conf /etc/collectd.d/managed_config/
  ```

Help
----

Read the instructions at the top of each config file for how to use or debug it.
