#!/usr/bin/perl

# This program requires perl version 3.0, patchlevel 4 or higher.

# Copyright 1990 Johan Vromans, all rights reserved.
# This program may be used, modified and distributed as long as
# this copyright notice remains part of the source. It may not be sold, or 
# be used to harm any living creature including the world and the universe.

$my_name = $0;

################ usage ################

sub usage {
  local ($help) = shift (@_);
  local ($usg) = "usage: $my_name [-c ctlfile][-i input][-d][-g][-h][-r][-u] [dir]";
  die "$usg\nstopped" unless $help;
  print STDERR "$usg\n";
  print STDERR <<EndOfHelp

    -c ctlfile  - file which controls which dirs to report [def = dir/.du.ctl]
    -i input    - input data as obtained by 'du dir' [def = 'du dir']
    -d          - provide trace info
    -g          - gather new data
    -h          - this help message
    -r          - do not discard entries which don't have data
    -u          - update the control file with new values
    dir         - path to which files in the control file are relative
EndOfHelp
  ;
  exit 1;
}

################ main stream ################

&do_get_options;	# process options
&do_parse_ctl;		# read the control file
&do_prepare;		# prepare data
&do_gather if $gather;	# gather new info
&do_report_and_update;	# report and update

################ end of main stream ################

################ other subroutines ################

sub do_get_options {

  # Default values for options

  $debug = 0;
  $noupdate = 1;
  $retain = 0;
  $gather = 0;

  # Command line options. We use a modified version of getopts.pl.

  &usage (0) if &Getopts ("c:dghi:ru");
  &usage (1) if $opt_h;
  &usage (0) if $#ARGV > 0;

  if ( $#ARGV == 0 ) {
    $root = shift (@ARGV);
    $root = $` while ($root =~ m|/$|);
    $prefix = "$root/";
    $root = "/" if $root eq "";
  }
  else {
    $prefix = $root = "";
  }

  $debug    |= $opt_d if defined $opt_d;	# -d -> debug
  $gather   |= $opt_g if defined $opt_g;	# -d -> gather new data
  $retain   |= $opt_r if defined $opt_r;	# -r -> retain old entries
  $noupdate = !$opt_u if defined $opt_u;	# -u -> update the control file

  if (defined $opt_i) {		# -i input file
    $du = $opt_i;
  }
  if (defined $opt_c) {		# -c control_file
    $table = $opt_c;
  }
  else {
    $table = "$prefix.du.ctl";
  }

  if ($debug) {
    print STDERR "@(#)@ dusage	1.2 - dusage.pl\n";
    print STDERR "Options:";
    print STDERR " debug" if $debug;	# silly, isn't it...
    print STDERR $noupdate ? " no" : " ", "update";
    print STDERR $retain ? " " : " no", "retain";
    print STDERR $gather ? " " : " no", "gather";
    print STDERR "\n";
    print STDERR "Root = $root [prefix = $prefix]\n";
    print STDERR "Control file = $table\n";
    print STDERR "Input data = $du\n" if defined $du;
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
  #
  # To add a new dir, just add the name. The special name '.' may 
  # be used to denote the $root totals. It is added automatically if -t is
  # supplied.
  #
  # Upon completion:
  #  - %oldblocks is filled with the previous values,
  #    colon separated, for each directory.
  #  - @globs is filled with the globs used.
  #  - @targets contains a list of names to be looked for.

  open (tb, "<$table") || die "Cannot open control file $table, stopped";
  @targets = ();
  @globs = ();
  %oldblocks = ();
  %newblocks = ();

  while ($tb = <tb>) {
    chop ($tb);

    # preferred syntax: <dir><TAB><size>:<size>:....
    # allowable	      <dir><TAB><size> <size> ...
    # possible	      <dir>

    if ($tb =~ /^(.+)\t([\d: ]+)/) {
      $name = $1;
      @blocks = split (/[ :]/, $2);
    }
    else {
      $name = $tb;
      @blocks = ("","","","","","","","");
    }

    # Check for globs ...
    if ( $name =~ /\*|\?/ ) {
      $glob = "$prefix$name";
      printf STDERR "glob: $glob\n" if $debug;
      foreach $n ( <${glob}> ) {
	next unless -d $n;
	$n = $' if $n =~ /^$prefix/;	#';
	if ( !defined $oldblocks{$n} ) {
	  $oldblocks{$n} = ":::::::";
	  push (@targets, "$prefix$n");
	}
	printf STDERR "glob: -> $n\n" if $debug;
      }
      # Put on the globs list, and terminate this entry
      push (@globs, $name);
      next;
    }

    if ($name eq ".") {
      $name = $rname = $root;
    } else {
      $rname = "$prefix$name";
    }

    # Don't add targets more than once ...
    push (@targets, "$rname") unless (defined $oldblocks{$name});
    # ... but allow the entry to be rewritten (in case of globs)
    $oldblocks{$name} = join (":", @blocks[0..7]);

    print STDERR "tb: $name\t$oldblocks{$name}\n" if $debug;
  }
  close (tb);
}

sub do_prepare {

  # Build a targets match string, and an optimized list of directories to
  # search.
  $targets = "//";
  @list = ();
  undef $last;
  foreach $name (sort (@targets)) {
    if ($name =~ m|^$prefix|) {
      $targets .= "$'//"; 
    }
    else {
      $targets .= "$name//"; 
    }
    if (defined $last && $name =~ m|^$last/|) {
      next;
    }
    push (@list, $name);
    $last = $name;
  }

  print STDERR "targets: $targets\n" if $debug;
  print STDERR "list: @list\n" if $debug;

  # Prepare update of the control file
  if ( !$noupdate ) {
    if ( !open (tb, ">$table") ) {
      warn "Warning: cannot update control file $table";
      $noupdate = 1;
    }
  }
}

sub do_gather {

  $du = "du @list|" unless $opt_i; # in which case we have a data file

  # Process the data. If a name is found in the target list, 
  # %newblocks will be set to the new blocks value.

  open (du, "$du") || die "Cannot get data from $du, stopped";
  while ($du = <du>) {
    chop ($du);
    ($blocks,$name) = split (/\t/, $du);
    $name = $' if $name =~ m|$prefix|;	#';
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
Disk usage statistics                      @<<<<<<<<<<<<<<<
$date

 blocks    +day     +week  (sub)tree
-------  -------  -------  --------------------------------
.
format std_out =
@>>>>>> @>>>>>>> @>>>>>>>  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<..
$blocks, $d_day, $d_week, $name
.

sub do_report_and_update {

  $^ = "std_hdr";
  $~ = "std_out";
  $date = `date`;
  chop ($date);

  # In one pass the report is generated, and the control file rewritten.

  foreach $name (sort (keys (%oldblocks))) {
    $fname = $name;
    $fname = "." if $name eq $root;
    @a = split (/:/, $oldblocks{$name});
    unshift (@a, $newblocks{$name}) if $gather;

    if ($#a < 0) {	# no data?
      if ($retain) {
	@a = ("","","","","","","","");
      }
      else {
	# Discard
	print STDERR "--: $name\n" if $debug;
	next;
      }
    }
    print STDERR "Warning: ", 1+$#a, " entries for $name\n"
      if ($debug && $#a != 8);
    $line = "$fname\t" . join(":",@a[0..7]) . "\n";
    print tb $line unless $noupdate;
    print STDERR "tb: $line" if $debug;

    $blocks = $a[0];
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
    $name = "$prefix$name" unless $name eq $root;
    write;
  }

  # Add the globs to the control file
  foreach $glob ( @globs ) {
    print tb $glob, "\n" unless $noupdate;
    print STDERR "tb: $glob\n" if $debug;
  }

  # Close control file, if opened
  close (tb) unless $noupdate;
}

# Modified version of getopts ...

sub Getopts {
    local($argumentative) = @_;
    local(@args,$_,$first,$rest);
    local($opterr) = 0;

    @args = split( / */, $argumentative );
    while(($_ = $ARGV[0]) =~ /^-(.)(.*)/) {
	($first,$rest) = ($1,$2);
	$pos = index($argumentative,$first);
	if($pos >= $[) {
	    if($args[$pos+1] eq ':') {
		shift(@ARGV);
		if($rest eq '') {
		    $rest = shift(@ARGV);
		}
		eval "\$opt_$first = \$rest;";
	    }
	    else {
		eval "\$opt_$first = 1";
		if($rest eq '') {
		    shift(@ARGV);
		}
		else {
		    $ARGV[0] = "-$rest";
		}
	    }
	}
	else {
	    print stderr "Unknown option: $first\n";
	    $opterr++;
	    if($rest ne '') {
		$ARGV[0] = "-$rest";
	    }
	    else {
		shift(@ARGV);
	    }
	}
    }
    return $opterr;
}
