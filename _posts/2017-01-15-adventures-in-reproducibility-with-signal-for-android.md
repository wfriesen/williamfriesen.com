---
layout: post
title:  "Adventures in Reproducibility with Signal for Android"
date:   2017-01-15 19:12:29 +1100
tags: [signal, android, encryption, docker]
---

Earlier this year, [Open Whisper Systems announced](https://whispersystems.org/blog/reproducible-android/) that their Signal Private Messenger application now supports reproducible builds for their Android app, using a Docker image to provide a consistent build environment. In theory, this allows us to have confidence that the publicly available source code posted to [github](https://github.com/WhisperSystems/Signal-Android) is, indeed, what is served out through the [Google Play Store](https://play.google.com/store/apps/details?id=org.thoughtcrime.securesms). Being security-minded (paranoid?), I thought I would verify this myself, but I encountered a few speed bumps along the way.

Right off the bat, things didn't go so smoothly. I wanted to build the Docker image myself, so I cloned the git repository and ran the docker build command. After a few minutes, and before the first command in the Dockerfile had completed, the following error message appeared:

```sh
E: Version '2.19-0ubuntu6.7' for 'libc6:i386' was not found
E: Version '4.8.4-2ubuntu1~14.04.1' for 'libstdc++6:i386' was not found
E: Version '8u72-b15-1~trusty1' for 'openjdk-8-jdk' was not found
The command '/bin/sh -c dpkg --add-architecture i386 &&     apt-get update -y &&     apt-get install -y software-properties-common &&     add-apt-repository -y ppa:openjdk-r/ppa &&     apt-get update -y &&     apt-get install -y libc6:i386=2.19-0ubuntu6.7 libncurses5:i386=5.9+20140118-1ubuntu1 libstdc++6:i386=4.8.4-2ubuntu1~14.04.1 lib32z1=1:1.2.8.dfsg-1ubuntu1 wget openjdk-8-jdk=8u72-b15-1~trusty1 git unzip &&     rm -rf /var/lib/apt/lists/* &&     apt-get autoremove -y &&     apt-get clean' returned a non-zero code: 100
```

This fails because it is requesting specific versions of these packages, which no longer exist in the repositories:

- libc6:i386=2.19-0ubuntu6.7
- libstdc++6:i386=4.8.4-2ubuntu1~14.04.1
- openjdk-8-jdk=8u72-b15-1~trusty1

I could just remove the pinned versions to get past this step, and install whatever version is there, but that would likely result in a different build output.

There is an open [pull request](https://github.com/WhisperSystems/Signal-Android/pull/5731/files) to update these packages to newer versions, although that version of the Dockerfile also failed to find the required versions of all the packages when I ran it. The Dockerfile referenced in that pull request is based on a Debian-based image, and it appears that Debian regularly prunes packages from it's repositories that have had security fixes published in later versions. An alternative would be to use the [snapshot archive](http://snapshot.debian.org/) to install specific versions of each package, although when I attempted that I ran in to dependency issues that would require other packages to be replaced with different versions. This would get me even further from the environment that was used to build the Play Store version, so at this point I abandoned the idea of building the Docker image myself.

The initial blog post by Open Whisper Systems recommends using the [pre-built image](https://hub.docker.com/r/whispersystems/signal-android/) available on Docker Hub. While we're not reproducing as much of the build process ourselves by using it, surely that would be a smoother process? One look at the scroll bar on this page might hint at the answer to that.

At the time of writing, the currently published version of Signal is 3.26.2, so I checked out the corresponding tag in my git working copy and ran `docker run --rm -v $(pwd):/project -w /project whispersystems/signal-android:0.2 ./gradlew clean assembleRelease`, which resulted in this error:

```bash
FAILURE: Build failed with an exception.

* What went wrong:
A problem occurred configuring root project 'project'.
> Failed to notify project evaluation listener.
   > You have not accepted the license agreements of the following SDK components:
     [Android SDK Build-Tools 23.0.3, Android SDK Platform 25].
     Before building your project, you need to accept the license agreements and complete the installation of the missing components using the Android Studio SDK Manager.
     Alternatively, to learn how to transfer the license agreements from one workstation to another, go to http://d.android.com/r/studio-ui/export-licenses.html
```

According to the announcement on the Open Whisper Systems blog, and the [Signal-Android wiki](https://github.com/WhisperSystems/Signal-Android/wiki/Reproducible-Builds), that command should be all that's required, but clearly this hasn't worked. Signal uses gradle to manage it's build process, and part of that process for a clean build includes downloading the Android SDK, among other things, which requires you to agree to their license terms.

Technically, all it requires is for the build process to see a file in a specific location, containing a specific hash, which matches up to what is generated by the Android SDK when you actually click the "I Agree" button. So, I could just put instructions here to create a file inside the container comprising a certain 40 character string, although that would almost certainly violate the license, and is likely why it is not included in the image distributed through Docker Hub. Why this step isn't mentioned anywhere, though, I can't say.

Anyway, following the instructions in `BUILDING.md`, I installed Android studio and the required Android SDK packages, which prompted me to accept the appropriate licenses. After clicking through the license, I had the magic string in the file `licenses/android-sdk-license` within the SDK location on my host machine, and now I just need to get the container to recognise it.

The container contains (ha!) the android SDK in the directory `/usr/local/android-sdk-linux`, and we can add another volume to the `docker run` command to use the license directory on the host machine. The command then takes this form:

```bash
docker run --rm -v $(pwd):/project -v $PATH_TO_HOST_SDK/licenses:/usr/local/android-sdk-linux/licenses -w /project whispersystems/signal-android:0.2 ./gradlew clean assembleRelease
```

where $PATH_TO_HOST_SDK should be substituted with the absolute location on the host of the Android SDK.

After running for a few minutes, I saw these license-related messages, indicating that the license file was picked up correctly by the build process:

```bash
Checking the license for package Android SDK Build-Tools 23.0.3 in /usr/local/android-sdk-linux/licenses
License for package Android SDK Build-Tools 23.0.3 accepted.
Preparing "Install Android SDK Build-Tools 23.0.3".
"Install Android SDK Build-Tools 23.0.3" ready.
Finishing "Install Android SDK Build-Tools 23.0.3"
Installing Android SDK Build-Tools 23.0.3 in /usr/local/android-sdk-linux/build-tools/23.0.3
"Install Android SDK Build-Tools 23.0.3" complete.
Checking the license for package Android SDK Platform 25 in /usr/local/android-sdk-linux/licenses
License for package Android SDK Platform 25 accepted.
Preparing "Install Android SDK Platform 25".
"Install Android SDK Platform 25" ready.
Finishing "Install Android SDK Platform 25"
Installing Android SDK Platform 25 in /usr/local/android-sdk-linux/platforms/android-25
"Install Android SDK Platform 25" complete.
```

And a while later, this message:

```bash
BUILD SUCCESSFUL

Total time: 20 mins 9.885 secs
```

Success! The resulting APK now existed at `./build/outputs/apk/project-release-unsigned.apk`. Now for the verification.

There are instructions for getting the APK off of your phone on the [wiki](https://github.com/WhisperSystems/Signal-Android/wiki/Reproducible-Builds), copied here for posterity:

- Enable USB debugging on your phone, connect it to your computer and accept the debugging prompt.
- Find where the APK is actually stored with: `adb shell pm path org.thoughtcrime.securesms`
- pull the APK to your computer's home directory with: `adb pull /data/app/org.thoughtcrime.securesms-1/base.apk ~/Signal-3.26.2-from-Google-Play.apk`, substituting the first argument to `adb pull` with the output of the `adb shell pm path` command, if required.

According to the wiki, we can verify that the APK's are equivalent by running the provided `apkdiff/apkdiff.py` script, passing it the location of our two APKs as arguments. Since I have python installed, I didn't bother trying to run this within the container, so I ran `apkdiff/apkdiff.py ~/Signal-3.26.2-from-Google-Play.apk build/outputs/apk/project-release-unsigned.apk` and saw this:

```bash
APKs match!
```

Looks good, but how do we know what it's done? Without looking at the script itself, it could be ignoring the arguments entirely and running no more than:

```python
print "APKs match!"
```

Of course, after reviewing `apkdiff.py`, that's not what it's doing. The script compares every file in each APK, but ignores these ones, located under `./META-INF`:

- CERT.RSA
- CERT.SF
- MANIFEST.MF

These files contain some metadata and digital signing information for the files within the APK. As we do not have the private key used by Open Whisper Systems (nor should we have it), the versions of these files that we produce will necessarily be different to the ones we get through Google Play. They don't contain any code, so it is not necessary to compare these files to prove that the source we have matches up to the distributed APK.

While `apkdiff.py` is nice, we needn't rely on it at all. Since .apk files are just .zip files with some conventions on naming and content, we can extract them and see exactly what the differences are.

Extracting both APK's to their own directories, and passing those directories to `diff -r`, confirms that the only differences are in those ignored `./META-INF` files. The `CERT.RSA` and `CERT.SF` files only exist in the Play Store version, not ours, while `MANIFEST.MF` exists in both, with quite a few differences. This output is excerpted below:

```diff
Only in Signal-3.26.2-from-Google-Play.apk_FILES/META-INF: CERT.RSA
Only in Signal-3.26.2-from-Google-Play.apk_FILES/META-INF: CERT.SF
diff -r project-release-unsigned.apk_FILES/META-INF/MANIFEST.MF Signal-3.26.2-from-Google-Play.apk_FILES/META-INF/MANIFEST.MF
4a5,9704
> Name: assets/stickers/weather/rain.png
> SHA1-Digest: gd+JIcO3HWQe29Zq+y4q4HKOiYc=
>
> Name: assets/stickers/food/tomato.png
> SHA1-Digest: gt7uBk6iNgpNB8kHZVlq6vfdWXc=
>
> Name: res/drawable/error_round.xml
> SHA1-Digest: /dc/CUQ2SFAXgoplWG74eEB36w0=
>
> Name: res/drawable-xhdpi-v4/ic_contact_picture_large.png
> SHA1-Digest: 3Z0C0DWzxp5pNxE+M3R0P0x2Fgg=
```

and on it goes for another ~9500 lines, all of which are no more than the `Name:` and `SHA1-Digest:` lines. Both versions of the .apk have the files themselves, but only the signed version contains references to them in the manifest.

So, as far as actual code goes, we have generated exactly the same thing as is distributed through Google Play on to your phone. While reproducible builds are important for a security conscious application, any part of the build process that relies on retrieving things from the internet is inherently brittle.

I'll probably build the Docker image myself once it is possible to do so again, but this process of building everything from source could go on forever. What about all the .jar files that are pulled down during the build? What about the build tools themselves? What about Docker and all the other software running on my host machine? Unless I manually compile every piece of code that touches my computer and phone, I can't say with 100% confidence that I know exactly what I have built during this excercise.

For my purposes, I'm happy enough to say that `APKs match!`.
