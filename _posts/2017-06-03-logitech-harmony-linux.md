---
layout: post
title:  "Configuring a Logitech Harmony Remote From Linux (Sort Of)"
date:   2017-07-09 13:26:20 +1000
tags: [linux, windows, virtualbox, logitech, harmony, remote]
---

I recently bought another Logitech Harmony universal remote (the 650 model). This post outlines the struggles of configuring this from Linux.

# Initial Setup/Discouragement

After loosing the remote from its clam shell prison, the included instructions direct you to [setup.myharmony.com](https://setup.myharmony.com) in order to download the software to configure the remote. Only Windows and Mac versions are available, but the site mentions a legacy web-based setup which sounded (slightly) more promising. After clicking through and logging in, I'm greeted with this error:

![Your Legacy Is Nothing]({{ site.url }}/assets/logitech-harmony/legacy-removed.png)

It would seem that in this case "legacy" means "non-existent". Working mostly on legacy codebases in my day job, I often agree with that sentiment.

# Con-Sarn It!

After Googling around, two Linux-focused projects spring up. [Concordance](https://github.com/jaymzh/concordance), a CLI application that does the heavy lifting of interfacing with the remote, and [Congruity](https://sourceforge.net/projects/congruity/), a GUI for Concordance. While installing Concordance was easy enough, I came up against some dependency issues when installing Congruity. Oh, well. Who needs a GUI anyway?

I quickly realized that, for this process, _I_ need a GUI. Concordance provides the lower level communication, allowing you to read and write the configuration and firmware of the device, but you're on your own as to actually obtaining this configuration for your make and model of TV/Cable Box/Whatever. In bygone days this would be available from the MyHarmony website, but those days are long (by)gone.

I was able to dump the factory config with:

```
$ concordance --dump-config=/tmp/config.EZHex
```

The configuration file appears to be an XML document with a binary blob stuck on the end. A quick run through `strings` didn't yield much of interest, but the XML contains this little nugget of header values that presumably would be sent with every request:

![Cookie Cookie Cookie]({{ site.url }}/assets/logitech-harmony/cookie.png)

At this point I gave up trying to fit a square peg into a penguin-shaped hole. There's a lot I will do to avoid Windows, but this was already encroaching upon valuable TV time.

# Bugger It, Just Use Windows

Using the MyHarmony software from a VirtualBox virtual machine was simple enough, but there were a couple of hiccups.

In order for VirtualBox to see a USB device, you need to be a member of the `vboxusers` group. Add the user `william` with:

```
sudo gpasswd -a william vboxusers
newgrp vboxusers
```

For the VM to then see a given USB device, the VirtualBox Devices menu can be used to mount it.

All that's left is to copy over the MyHarmony software and run though it. After configuring as you will, syncing the changes to the remote hung at 99%, producing this message:

![Sync Stuck At 99%]({{ site.url }}/assets/logitech-harmony/sync-99.png)

At 99% through, the remote will reboot. You will need to quickly get past this strange concept, and re-mount the remote from the Devices menu before it times out in order to see a nice 100% message.

While I didn't send any feedback, I would definitely recommend this remote over the weird little egg-mote that came with my TV. That Cookie Monster reference alone is worth every cent.
