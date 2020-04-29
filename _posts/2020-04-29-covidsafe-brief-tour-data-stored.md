---
layout: post
title:  "Australia's COVIDSafe App: A Brief Tour of the Data Stored"
date:   2020-04-29
tags: [covidsafe, covid19, android, sql, sqlite, encryption]
---

The Australian government released it's own contact tracing app last weekend, and while it is claimed that they will release the source code, that has not happened yet. Plenty has already been written about how we are told it works, and there is some great work being done on the [decompiled code](https://github.com/ghuntley/COVIDSafe_1.0.11.apk) by [@GeoffreyHuntley](https://twitter.com/GeoffreyHuntley) and others to document how it does work. I'm not digging into the code much myself, but I did examine some of the data stored on my own device.

To start with I took a rooted Android phone and installed the [COVIDSafe](https://play.google.com/store/apps/details?id=au.gov.health.covidsafe&hl=en_US) app. I also installed it on another phone, and left them next to each other to commune for a while and collect some data.

From the package name, `au.gov.health.covidsafe`, we know that it can store data in `/data/data/au.gov.health.covidsafe`. Root access is needed to read this directory, so I plugged the rooted phone into a computer and pulled that directory for further inspection:

```sh
 ~/code/covid $ adb shell "su -c 'tar cf - /data/data/au.gov.health.covidsafe'" | tar xf -
removing leading '/' from member names
 ~/code/covid $ tree data/data/au.gov.health.covidsafe
data/data/au.gov.health.covidsafe
├── cache
├── code_cache
├── databases
│   ├── record_database
│   ├── record_database-shm
│   └── record_database-wal
├── files
│   └── packet
└── shared_prefs
    ├── embryo.xml
    └── Tracer_pref.xml

5 directories, 6 files
```

The databases directory contains a single SQLite database along with it's logs. With some whitespace reformatting, it has this basic structure:

```sql
SQLite version 3.31.1 2020-01-27 19:55:54
Enter ".help" for usage hints.
sqlite> .tables

android_metadata
record_table
room_master_table
status_table

sqlite> .schema android_metadata
CREATE TABLE android_metadata (
  locale TEXT
);
sqlite> .schema record_table
CREATE TABLE `record_table` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `timestamp` INTEGER NOT NULL
, `v` INTEGER NOT NULL
, `msg` TEXT NOT NULL
, `org` TEXT NOT NULL
, `modelP` TEXT NOT NULL
, `modelC` TEXT NOT NULL
, `rssi` INTEGER NOT NULL
, `txPower` INTEGER
);
sqlite> .schema room_master_table
CREATE TABLE room_master_table (
  id INTEGER PRIMARY KEY
, identity_hash TEXT
);
sqlite> .schema status_table
CREATE TABLE `status_table` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
, `timestamp` INTEGER NOT NULL
, `msg` TEXT NOT NULL
);
```

The `android_metadata` table isn't all that interesting

```sql
sqlite> .headers on
sqlite> select * from android_metadata;
locale
en_AU
```

`room_master_table` stores information about a [Room](https://developer.android.com/training/data-storage/room), an Android provided abstraction over SQLite, and doesn't store much.

```
sqlite> select * from room_master_table;
id|identity_hash
42|XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

That ID is curious, though. The [decompiled source](https://github.com/ghuntley/COVIDSafe_1.0.11.apk/blob/46dba04dc1ad121a58ecf36646d0ce8749eda6e0/apk2gold-reloaded/COVIDSafe_1.0.11/src/sources/androidx/room/RoomMasterTable.java#L7) of `androidx/room/RoomMasterTable.java` reveals that one of the developers is a Hitchhiker's Guide fan:

```java
    public static final String DEFAULT_ID = "42";
```

They also aren't too fussed about data types, since this Java `String` is being persisted to the database as an `INTEGER`.

`status_table` logs when bluetooth scanning starts and stops, and it had quite a lot of records:

```sql
sqlite> select * from status_table limit 4;
id|timestamp|msg
1|1588065769226|Scanning Started
2|1588065777229|Scanning Stopped
3|1588065819972|Scanning Started
4|1588065827980|Scanning Stopped
```

The timestamps here are stored to the millisecond. It scans roughly once per minute, and from looking further the longer breaks matched up with when the screen was off.

```sql
sqlite> with q as (
   ...>   select
   ...>    (lead(timestamp, 1, NULL) over (order by id) - timestamp) / 1000 diff
   ...>   from status_table
   ...>   where msg = 'Scanning Started'
   ...> )
   ...>  select
   ...>   avg (diff)
   ...> , min(diff)
   ...> , max(diff)
   ...> from q;
avg (diff)|min(diff)|max(diff)
62.3049886621315|44|841
```

`record_table` is where interactions with other devices are recorded.

(Note that while I've redacted the `msg` values, I've kept their lengths and uniqueness in tact.)

```sh
sqlite> .headers ON
sqlite> select * from record_table limit 5;
id|timestamp|v|msg|org|modelP|modelC|rssi|txPower
1|1588065902522|1|AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA|AU_DTA|LG-H990|ONEPLUS A6003|-48|
2|1588065905633|1|AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA|AU_DTA|ONEPLUS A6003|LG-H990|-58|
3|1588066045043|1|AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA|AU_DTA|LG-H990|ONEPLUS A6003|-54|
4|1588066146769|1|BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB|AU_DTA|ONEPLUS A5010|ONEPLUS A6003|-95|
5|1588066289884|1|AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA|AU_DTA|LG-H990|ONEPLUS A6003|-30|
```

There's some accounting stuff, like `id`, `timestamp`, `v` (version?), and the repeated value of `org` being `AU_DTA` (I'm guessing because this app was released for AUstralia by the Digital Transformation Agency).

There is also some Bluetooth signal information in `rssi` and `txPower`. `rssi` is the Received Signal Strength Indication, a measure of the signal power, and can be a good measure of distance between devices. All of my `txPower` values are `NULL`.

`msg` presumably holds the encrypted temporary ID's being exchanged between devices.

Here we see the same (redacted) temp IDs being repeatedly exchanged over time until they are rotated out of use.

```sql
sqlite> select msg, count(*) from record_table group by msg;
msg|count(*)
BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB|6
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA|38
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC|6
DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD|26
```

`modelP` and `modelC` are the device models that are communicating, stored in glorious plaintext. As you can see, I tested this using a OnePlus 6 (`ONEPLUS A6003`), and an LG V20 (`LG-H990`), specifically the H990DS model.

As for the remaining files, `files/packet` contains 120 characters of base64-encoded binary data, which from a cursory grep'ing seems to come from a Bluetooth broadcast, maybe one of the temporary IDs? I haven't looked into it much other than to confirm that it is base64, and decodes to 89 bytes:

```sh
 ~/code/covid $ base64 --decode data/data/au.gov.health.covidsafe/files/packet | wc -c
89
```

`shared_prefs` contains some user settings and UI related stuff. Examples are shown here, with sensitive/encrypted parts redacted.

`embryo.xml`

```xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <int name="layout_fail_decor" value="-1" />
    <boolean name="hwui" value="true" />
    <string name="layout_name_main">au.gov.health.covidsafe:layout/activity_onboarding</string>
    <int name="layout_theme_main" value="2132017394" />
    <int name="layout_fail_main" value="-1" />
    <int name="layout_decor" value="17367271" />
    <int name="layout_theme_decor" value="2132017394" />
    <boolean name="layout_preload_main" value="true" />
    <boolean name="layout_preload_decor" value="true" />
    <string name="layout_name_decor">android:layout/screen_simple</string>
    <int name="layout_main" value="2131558430" />
</map>
```

`shared_prefs/Tracer_pref.xml`

```xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <long name="NEXT_FETCH_TIME" value="XXXXXXXXXXXXX" />
    <long name="EXPIRY_TIME" value="XXXXXXXXXXXXX" />
    <string name="__androidx_security_crypto_encrypted_prefs_key_keyset__">XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX</string>
    <string name="POST_CODE">XXXX</string>
    <string name="__androidx_security_crypto_encrypted_prefs_value_keyset__">XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX</string>
    <string name="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX">XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX</string>
    <string name="PHONE_NUMBER">XXXXXXXXXXXX</string>
    <boolean name="IS_ONBOARDED" value="true" />
    <string name="DEVICE_ID">XXXXXXXXXXXXXXXX</string>
    <string name="NAME">XXXXXXXXXXXXXXX</string>
    <string name="AGE">XX</string>
</map>
```

And that's it. I've only included the data that came from my own devices, but from the limited time that I ran this in my apartment I also saw model values of `ONEPLUS A5010` for a OnePlus 5T, a device I remember from previously scanning bluetooth when pairing devices. This appeared in 6 of the 76 records I collected, so it's likely a neighbour's signal is peeking through the walls of my building, hovering around the power threshold.

The app is set to delete these records after 22 days, but as an avid data hoarder I will likely dump it periodically for safe keeping. It will make for a nice log of devices I come within sneezing range of.
