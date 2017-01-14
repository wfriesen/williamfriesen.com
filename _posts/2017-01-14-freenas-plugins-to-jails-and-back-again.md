---
layout: post
title:  "FreeNAS - Plugins to Jails and Back Again"
date:   2017-01-14 19:24:41 +1000
tags: [freenas]
---

Some time ago the cheap USB flash drive that I ran the FreeNAS OS on died, requiring me to re-install (this time to 2, mirrored, flash drives) and re-import a backup of my settings. This mostly recovered everything, with the exception that all of the plugins I had previously installed were not recognised as plugins, just standard jails. For most services this didn't matter, since they simply run from a git repository and update themselves accordingly, but for services like [SABnzbd](https://sabnzbd.org/) this left me with no easy "update plugin" method of upgrading to newer versions as they are released.

<!--more-->

There is a relevant bug filed against FreeNAS [here](https://bugs.ixsystems.com/issues/7447), marked as "Not To Be Fixed", so it seems the only solution is to re-create each plugin, export the appropriate settings/files from the old jail, and import into the new one. This post will cover the process for each of these plugins:

- [SABnzbd](#sabnzbd)
- [Sonarr](#sonarr)
- [CouchPotato](#couchpotato)
- [Headphones](#headphones)
- [Mylar](#mylar)

## Common Stuff

All of these processes will require installing a new plugin, and adding the same storage links that exist in the old jail. I also changed the IP address of each of the old jails to avoid a conflict, and then updated the plugin jail's IP address to match the original one, so that I didn't have to then change any settings to link all of the services back together. The new plugins can then be used as a drop-in replacement of the old jails.

Just in case I missed something, I'm going to keep the old jails around for now, but set them to not autostart on system boot.

Most of these plugins require some variation on the same process:

- archive the settings within the current jail, storing it outside the jail
- stop the jail, install and start the plugin
- extract the archive to the plugin jail, and fix permissions/ownership

For completeness, and to further document my setup in case something goes very wrong in future, these steps are expanded out for each service below.

<a name="#sabnzbd"/>

## SABnzbd

All of the relevant configuration is stored in `/var/db/sabnzbd/sabnzbd.ini`, so first make a copy of that file. From the FreeNAS web GUI, stop the old jail, and install the new plugin. Start up the plugin, so that it will create the new config file, then stop the plugin. Copy all of the contents from the backup into the new file in the plugin jail so that the permissions created by the initial startup are retained, then start the plugin and you're good to go.

This method does not retain the download history/stats, but for my purposes I'm OK with that. The more pressing concern at the moment was to get rid of the "Update Available!" message on the web interface.

<a name="#sonarr"/>

## Sonarr

Sonarr has a handy backup feature, documented [here](https://github.com/Sonarr/Sonarr/wiki/Backup-and-Restore).

Under the System -> Backup menu, click the "Backup" button to create an up-to-date backup, then download it through the web UI.

Stop the sonarr jail, install the new plugin and start up the service. Go to the web UI and find the AppData directory location listed under the System menu. In my case this was `/var/db/sonarr`.

Stop the sonarr service, copy the backup zip to the AppData directory inside the jail, then open a shell inside the jail and run the following:

{% highlight bash %}
cd /var/db/sonarr
rm config.xml nzbdrone.db*
unzip nzbdrone_backup_*.zip
chown media config.xml nzbdrone.db
{% endhighlight %}

Restart the plugin service, then visit the web interface to confirm that everything imported correctly. Most likely Sonarr will attempt to update itself since the version included in the plugin will be behind the Sonarr git repository.

<a name="#couchpotato"/>

## CouchPotato

Open a shell inside the old jail, and run these commands to backup the relevant data:

{% highlight bash %}
cd /var/db/couchpotato
tar cvf ../couchpotato.tar .
{% endhighlight %}

Then move the .tar created at `/var/db/couchpotato.tar` to somewhere outside the jail. Stop the jail, install the new plugin, setup the same storage, start the plugin service then stop it again so that the initial setup is performed. Then inside the plugin jail move the .tar file to `/var/db/couchpotato.tar` and run:

{% highlight bash %}
cd /var/db/couchpotato
rm -rf ./*
tar xvf ../couchpotato.tar
chown -R media .
{% endhighlight %}

Start up the plugin service and confirm that the web UI looks like it imported everything properly.

<a name="#headphones"/>

## Headphones

In a shell in the headphones jail:

{% highlight bash %}
service headphones stop
cd /var/db
tar cvf headphones.tar headphones
{% endhighlight %}

Move headphones.tar outside the jail, stop the jail, install the plugin and setup storage and it's IP address. Inside the jail, copy the archive to `/var/db/headphones.tar` and run this:

{% highlight bash %}
cd /var/db
tar xvf headphones.tar
{% endhighlight %}

Start up the plugin service, check the web UI and apply any available updates.


<a name="#mylar"/>

## Mylar

In a shell within the mylar jail, run:

{% highlight bash %}
service mylar stop
cd /var/db
tar cvf mylar.tar mylar
{% endhighlight %}

Then move the created mylar.tar outside the jail, stop the jail, install the plugin, setup storage and IP addresses, start the plugin jail, copy the archive to `/var/db/mylar.tar` and run this inside a shell in the plugin jail:

{% highlight bash %}
cd /var/db
tar xvf mylar.tar
{% endhighlight %}

Start up the service, check out the web UI, and update as necessary.

## Last Things Last

Now that everything is re-plugin-ified, it should be easy enough to update the plugins if/when an update is available. I'll keep the original jails around for a while in case something goes bad, but so far so good.
