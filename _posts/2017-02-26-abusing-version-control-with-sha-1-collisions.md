---
layout: post
title:  "Abusing Version Control with SHA-1 Collisions"
date:   2017-02-26 19:22:20 +1000
tags: [shattered, sha1, hash, git, svn]
---

Now that there is a [public SHA-1 collision](http://shattered.io/), we can supposedly mess with both SVN and git repositories by adding these specially crafted pdf files. But what actually happens when these files are added to a repository that uses SHA-1 for deduplication? To find out, let's create git and SVN repositories, add these files to them, and see what happens.

To start off, I grabbed both of the PDF files provided at [http://shattered.io/](http://shattered.io/). These two files have different contents, but result in the same SHA-1 hash:

```bash
william@william-laptop ~/c/shattered> sha1sum *.pdf
38762cf7f55934b34d179ae6a4c80cadccbb7f0a  shattered-blue.pdf
38762cf7f55934b34d179ae6a4c80cadccbb7f0a  shattered-red.pdf
william@william-laptop ~/c/shattered> sha256sum *.pdf
2bb787a73e37352f92383abe7e2902936d1059ad9f1ba6daaa9c1e58ee6970d0  shattered-blue.pdf
d4488775d29bdef7993367d541064dbdda50d383f89f0aa13a6ff2e0894ba5ff  shattered-red.pdf
```

### SVN

Originally, [http://shattered.io/](http://shattered.io/) only mentioned SVN, later adding references to git, so let's start there. Since SVN is centralized, we first need to set up an SVN server. I used a [docker image](https://github.com/pikado/alpine-svn), of course.

After checking out the test repository, I first added and committed the blue PDF.

```
william@william-laptop ~/c/s/testrepo> cp ../shattered-blue.pdf .
william@william-laptop ~/c/s/testrepo> svn add shattered-blue.pdf
A  (bin)  shattered-blue.pdf
william@william-laptop ~/c/s/testrepo> svn commit -m "Added BLUE pdf"
Adding  (bin)  shattered-blue.pdf
Transmitting file data .done
Committing transaction...
Committed revision 1.
```

Now for the breakage: replacing the blue PDF with the red one, which SVN should assume is the same file, since it has the same SHA-1 hash.

```
william@william-laptop ~/c/s/testrepo> rm shattered-blue.pdf
william@william-laptop ~/c/s/testrepo> cp ../shattered-red.pdf shattered-blue.pdf
william@william-laptop ~/c/s/testrepo> svn status
M       shattered-blue.pdf
```

So far the SVN client is holding up better than I'd hoped, since it has detected that this file is, indeed, different. Now to commit this file:

```
william@william-laptop ~/c/s/testrepo> svn commit -m "Replaced with RED pdf"
Sending        shattered-blue.pdf
Transmitting file data .done
Committing transaction...
Committed revision 2.
william@william-laptop ~/c/s/testrepo> sha256sum *.pdf
d4488775d29bdef7993367d541064dbdda50d383f89f0aa13a6ff2e0894ba5ff  shattered-blue.pdf
```

All seems well, but there is a hidden issue here which we will soon see. Our local working copy thinks it is up-to-date with the server, but it does not actually contain the same data. If we pull down the file from the server again, we end up with a different version than the one we had before.

```
william@william-laptop ~/c/s/testrepo> svn status
william@william-laptop ~/c/s/testrepo> rm shattered-blue.pdf
william@william-laptop ~/c/s/testrepo> svn update
Updating '.':
Restored 'shattered-blue.pdf'
At revision 2.
william@william-laptop ~/c/s/testrepo> svn status
william@william-laptop ~/c/s/testrepo> sha256sum *.pdf
2bb787a73e37352f92383abe7e2902936d1059ad9f1ba6daaa9c1e58ee6970d0  shattered-blue.pdf
```

And just like that, our hash has changed. SVN believes that our working copy is in the same state as before, even though our file has changed from red to blue. It would appear that the version committed in revision 2 does not exist on the server. At least not in a way that is easily retrievable.

It's not until we interrogate the server some more that things start to break:

```
william@william-laptop ~/c/s/testrepo> svn diff -r 1:2
svn: E200014: Checksum mismatch for 'shattered-blue.pdf':
   expected:  5bd9d8cabc46041579a311230539b8d1
     actual:  ee4aa52b139d925f8d8884402b0a750c
```

```
william@william-laptop ~/c/s/testrepo> svn diff -r 0:1
Index: shattered-blue.pdf
===================================================================
Cannot display: file marked as a binary type.
svn:mime-type = application/pdf
Index: shattered-blue.pdf
===================================================================
--- shattered-blue.pdf  (nonexistent)
+++ shattered-blue.pdf  (revision 1)

Property changes on: shattered-blue.pdf
___________________________________________________________________
Added: svn:mime-type
## -0,0 +1 ##
+application/pdf
\ No newline at end of property
```

So, revision 2 has problems, but revisions before it seem unaffected.

What if we start from scratch and check-out a fresh working copy?

```
william@william-laptop ~/c/s/testrepo> cd ..
william@william-laptop ~/c/shattered> svn co --username davsvn --password davsvn http://0.0.0.0:32770/svn/testrepo testrepo-fresh
svn: E120106: ra_serf: The server sent a truncated HTTP response body.
```

Looks like we've killed it. We still have our working copy, though, so what happens if we try to add another revision?

```
william@william-laptop ~/c/s/testrepo> echo "non colliding file (i assume)" > foo
william@william-laptop ~/c/s/testrepo> svn add foo
A         foo
william@william-laptop ~/c/s/testrepo> svn commit -m "Fingers crossed!"
Adding         foo
Transmitting file data .done
Committing transaction...
Committed revision 3.
william@william-laptop ~/c/s/testrepo> svn diff -r 2:3
Index: foo
===================================================================
--- foo (nonexistent)
+++ foo (revision 3)
@@ -0,0 +1 @@
+non colliding file \(i assume\)
```

We can still see information about revisions before/after the collision, we just can't do anything that needs to deal with the offending revision 2, which includes doing a fresh check-out.

### Git

For a like-for-like comparison, let's try the same scenario with git. First, we'll trash the svn working copy, and set up the same commits.

```
william@william-laptop ~/c/s/testrepo> cd ..
william@william-laptop ~/c/shattered> rm -rf testrepo testrepo-fresh
william@william-laptop ~/c/shattered> git init
Initialized empty Git repository in /home/william/code/shattered/.git/
william@william-laptop ~/c/shattered> cp shattered-blue.pdf shattered.pdf
william@william-laptop ~/c/shattered> git add shattered.pdf
william@william-laptop ~/c/shattered> git commit -m "Added BLUE pdf"
[master (root-commit) 43cd22c] Added BLUE pdf
 1 file changed, 0 insertions(+), 0 deletions(-)
 create mode 100644 shattered.pdf
william@william-laptop ~/c/shattered> rm shattered.pdf
william@william-laptop ~/c/shattered> cp shattered-red.pdf shattered.pdf
william@william-laptop ~/c/shattered> git commit shattered.pdf -m "Replaced with RED pdf"
[master fcba92f] Replaced with RED pdf
 1 file changed, 0 insertions(+), 0 deletions(-)
william@william-laptop ~/c/shattered> rm shattered-blue.pdf shattered-red.pdf
william@william-laptop ~/c/shattered> git status
On branch master
nothing to commit, working tree clean
```

Now that we've got the two files in there, what does git think of them?

```
william@william-laptop ~/c/shattered> sha256sum *.pdf
d4488775d29bdef7993367d541064dbdda50d383f89f0aa13a6ff2e0894ba5ff  shattered.pdf
william@william-laptop ~/c/shattered> rm shattered.pdf
william@william-laptop ~/c/shattered> git checkout -- .
william@william-laptop ~/c/shattered> git status
On branch master
nothing to commit, working tree clean
william@william-laptop ~/c/shattered> sha256sum *.pdf
d4488775d29bdef7993367d541064dbdda50d383f89f0aa13a6ff2e0894ba5ff  shattered.pdf
```

Unlike SVN, git serves up the correct (red) version of the file when asked. Looking at the diffs between each of our revisions also works as it should:

```
william@william-laptop ~/c/shattered> git show
commit fcba92f74d633f93e11d5f91ff6305b288050161
Author: William Friesen <willi@mfriesen.com>
Date:   Sun Feb 26 18:34:22 2017 +1100

    Replaced with RED pdf

diff --git a/shattered.pdf b/shattered.pdf
index ba9aaa1..b621eec 100644
Binary files a/shattered.pdf and b/shattered.pdf differ
william@william-laptop ~/c/shattered> git show HEAD~1
commit 43cd22c0d285dde34dfef7e8e591f836320dda32
Author: William Friesen <willi@mfriesen.com>
Date:   Sun Feb 26 18:32:58 2017 +1100

    Added BLUE pdf

diff --git a/shattered.pdf b/shattered.pdf
new file mode 100644
index 0000000..ba9aaa1
Binary files /dev/null and b/shattered.pdf differ
```

Let's finish with inspecting both the SHA-1 and SHA-256 hashes of the files at each revision:

```
william@william-laptop ~/c/shattered> git show HEAD~1:shattered.pdf | sha1sum
38762cf7f55934b34d179ae6a4c80cadccbb7f0a  -
william@william-laptop ~/c/shattered> git show HEAD:shattered.pdf | sha1sum
38762cf7f55934b34d179ae6a4c80cadccbb7f0a  -
william@william-laptop ~/c/shattered> git show HEAD~1:shattered.pdf | sha256sum
2bb787a73e37352f92383abe7e2902936d1059ad9f1ba6daaa9c1e58ee6970d0  -
william@william-laptop ~/c/shattered> git show HEAD:shattered.pdf | sha256sum
d4488775d29bdef7993367d541064dbdda50d383f89f0aa13a6ff2e0894ba5ff  -
```

This matches up with the hashes generated at the top of this post, so while git supposedly uses SHA-1 for deduplication, it's also doing some extra magic that SVN isn't.

### Final Thoughts

While it appears that a hash collision is disastrous for SVN, git holds up surprisingly well. This adds another one to the list of cool things git does that I don't really understand. Although it may not apply to every use case, I'll end with this thought buried within the offending files:

```
william@william-laptop ~/c/shattered> strings shattered.pdf | grep SHA-1
$SHA-1 is dead!!!!!
```
