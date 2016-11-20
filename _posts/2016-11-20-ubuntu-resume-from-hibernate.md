---
layout: post
title:  "Ubuntu Network Issues After Hibernating"
date:   2016-11-20 18:43:41 +1000
tags: [ubuntu, systemd, hibernate, suspend]
---

I recently installed Ubuntu Gnome 16.10 onto my Dell XPS 13 (9350), and while most things are working fine out of the box, hibernating has caused some pain.

<!--more-->

Firstly, I wanted my laptop to hibernate after closing the lid. The Power settings don't include anything like that, but dconf does. Running the dconf Editor, the relevant keys to change are:

{% highlight bash %}
lid-close-ac-action
lid-close-battery-action
{% endhighlight %}

Setting both of these to `hibernate` gets the lid close actions to where I want them to be.

After opening the lid again, however, it seems that the network interfaces are no longer working. Chrome would throw up a `DNS_PROBE_FINISHED_BAD_CONFIG` error when visiting any page, and any other internet activity would similarly fail. The local network is unaffected.

Running `sudo service network-manager restart` would temporarily fix the issue, but I don't want to have to run that after every hibernation.

Some Googling provided a bunch of different possible solutions, most of them being various ways to restart the network service after hibernation. The [one that worked for Ubuntu Gnome 16.10](http://askubuntu.com/questions/452826/wireless-networking-not-working-after-resume-in-ubuntu-14-04#comment1283721_748084) was to create a file (I named it `restart_network`) in `/lib/systemd/system-sleep/` with the following contents:

{% highlight bash %}
#!/bin/sh

case $1 in
    post)
        service network-manager restart
        ;;
esac
{% endhighlight %}

and then make it executable with:

{% highlight bash %}
sudo chmod +x /lib/systemd/system-sleep/restart_network
{% endhighlight %}
