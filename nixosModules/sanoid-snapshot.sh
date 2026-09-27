# usage: sanoid-snapshot <dataset> <granularity>
#
# Takes a snapshot for <granularity>, plus one for every coarser type whose
# boundary falls now, named the way sanoid names its own so sanoid's autoprune
# counts and expires them as if it had taken them.
#
# For datasets that cannot use sanoid's own autosnap because something has to
# happen around the snapshot: a database dumped into the dataset so one
# snapshot holds both halves, a service stopped so nothing writes mid-dump.
# Sanoid takes snapshots on a timer with nothing in between, so those datasets
# need their own unit -- and then, historically, their own naming, which is
# where snapshots sanoid will not prune come from.
#
# Sanoid claims a snapshot as its own only if the name starts with "autosnap"
# (sanoid:914) and ends in a type it recognises, which it extracts with
# /.*_(\w*ly)/ (sanoid:913) -- every sanoid type ends in "ly", which is what
# that regex leans on. The timestamp between the two is decoration: pruning
# orders snapshots by the ZFS creation property, never by the name. It is
# still written in sanoid's own format and timezone so snapshots from both
# sources sort together in one zfs list -- and that timezone is UTC, even
# though sanoid's get_date calls localtime (sanoid:1153), because the NixOS
# sanoid module pins Environment=TZ=UTC on sanoid.service.
#
# The boundary checks below deliberately do not follow the name into UTC.
# They have to agree with when the caller's timer fires, which is in local
# time: a daily run at 00:00 in a UTC+7 zone is 17:00 UTC the day before, so
# a UTC weekday would call Monday's run Sunday and fire the monthly on the
# last day of the previous month.
#
# Assumes a caller that runs no more often than hourly, which is what lets
# due-ness be read straight off the clock with no record of the last run.
#
# Unlike sanoid's autosnap, which skips a type whose count is 0, this takes
# every type whose boundary falls now regardless of the dataset's config. A
# type left at sanoid's default of 0 -- weekly and yearly both are -- is
# pruned on sanoid's next run, so those snapshots are churn rather than a
# leak: set the counts you actually want on the dataset.

if [ "$#" -ne 2 ]; then
  echo "usage: sanoid-snapshot <dataset> <granularity>" >&2
  exit 1
fi

dataset="$1"
granularity="$2"

# Rejected rather than passed through. A type sanoid does not recognise is a
# snapshot it never prunes, which is the one mistake here that costs disk
# forever instead of failing loudly.
case "$granularity" in
hourly) rank=0 ;;
daily) rank=1 ;;
weekly) rank=2 ;;
monthly) rank=3 ;;
yearly) rank=4 ;;
*)
  echo "sanoid-snapshot: unknown granularity '$granularity'" >&2
  exit 1
  ;;
esac

# One reading of the clock, fixed as an epoch and then formatted several ways.
# Asking date afresh for each field lets a run that starts at 23:59:59 decide
# on one day and stamp the name with the next.
#
# The stamp is UTC to match sanoid; the four boundary fields are local. See
# the header for why the two deliberately disagree.
now=$(date +%s)
stamp=$(date -u -d "@$now" +"%Y-%m-%d_%H:%M:%S")
hour=$(date -d "@$now" +%H)
wday=$(date -d "@$now" +%u)
mday=$(date -d "@$now" +%-d)
mon=$(date -d "@$now" +%-m)

take() {
  zfs snapshot "$dataset@autosnap_${stamp}_$1"
}

# Ungated. The hour is whenever the timer happened to fire, so requiring a
# particular one would mean a run a few minutes late silently takes nothing.
take "$granularity"

# Only a caller running more often than daily has a meaningful hour to check.
if [ "$rank" -eq 0 ] && [ "$hour" != "00" ]; then
  exit 0
fi

if [ "$rank" -lt 1 ]; then take daily; fi
if [ "$rank" -lt 2 ] && [ "$wday" = "1" ]; then take weekly; fi

# An hourly or daily caller runs on the 1st, so for those the monthly boundary
# is simply the 1st.
if [ "$rank" -lt 2 ] && [ "$mday" -eq 1 ]; then take monthly; fi

# A boundary is the first run of the coarser period, not a fixed date: a
# weekly caller lands on the 1st only about one month in seven, so testing
# the 1st for it would leave most months with no monthly snapshot at all --
# and the monthly count could never fill, so it could never prune either. Its
# first run of the month is instead any run in the first seven days, which
# happens exactly once a month.
if [ "$rank" -eq 2 ] && [ "$mday" -le 7 ]; then take monthly; fi

# Same ladder one period up. Sanoid's types run out at yearly (sanoid:466), so
# leaving it out would leave any dataset configured with a non-zero yearly
# count with a bucket that never fills and therefore never prunes -- the exact
# failure this script exists to avoid. The first run of the year is January's
# first run of the month for the finer callers, and January itself for a
# monthly caller.
if [ "$rank" -lt 2 ] && [ "$mon" -eq 1 ] && [ "$mday" -eq 1 ]; then take yearly; fi
if [ "$rank" -eq 2 ] && [ "$mon" -eq 1 ] && [ "$mday" -le 7 ]; then take yearly; fi
if [ "$rank" -eq 3 ] && [ "$mon" -eq 1 ]; then take yearly; fi
