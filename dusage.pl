#!/usr/bin/perl
#
#	@(#)dusage	1.8
#
# This program requires perl version 3.0, patchlevel 12 or higher.
#
# Copyright 1990 Johan Vromans, all rights reserved.
# This program may be used, modified and distributed as long as
# this copyright notice remains part of the source. It may not be sold, or 
# be used to harm any living creature including the world and the universe.

$my_name = $0;

################ usage ################

sub usage {
  local ($help) = shift (@_);
  local ($usg) = "usage: $my_name [-afghruD][-i input][-p dir] ctlfile";
  die "$usg\nstopped" unless $help;
  print STDERR "$usg\n";
  print STDERR <<EndOfHelp

    -D          - provide debugging info
    -a          - provide all statis
    -f          - also report file statistics
    -g          - gather new data
    -h          - this help message
    -i input    - input data as obtained by 'du dir' [def = 'du dir']
    -p dir      - path to which files in the control file are relative
    -r          - do not discard entries which don't have data
    -u          - update the control file with new values
    ctlfile     - file which controls which dirs to report [def = dir/.du.ctl]
EndOfHelp
  ;
  exit 1;
}

################ main stream ################

&do_get_options;		# process options
&do_parse_ctl;			# read the control file
&do_gather if $gather;		# gather new info
&do_report_and_update;		# report and update

################ end of main stream ################

################ other subroutines ################

sub do_get_options {

  # Default values for options

  $debug = 0;
  $noupdate = 1;
  $retain = 0;
  $gather = 0;
  $allfiles = 0;
  $allstats = 0;

  # Command line options. We use a modified version of getopts.pl.

  do "getopts.pl" || die "Cannot load getopts.pl, stopped";
  die $@ if $@;

  &usage (0) if !&Getopts ("Dafghi:p:ru");
  &usage (1) if $opt_h;
  &usage (0) if $#ARGV > 0;

  $debug    |= $opt_D if defined $opt_D;	# -D -> debug
  $allstats |= $opt_a if defined $opt_a;	# -a -> all stats
  $allfiles |= $opt_f if defined $opt_f;	# -f -> report all files
  $gather   |= $opt_g if defined $opt_g;	# -g -> gather new data
  $retain   |= $opt_r if defined $opt_r;	# -r -> retain old entries
  $noupdate = !$opt_u if defined $opt_u;	# -u -> update the control file
  $du        = $opt_i if defined $opt_i;	# -i input file
  if ( defined $opt_p ) {			# -p path
    $root = $opt_p;
    $root = $` while ($root =~ m|/$|);
    $prefix = "$root/";
    $root = "/" if $root eq "";
  }
  else {
    $prefix = $root = "";
  }
  $table    = ($#ARGV == 0) ? shift (@ARGV) : "$prefix.du.ctl";
  $runtype = $allfiles ? "file" : "directory";
  if ($debug) {
    print STDERR "@(#)@ dusage	1.8 - dusage.pl\n";
    print STDERR "Options:";
    print STDERR " debug" if $debug;	# silly, isn't it...
    print STDERR $noupdate ? " no" : " ", "update";
    print STDERR $retain ? " " : " no", "retain";
    print STDERR $gather ? " " : " no", "gather";
    print STDERR $allstats ? " " : " no", "allstats";
    print STDERR "\n";
    print STDERR "Root = $root [prefix = $prefix]\n";
    print STDERR "Control file = $table\n";
    print STDERR "Input data = $du\n" if defined $du;
    print STDERR "Run type = $runtype\n";
    print STDERR "\n";
  }
}

sub do_parse_ctl {

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

  open (tb, "<$table") || die "Cannot open control file $table, stopped";
  @targets = ();
  %oldblocks = ();
  %newblocks = ();

  while ($tb = <tb>) {
    chop ($tb);

    # preferred syntax: <dir><TAB><size>:<size>:....
    # allowable	      <dir><TAB><size> <size> ...
    # possible	      <dir>

    if ( $tb =~ /^-/ ) {	# break
      push (@targets, "$tb");
      printf STDERR "tb: *break* $tb\n" if $debug;
      next;
    }

    if ( $tb =~ /^!/ ) {	# exclude
      $excl = $';		#';
      @a = grep ($_ ne $excl, @targets);
      @targets = @a;
      push (@targets, "*$tb");
      printf STDERR "tb: *excl* $tb\n" if $debug;
      next;
    }

    if ($tb =~ /^(.+)\t([\d: ]+)/) {
      $name = $1;
      @blocks = split (/[ :]/, $2);
    }
    else {
      $name = $tb;
      @blocks = ("","","","","","","","");
    }

    if ($name eq ".") {
      if ( $root eq "" ) {
	printf STDERR "Warning: \".\" in control file w/o \"-p path\" - ignored\n";
	next;
      }
      $name = $root;
    } else {
      $name = $prefix . $name unless ord($name) == ord ("/");
    }

    # Check for globs ...
    if ( $gather && $name =~ /\*|\?/ ) {
      print STDERR "glob: $name\n" if $debug;
      foreach $n ( <${name}> ) {
	next unless $allfiles || -d $n;
	# Globs never overwrite existing entries
	if ( !defined $oldblocks{$n} ) {
	  $oldblocks{$n} = ":::::::";
	  push (@targets, $n);
	}
	printf STDERR "glob: -> $n\n" if $debug;
      }
      # Put on the globs list, and terminate this entry
      push (@targets, "*$name");
      next;
    }

    push (@targets, "$name");
    # Entry may be rewritten (in case of globs)
    $oldblocks{$name} = join (":", @blocks[0..7]);

    print STDERR "tb: $name\t$oldblocks{$name}\n" if $debug;
  }
  close (tb);
}

sub do_gather {

  # Build a targets match string, and an optimized list of directories to
  # search.
  $targets = "//";
  @list = ();
  $last = "///";
  foreach $name (sort (@targets)) {
    next if $name =~ /^[-*]/;
    next unless $allfiles || -d $name;
    $targets .= "$name//"; 
    next if ($name =~ m|^$last/|);
    push (@list, $name);
    $last = $name;
  }

  print STDERR "targets: $targets\n" if $debug;
  print STDERR "list: @list\n" if $debug;
  print STDERR "reports: @targets\n" if $debug;

  $du = "du " . ($allfiles ? "-a" : "") . " @list|"
    unless defined $du; # in which case we have a data file

  # Process the data. If a name is found in the target list, 
  # %newblocks will be set to the new blocks value.

  open (du, "$du") || die "Cannot get data from $du, stopped";
  while ($du = <du>) {
    chop ($du);
    ($blocks,$name) = split (/\t/, $du);
    if (($i = index ($targets, "//$name//")) >= 0) {
      # tally and remove entry from search list
      $newblocks{$name} = $blocks;
      print STDERR "du: $name $blocks\n" if $debug;
      substr ($targets, $i, length($name) + 2) = "";
    }
  }
  close (du);
}


# Report generation

format std_hdr =
Disk usage statistics@<<<<<<<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<
$subtitle, $date

 blocks    +day     +week  @<<<<<<<<<<<<<<<
$runtype
-------  -------  -------  --------------------------------
.
format std_out =
@>>>>>> @>>>>>>> @>>>>>>>  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<..
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
$a[0],  $a[1],   $a[2],   $a[3],   $a[4],   $a[5],   $a[6],   $a[7],    $name
.

sub do_report_and_update {

  # Prepare update of the control file
  if ( !$noupdate ) {
    if ( !open (tb, ">$table") ) {
      print STDERR "Warning: cannot update control file $table - continuing\n";
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
  $date = `date`;
  chop ($date);

  # In one pass the report is generated, and the control file rewritten.

  foreach $name (@targets) {
    if ($name =~ /^-/ ) {
      $subtitle = $';				#';
      print tb "$name\n" unless $noupdate;
      print STDERR "tb: $name\n" if $debug;
      $- = -1;
      next;
    }
    if ($name  =~ /^\*$prefix/ ) {
      print tb "$'\n" unless $noupdate;		#';
      print STDERR "tb: $'\n" if $debug;	#';
      next;
    }
    @a = split (/:/, $oldblocks{$name});
    unshift (@a, $newblocks{$name}) if $gather;
    $name = "." if $name eq $root;
    $name = $' if $name =~ /^$prefix/;		#';
    print STDERR "Warning: ", 1+$#a, " entries for $name\n"
      if ($debug && $#a != 8);

    # check for valid data
    $try = join(":",@a[0..7]);
    if ( $try eq ":::::::") {
      if ($retain) {
	@a = ("","","","","","","","");
      }
      else {
	# Discard
	print STDERR "--: $name\n" if $debug;
	next;
      }
    }

    $line = "$name\t$try\n";
    print tb $line unless $noupdate;
    print STDERR "tb: $line" if $debug;

    $blocks = $a[0];
    if ( !$allstats ) {
      $d_day = $d_week = "";
      if ($blocks ne "") {
	if ($a[1] ne "") {		# dayly delta
	  $d_day = $blocks - $a[1];
	  $d_day = "+" . $d_day if $d_day > 0;
	}
	if ($a[7] ne "") {		# weekly delta
	  $d_week = $blocks - $a[7];
	  $d_week = "+" . $d_week if $d_week > 0;
	}
      }
    }
    write;
  }

  # Close control file, if opened
  close (tb) unless $noupdate;
}
