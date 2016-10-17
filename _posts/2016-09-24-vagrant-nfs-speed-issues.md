---
layout: post
title:  "Vagrant NFS Speed Issues"
date:   2016-09-24 13:15:00 +1000
tags: [vagrant, nfs, ubuntu]
---

Web development with vagrant can be a joy, but sharing files between a Virtual Box VM and the host machine has it's quirks. Some Googling would tell you that simply using NFS will solve all your speed issues, but on my Ubuntu host/Ubuntu guest setup I'm still seeing extremely slow file accesses. What's going on here?

<!--more-->

Firstly, let's start with a simple Vagrant file, exporting an NFS share from the host and mounting in the guest:


{% highlight ruby %}
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = "ubuntu/trusty64"

  config.vm.network "private_network", ip: "192.168.90.100"
  config.vm.synced_folder "./data/", "/home/vagrant/data", type: 'nfs', create: true, :linux__nfs_options => ["rw","no_root_squash","no_subtree_check"]
end
{% endhighlight %}

Now we'll `vagrant ssh` and write ~800MB of zeroes to the shared folder:

{% highlight bash %}
vagrant@vagrant-ubuntu-trusty-64:~$ dd if=/dev/zero of=/home/vagrant/data/output bs=8k count=100k
102400+0 records in
102400+0 records out
838860800 bytes (839 MB) copied, 20.2814 s, 41.4 MB/s
{% endhighlight %}

This doesn't seem too speedy. Let's invert the NFS configuration here. Instead of exporting from the host and mounting in the guest, we'll export from the guest and mount in the host. First install the [vagrant-nfs_guest](https://github.com/Learnosity/vagrant-nfs_guest) plugin that serves just this purpose:

`vagrant plugin install vagrant-nfs_guest`

and then modify the NFS config to change the `type` to `nfs_guest`.

{% highlight ruby %}
  config.vm.synced_folder "./data/", "/home/vagrant/data", type: 'nfs_guest', create: true, :linux__nfs_options => ["rw","no_root_squash","no_subtree_check"]
{% endhighlight %}

Now we `vagrant reload`, and run the same test again:

{% highlight bash %}
vagrant@vagrant-ubuntu-trusty-64:~$ dd if=/dev/zero of=/home/vagrant/data/output bs=8k count=100k
102400+0 records in
102400+0 records out
838860800 bytes (839 MB) copied, 0.825531 s, 1.0 GB/s
{% endhighlight %}

Much better. This shows roughly a 25-fold improvement.

For sake of comparison, here's the results of the same test running directly on the host machine:

{% highlight bash %}
william@william-XPS-13-9350 ~/c/williamfriesen.com> dd if=/dev/zero of=/tmp/output bs=8k count=100k
102400+0 records in
102400+0 records out
838860800 bytes (839 MB, 800 MiB) copied, 0.479585 s, 1.7 GB/s
{% endhighlight %}

And here when using a plain old VirtualBox shared folder, with the following config in the `Vagrantfile`:

{% highlight ruby %}
  config.vm.synced_folder "./data/", "/home/vagrant/data", create: true
{% endhighlight %}

{% highlight bash %}
vagrant@vagrant-ubuntu-trusty-64:~$ dd if=/dev/zero of=/home/vagrant/data/output bs=8k count=100k
102400+0 records in
102400+0 records out
838860800 bytes (839 MB) copied, 6.70526 s, 125 MB/s
{% endhighlight %}

And just because I love a good chart, here's a visual representation of these numbers:

![NFS Config Speed Test Results]({{ site.url }}/assets/vagrant-nfs-speed-issues/test-results.svg)

A major wrinkle here is that since we are storing our files within the VM now, they will not be available on the host while the VM is powered off. This may be a deal-breaker, but for a quick-and-dirty fix for your vagrant NFS woes, this is something to consider.
