---
layout: post
title:  "The Politics of Age"
date:   2016-07-24 15:34:41 +1000
tags: [sql, politics, america, us politics]
---

This coming US election will prove historic for many reasons, not least of which being that whoever the next president is, they will be significantly older than Barack Obama. For me this has sprouted the idea that perhaps a correlation can be drawn between a president's political party and their age. Namely, when voters oust one party in favour of the other, is there a trend towards older Republicans/younger Democrats?

<!--more-->

This could be determined by a quick Googling, but since I primarily develop against an Oracle database in my day job, I see this nail as begging for the SQL hammer. Doing this in a full Oracle install is a bit of overkill, though, so I went with SQLite for this task. You can all play along at home in [SQL Fiddle](http://sqlfiddle.com), or you could just skip ahead to the [pretty pictures](#charts) at the end of this post.

So, let's start by creating a table to hold our data.

{% highlight sql %}
CREATE TABLE presage (
  op INTEGER PRIMARY KEY
, name VARCHAR2(100)
, inauguration INTEGER
, age_at_inauguration NUMBER(5, 3)
, party CHAR(1)
);
{% endhighlight %}
I fully admit that this entire exercise may just be a justification for making that "PresAge" pun in the table name.

We can obtain our data from the [List of Presidents of the United States by age](https://en.wikipedia.org/wiki/List_of_Presidents_of_the_United_States_by_age) on Wikipedia. I didn't include the full list, since president #13 belonged to a party (Whig) that doesn't exist anymore. This still leaves us with ~150 years of Republican/Democrat contests, more than enough to draw some facile conclusions from.

After copying that table into LibreOffice to filter out just the relevant columns, and some regex and multi-cursor business in Atom, we have our sample data. The only thing missing is party affiliation, which is simple enough to add manually.

{% highlight sql %}
INSERT INTO presage (
  op
, name
, inauguration
, age_at_inauguration
, party
)
VALUES
  (14, 'Franklin Pierce', 1853, 48.101, 'D')
, (15, 'James Buchanan', 1857, 65.315, 'D')
, (16, 'Abraham Lincoln', 1861, 52.20, 'R')
, (17, 'Andrew Johnson', 1865, 56.107, 'D')
, (18, 'Ulysses S. Grant', 1869, 46.311, 'R')
, (19, 'Rutherford B. Hayes', 1877, 54.151, 'R')
, (20, 'James A. Garfield', 1881, 49.105, 'R')
, (21, 'Chester A. Arthur', 1881, 51.349, 'R')
, (22, 'Grover Cleveland', 1885, 47.351, 'D')
, (24, 'Grover Cleveland', 1893, 55.351, 'D')
, (23, 'Benjamin Harrison', 1889, 55.196, 'R')
, (25, 'William McKinley', 1897, 54.34, 'R')
, (26, 'Theodore Roosevelt', 1901, 42.322, 'R')
, (27, 'William Howard Taft', 1909, 51.170, 'R')
, (28, 'Woodrow Wilson', 1913, 56.66, 'D')
, (29, 'Warren G. Harding', 1921, 55.122, 'R')
, (30, 'Calvin Coolidge', 1923, 51.29, 'R')
, (31, 'Herbert Hoover', 1929, 54.206, 'R')
, (32, 'Franklin D. Roosevelt', 1933, 51.33, 'D')
, (33, 'Harry S. Truman', 1945, 60.339, 'D')
, (34, 'Dwight D. Eisenhower', 1953, 62.98, 'R')
, (35, 'John F. Kennedy', 1961, 43.236, 'D')
, (36, 'Lyndon B. Johnson', 1963, 55.87, 'D')
, (37, 'Richard Nixon', 1969, 56.11, 'R')
, (38, 'Gerald Ford', 1974, 61.26, 'R')
, (39, 'Jimmy Carter', 1977, 52.111, 'D')
, (40, 'Ronald Reagan', 1981, 69.349, 'R')
, (41, 'George H. W. Bush', 1989, 64.222, 'R')
, (42, 'Bill Clinton', 1993, 46.154, 'D')
, (43, 'George W. Bush', 2001, 54.198, 'R')
, (44, 'Barack Obama', 2009, 47.169, 'D');
{% endhighlight %}

Note that I left the ages in an essentially base-365 representation. Since all we're doing with these numbers is comparing them against each other, this will work just fine.

Since we'll be querying twice (once for Democrats succeeding Republicans, and once for Republicans succeeding Democrats), let's create a view that does most of the work.

{% highlight sql %}
CREATE VIEW age_differences AS
  WITH once_and_future_leaders AS (
    SELECT
      p.op
    , MIN(p2.op) succeeded_by
    FROM presage p
    JOIN presage p2
      ON p2.op > p.op
      AND p2.party != p.party
    GROUP BY
      p.op
  )
  , party_changes AS (
    SELECT
      MAX(op) op
    , succeeded_by
    FROM once_and_future_leaders
    GROUP BY
      succeeded_by
  )
  SELECT
    p2.inauguration
  , p2.name new_president
  , ROUND(p2.age_at_inauguration - p.age_at_inauguration, 2) age_difference
  , p2.op
  , p.party
  , p2.party new_party
  FROM party_changes pc
  JOIN presage p
    ON p.op = pc.op
  JOIN presage p2
    ON p2.op = pc.succeeded_by
{% endhighlight %}

At this point I actually missed Oracle. With no support for analytic functions in SQLite, this query required some convoluted joins and grouping in the `once_and_future_leaders` and `successions` views. Using Oracle's `LAG` or `LEAD` functions would have let us write a much simpler query:

{% highlight sql %}
WITH once_and_future_leaders AS (
  SELECT
    p.op
  , LEAD(p.op, 1, NULL) OVER (ORDER BY p.op) next_op
  FROM presage p
)
, successions AS (
  SELECT
    p.op
  , p2.op succeeded_by
  FROM once_and_future_leaders oafl
  JOIN presage p
    ON p.op = oafl.op
  JOIN presage p2
    ON p2.op = oafl.next_op
  WHERE p.party != p2.party
)
...
{% endhighlight %}

Anyway, enough jibber jabber, let's run some queries and see what we can see.

{% highlight sql %}
SELECT
  inauguration
, new_president
, age_difference
FROM age_differences
WHERE party = 'D'
AND new_party = 'R'
ORDER BY
  op;

SELECT
  inauguration
, new_president
, age_difference
FROM age_differences
WHERE party = 'R'
AND new_party = 'D'
ORDER BY
  op;
{% endhighlight %}

This gives us the following results for newly elected Republicans.

| inauguration |        new_president | age_difference |
|--------------|----------------------|----------------|
|         1861 |      Abraham Lincoln |         -13.11 |
|         1869 |     Ulysses S. Grant |           -9.8 |
|         1889 |    Benjamin Harrison |           7.84 |
|         1897 |     William McKinley |          -1.01 |
|         1921 |    Warren G. Harding |          -1.54 |
|         1953 | Dwight D. Eisenhower |           2.64 |
|         1969 |        Richard Nixon |           0.24 |
|         1981 |        Ronald Reagan |          17.24 |
|         2001 |       George W. Bush |           8.04 |

<br/>
And this for incoming Democrats.

| inauguration |         new_president | age_difference |
|--------------|-----------------------|----------------|
|         1865 |        Andrew Johnson |           3.91 |
|         1885 |      Grover Cleveland |             -4 |
|         1893 |      Grover Cleveland |           0.16 |
|         1913 |        Woodrow Wilson |           5.49 |
|         1933 | Franklin D. Roosevelt |          -2.88 |
|         1961 |       John F. Kennedy |         -19.74 |
|         1977 |          Jimmy Carter |          -9.15 |
|         1993 |          Bill Clinton |         -18.07 |
|         2009 |          Barack Obama |          -7.03 |

<br/>
This does seem to indicate a trend towards older-Republicans/younger-Democrats, particularly in more recent times.

<a name="charts"/>
![Republicans Succeeding Democrats]({{ site.url }}/assets/politics-of-age/r_after_d.svg)
![Democrats Succeeding Republicans]({{ site.url }}/assets/politics-of-age/d_after_r.svg)

But what about this coming election? Since I'm only looking at party switches, the Democratic chart will remain the same no matter what the outcome. So let's look at the effect a potential Trump presidency would have.

{% highlight sql %}
INSERT INTO presage (
  op
, name
, inauguration
, age_at_inauguration
, party
)
VALUES
  (45, 'Donald Trump', 2017, 70.220, 'R')
{% endhighlight %}

![Republicans (and Trump) Succeeding Democrats]({{ site.url }}/assets/politics-of-age/r_after_d_trump.svg)

At 70 years, 220 days old, Donald Trump would not only be the oldest incoming US president (besting Reagan by over 6 months), he would also provide us with the largest party-switch age differential at 23.05.
