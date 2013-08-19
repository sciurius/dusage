#!/usr/bin/perl -w

# dusage.pl -- gather disk usage statistics
# Author          : Johan Vromans
# Created On      : Sun Jul  1 21:49:37 1990
# Last Modified By: Johan Vromans
# Last Modified On: Mon Aug 19 11:57:56 2013
# Update Count    : 165
# Status          : OK
#
# This program requires Perl version 5.0, or higher.

################ Common stuff ################

use strict;

my ($my_name, $my_version) = qw( dusage 1.12 );

################ Command line parameters ################

use Getopt::Long 2.13;

my $verbose = 0;                # verbose processing
my $noupdate = 1;		# do not update the control file
my $retain = 0;			# retain emtpy entries
my $gather = 0;			# gather new data
my $follow = 0;			# follow symlinks
my $allfiles = 0;		# also report file stats
my $allstats = 0;		# provide all stats

my $root;			# root of all eveil
my $prefix;			# root prefix for reporting
my $data;			# the data, or how to get it
my $table;

my $runtype;			# file or directory

# Development options (not shown with -help).
my $debug = 0;                  # debugging
my $trace = 0;                  # trace (show process)
my $test = 0;                   # test (no actual processing)

app_options();

# Options post-processing.
$trace |= ($debug || $test);

################ Presets ################

my $TMPDIR = $ENV{TMPDIR} || '/usr/tmp';

################ The Process ################

my @targets = ();		# directories to process, and more
my %newblocks = ();		# du values
my %oldblocks = ();		# previous values
my @excludes = ();		# excluded entries

parse_ctl ();			# read the control file
gather () if $gather;		# gather new info
report_and_update ();		# wrrite report and update control file

################ Subroutines ################

sub parse_ctl {

    # Parsing the control file.
    #
    # This file contains the names of the (sub)directories to tally,
    # and the values dereived from previous runs.
    # The names of the directories are relative to the $root.
    # The name may contain '*' or '?' characters, and will be globbed if so.
    # An entry starting with ! is excluded.
    #
    # To add a new dir, just add the name. The special name '.' may 
    # be used to denote the $root directory. If used, '-p' must be
    # specified.
    #
    # Upon completion:
    #  - %oldblocks is filled with the previous values,
    #    colon separated, for each directory.
    #  - @targets contains a list of names to be looked for. These include
    #    break indications and globs info, which will be stripped from
    #    the actual search list.

    my $ctl = do { local(*FH); *FH };
    my $tb;			# ctl file entry

    open ($ctl, "<$table") or die ("Cannot open control file $table: $!\n");

    while ( $tb = <$ctl> ) {

	# syntax:    <dir><TAB><size>:<size>:....
	# possible   <dir>

	if ( $tb =~ /^-(?!\t)(.*)/ ) { # break
	    push (@targets, "-$1");
	    print STDERR ("tb: *break* $1\n") if $debug;
	    next;
	}

	if ( $tb =~ /^!(.*)/ ) { # exclude
	    push (@excludes, $1);
	    push (@targets, "!".$1);
	    print STDERR ("tb: *excl* $1\n") if $debug;
	    next;
	}

	my @blocks;
	my $name;
	if ( $tb =~ /^(.+)\t([\d:]+)/ ) {
	    $name = $1;
	    @blocks = split (/:/, $2 . "::::::::", -1);
	    $#blocks = 7;
	}
	else {
	    chomp ($name = $tb);
	    @blocks = ("") x 8;
	}

	if ( $name eq "." ) {
	    if ( $root eq "" ) {
		warn ("Warning: \".\" in control file w/o \"-p path\" - ignored\n");
		next;
	    }
	    $name = $root;
	}
	else {
	    $name = $prefix . $name unless ord($name) == ord ("/");
	}

	# Check for globs ...
	if ( ($gather|$debug) && $name =~ /\*|\?/ ) {
	    print STDERR ("glob: $name\n") if $debug;
	    foreach my $n ( glob($name) ) {
		next unless $allfiles || -d $n;
		# Globs never overwrite existing entries
		unless ( defined $oldblocks{$n} ) {
		    $oldblocks{$n} = ":::::::";
		    push (@targets, " $n");
		}
		print STDERR ("glob: -> $n\n") if $debug;
	    }
	    # Put on the globs list, and terminate this entry
	    push (@targets, "*$name");
	    next;
	}

	push (@targets, " $name");

	# Entry may be rewritten (in case of globs)
	$oldblocks{$name} = join (":", @blocks[0..7]);

	print STDERR ("tb: $name\t$oldblocks{$name}\n") if $debug;
    }

    if ( @excludes ) {
	foreach my $excl ( @excludes ) {
	    my $try = ord($excl) == ord("/") ? " $excl" : " $prefix$excl";
	    @targets = grep ($_ ne $try, @targets);
	}
	print STDERR ("targets after exclusion: @targets\n") if $debug;
    }

    close ($ctl);
}

sub gather {

    # Build a targets match string, and an optimized list of
    # directories to search. For example, if /foo and /foo/bar are
    # both in the list, only /foo is used since du will produce the
    # statistics for /foo/bar as well.

    my %targets = ();
    my @list = ();
    # Get all entries, and change the / to nul chars.
    my @a = map { s;/;\0;g ? ($_) : ($_) }
      # Only dirs unless $allfiles
      grep { $allfiles || -d }
	# And only the file/dir info entries
	map { /^ (.*)/ ? $1 : () } @targets;

    my $prev = "\0\0\0";
    foreach my $name ( sort (@a) ) {
	# If $prev is a complete prefix of $name, we've already got a
	# better one in the tables.
	unless ( index ($name, $prev) == 0 ) {
	    # New test arg -- including the trailing nul.
	    $prev = $name . "\0";
	    # Back to normal.
	    $name =~ s;\0;/;g;
	    # Register.
	    push (@list, $name);
	    $targets{$name}++;
	}

    }

    if ( $debug ) {
	print STDERR ("dirs: ", join(" ",sort(keys(%targets))),"\n",
		      "list: @list\n");
    }

    my $fh = do { local(*FH); *FH };
    my $out = do { local(*FH); *FH };
    if ( !$gather && defined $data ) {		# we have a data file
	open ($fh, "<$data")
	  or die ("Cannot get data from $data: $!\n");
	undef $data;
    }
    else {
	my @du = ("du");
	push (@du, "-a") if $allfiles;
	push( @du, "-L" ) if $follow;
	push (@du, @list);
	my $ret = open ($fh, "-|") || exec @du;
	die ("Cannot get input from -| @du\n") unless $ret;
	if ( defined $data ) {
	    open ($out, ">$data") or die ("Cannot create $data: $!\n");
	}
    }

    # Process the data. If a name is found in the target list,
    # %newblocks will be set to the new blocks value.
    %targets = map { $_ => 1 } @targets;
    my %excludes = map { $prefix.$_ => 1 } @excludes;
    my $du;
    while ( defined ($du = <$fh>) ) {
	print $out $du if defined $data;
	chomp ($du);
	my ($blocks, $name) = split (/\t/, $du);
	if ( exists ($targets{" ".$name}) && !exists ($excludes{$name}) ) {
	    # Tally and remove entry from search list.
	    $newblocks{$name} = $blocks;
	    print STDERR ("du: $name $blocks\n") if $debug;
	    delete ($targets{" ".$name});
	}
    }
    close ($fh);
    close ($out) if defined $data;
}

# Variables used in the formats.
my $date;			# date
my $name;			# name
my $subtitle;			# subtitle
my @a;
my $d_day;			# day delta
my $d_week;			# week delta
my $blocks;

sub report_and_update {

    my $ctl = do { local(*FH); *FH };

    # Prepare update of the control file
    if ( !$noupdate ) {
	if ( !open ($ctl, ">$table") ) {
	    warn ("Warning: cannot update control file $table [$!] - continuing\n");
	    $noupdate = 1;
	}
    }

    if ( $allstats ) {
	$^ = "all_hdr";
	$~ = "all_out";
    }
    else {
	$^ = "std_hdr";
	$~ = "std_out";
    }

    $date = localtime;
    $subtitle = "";

    # In one pass the report is generated, and the control file rewritten.

    foreach my $nam ( @targets ) {

	if ( $nam =~ /^-(.*)/ ) {
	    $subtitle = $1;
	    print $ctl ($nam, "\n") unless $noupdate;
	    print STDERR ("tb: $nam\n") if $debug;
	    $- = 0;		# force page feed
	    next;
	}

	if ($nam  =~ /^\*\Q$prefix\E(.*)/o ) {
	    print $ctl ("$1\n") unless $noupdate;
	    print STDERR ("tb: $1\n") if $debug;
	    next;
	}

	if ( $nam =~ /^ (.*)/ ) {
	    $nam = $1
	}
	else {
	    print $ctl $nam, "\n";
	    print STDERR ("tb: $nam\n") if $debug;
	    next;
	}

	print STDERR ("Oops1 $nam\n") unless defined $oldblocks{$nam};
	print STDERR ("Oops2 $nam\n") unless defined $newblocks{$nam};
	@a = split (/:/, $oldblocks{$nam} . ":::::::", -1);
	$#a = 7;
	unshift (@a, $newblocks{$nam}) if $gather;
	$nam = "." if $nam eq $root;
	$nam = $1 if $nam =~ /^\Q$prefix\E(.*)/o;
	warn ("Warning: ", scalar(@a), " entries for $nam\n")
	  if $debug && @a != 9;

	# check for valid data
	my $try = join (":", @a[0..7]);
	if ( $try eq ":::::::" ) {
	    if ($retain) {
		@a = ("") x 8;
	    }
	    else {
		# Discard.
		print STDERR ("--: $nam\n") if $debug;
		next;
	    }
	}

	my $line = "$nam\t$try\n";
	print $ctl ($line) unless $noupdate;
	print STDERR ("tb: $line") if $debug;

	$blocks = $a[0];
	unless ( $allstats ) {
	    $d_day = $d_week = "";
	    if ( $blocks ne "" ) {
		if ( $a[1] ne "" ) { # daily delta
		    $d_day = $blocks - $a[1];
		    $d_day = "+" . $d_day if $d_day > 0;
		}
		if ( $a[7] ne "" ) { # weekly delta
		    $d_week = $blocks - $a[7];
		    $d_week = "+" . $d_week if $d_week > 0;
		}
	    }
	}

 	# Using a outer my variable that is aliased in a loop within a
 	# subroutine still doesn't work...
	$name = $nam;
	write;
    }

    # Close control file, if opened
    close ($ctl) unless $noupdate;
}

################ Option Processing ################

sub app_options {
    my $help = 0;               # handled locally
    my $ident = 0;              # handled locally
    my $man = 0;		# handled locally

    my $pod2usage = sub {
        # Load Pod::Usage only if needed.
        require Pod::Usage;
        Pod::Usage->import;
        &pod2usage;
    };

    Getopt::Long::Configure qw(bundling);
    GetOptions(
	       'allstats|a'	=> \$allstats,
	       'allfiles|f'	=> \$allfiles,
	       'gather|g'	=> \$gather,
	       'follow|L'	=> \$follow,
	       'retain|r'	=> \$retain,
	       'update!'	=> sub { $noupdate = !$_[1] },
	       'u'		=> sub { $noupdate = !$_[1] },
	       'data|i=s'	=> \$data,
	       'dir|p=s'	=> \$root,
	       'verbose|v'	=> \$verbose,
	       'trace'		=> \$trace,
	       'help|?'		=> \$help,
	       'man'		=> \$man,
	       'debug'		=> \$debug,
	      ) or $pod2usage->(2);

    if ( $ident or $help or $man ) {
	print STDERR ("This is $my_name $my_version\n");
    }
    if ( $man or $help ) {
	$pod2usage->(1) if $help;
	$pod2usage->(VERBOSE => 2) if $man;
    }
    if ( @ARGV > 1 ) {
	$pod2usage->(2);
    }

    if ( defined $root ) {
	$root =~ s;/+$;;;
	$prefix = $root . "/";
	$root = "/" if $root eq "";
    }
    else {
	$prefix = $root = "";
    }

    $table = @ARGV ? shift(@ARGV) : $prefix . ".du.ctl";
    $runtype = $allfiles ? "file" : "directory";
    $noupdate |= !$gather;

    if ( $debug ) {
	print STDERR
	  ("$my_name $my_version\n",
	   "Options:",
	   $debug     ? " debug"  : ""	 , # silly, isn't it...
	   $noupdate  ? " no"	  : " "	 , "update",
	   $retain    ? " "	  : " no", "retain",
	   $gather    ? " "	  : " no", "gather",
	   $allstats  ? " "	  : " no", "allstats",
	   "\n",
	   "Root = \"$root\", prefix = \"$prefix\"\n",
	   "Control file = \"$table\"\n",
	   $data ? (($gather ? "Output" : "Input") ." data = \"$data\"\n") : "",
	   "Run type = \"$runtype\"\n",
	   "\n");
    }
}

# Formats.

format std_hdr =
Disk usage statistics@<<<<<<<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<
$subtitle, $date

  blocks    +day     +week  @<<<<<<<<<<<<<<<
$runtype
--------  -------  -------  --------------------------------
.

format std_out =
@>>>>>>> @>>>>>>> @>>>>>>>  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$blocks, $d_day, $d_week, $name
.

format all_hdr =
Disk usage statistics@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<           @<<<<<<<<<<<<<<<
$subtitle, $date

 --0--    --1--    --2--    --3--    --4--    --5--    --6--    --7--   @<<<<<<<<<<<<<<<
$runtype
-------  -------  -------  -------  -------  -------  -------  -------  --------------------------------
.
format all_out =
@>>>>>> @>>>>>>> @>>>>>>> @>>>>>>> @>>>>>>> @>>>>>>> @>>>>>>> @>>>>>>>  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<..
@a, $name
.

__END__

=pod

=head1 NAME

dusage - provide disk usage statistics

=head1 SYNOPSIS

    dusage [options] ctlfile

      -a  --allstats          provide all statis
      -f  --allfiles          also report file statistics
      -g  --gather            gather new data
      -i input  --data=input  input data as obtained by 'du dir'
			      or output with -g
      -p dir  --dir=dir       path to which files in the ctlfile are relative
      -r  --retain            do not discard entries which do not have data
      -u  --update            update the control file with new values
      -L                      resolve symlinks
      -h  --help              this help message
      --man		      show complete documentation
      --debug                 provide debugging info

      ctlfile                 file which controls which dirs to report
			      default is dir/.du.ctl

=head1 DESCRIPTION

Ever wondered why your free disk space gradually decreases? This
program may provide you with some useful clues.

B<dusage> is a Perl program which produces disk usage statistics.
These statistics include the number of blocks that files or
directories occupy, the increment since the previous run (which is
assumed to be the day before if run daily), and the increment since 7
runs ago (which could be interpreted as a week, if run daily).

B<dusage> is driven by a control file that describes the names of the
files (directories) to be reported. It also contains the results of
previous runs.

When B<dusage> is run, it reads the control file, optionally gathers
new disk usage values by calling the B<du> program, prints the report,
and optionally updates the control file with the new information.

Filenames in the control file may have wildcards. In this case, the
wildcards are expanded, and all entries reported. Both the expanded
names as the wildcard info are maintained in the control file. New
files in these directories will automatically show up, deleted files
will disappear when they have run out of data in the control file (but
see the B<-r> option).

Wildcard expansion only adds filenames that are not already on the list.

The control file may also contain filenames preceded with an
exclamation mark C<!>; these entries are skipped. This is meaningful
in conjunction with wildcards, to exclude entries which result from a
wildcard expansion.

The control file may have lines starting with a dash C<-> that is
I<not> followed by a C<Tab>, which will cause the report to start a
new page here. Any text following the dash is placed in the page
header, immediately following the text ``Disk usage statistics''.

The available command line options are:

=over 4

=item B<-a> B<--allstats>

Reports the statistics for this and all previous runs, as opposed to
the normal case, which is to generate the statistics for this run, and
the differences between the previous and 7th previous run.

=item B<-f> B<--allfiles>

Reports file statistics also. Default is to only report directories.

=item B<-g> B<--gather>

Gathers new data by calling the B<du> program. See also the C<-i>
(B<--data>) option below.

=item B<-i> I<file> or <--data> I<file>

With B<-g> (B<--gather>), write the obtained raw info (the output of the B<du> program) to this file for subsequent use.

Without B<-g> (B<--gather>), a data file written in a previous run is reused.

=item B<-p> I<dir> or B<--dir> I<dir>

All filenames in the control file are interpreted relative to this
directory.

=item B<-L> B<--follow>

Follow symbolic links.

=item B<-r> B<--retain>

Normally, entries that do not have any data anymore are discarded.
If this option is used, these entries will be retained in the control file.

=item B<-u> B<--update>

Update the control file with new values. Only effective if B<-g>
(B<--gather>) is also supplied.

=item B<-h> B<--help> B<-?>

Provides a help message. No work is done.

=item B<--man>

Provides the complete documentation. No work is done.

=item B<--debug>

Turns on debugging, which yields lots of trace information.

=back

The default name for the control file is
I<.du.ctl>, optionally preceded by the name supplied with the
B<-p> (B<--dir>) option.

=head1 EXAMPLES

Given the following control file:

    - for manual pages
    maildir
    maildir/*
    !maildir/unimportant
    src

This will generate the following (example) report when running the
command ``dusage -gu controlfile'':

    Disk usage statistics for manual pages     Wed Nov 23 22:15:14 2000

     blocks    +day     +week  directory
    -------  -------  -------  --------------------------------
       6518                    maildir
	  2                    maildir/dirent
	498                    src

After updating the control file, it will contain:

    - for manual pages
    maildir 6518::::::
    maildir/dirent  2::::::
    maildir/*
    !maildir/unimportant
    src     498::::::

The names in the control file are separated by the values with a C<Tab>;
the values are separated by colons. Also, the entries found by
expanding the wildcard are added. If the wildcard expansion had
generated a name ``maildir/unimportant'' it would have been skipped.

When the program is rerun after one day, it could print the following
report:

    Disk usage statistics for manual pages      Thu Nov 23 17:25:44 2000

     blocks    +day     +week  directory
    -------  -------  -------  --------------------------------
       6524       +6           maildir
	  2        0           maildir/dirent
	486      -12           src

The control file will contain:

    - for manual pages
    maildir 6524:6518:::::
    maildir/dirent  2:2:::::
    maildir/*
    !maildir/unimportant
    src     486:498:::::

It takes very little fantasy to imagine what will happen on subsequent
runs...

When the contents of the control file are to be changed, e.g. to add
new filenames, a normal text editor can be used. Just add or remove
lines, and they will be taken into account automatically.

When run without B<-g> (B<--gather>) option, it reproduces the report
from the previous run.

When multiple runs are required, save the output of the B<du> program 
in a file, and pass this file to B<dusage> using the B<-i> (B<--data>)
option.

Running the same control file with differing values of the B<-f>
(B<--allfiles>) or B<-r> (B<--retain>) options may cause strange
results.

=head1 COMPATIBILITY NOTICE

This program is rewritten for Perl 5.005 and later. However, it is
still fully backward compatible with its 1990 predecessor.

=head1 AUTHOR

Johan Vromans, Squirrel Consultancy, Haarlem, The Netherlands.

Send bugs and remarks to <jvromans@squirrel.nl>.

=head1 COPYRIGHT

Copyright 1990,1991,2000 Johan Vromans, all rights reserved.

This program may be used, modified and distributed as long as this
copyright notice remains part of the source. It may not be sold, or
be used to harm any living creature including the world and the
universe.

=cut

# Emacs support
# Local Variables:
# eval:(headers)
# End:
