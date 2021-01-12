# dusage

`dusage` is a utility to generate disk space usage reports.

[![License](https://img.shields.io/badge/License-Artistic-blue.svg)](https://github.com/sciurius/dusage/LICENSE.md)
[![LocCount](https://img.shields.io/tokei/lines/github/sciurius/dusage.svg)](https://github.com/XAMPPRocky/tokei)
[![GitHubCodeSize](https://img.shields.io/github/languages/code-size/sciurius/dusage.svg)](https://github.com/sciurius/dusage)
[![LgtmAlerts](https://img.shields.io/lgtm/alerts/g/sciurius/dusage.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/sciurius/dusage/alerts/)
[![CodeBeatadge](https://codebeat.co/badges/ff68217a-76ec-467c-8ecd-c49c4491c6ae)](https://codebeat.co/projects/github-com-sciurius-dusage-master)
[![CodeclimateMaintainability](https://api.codeclimate.com/v1/badges/bbc4379b8c69ca2693e6/maintainability)](https://codeclimate.com/github/sciurius/dusage/maintainability)
[![TickgitTODOs](https://img.shields.io/endpoint?url=https://api.tickgit.com/badge?repo=github.com/sciurius/dusage)](https://www.tickgit.com/browse?repo=github.com/sciurius/dusage)
[![DeepSourceA](https://deepsource.io/gh/johnsonjh/dusage.svg/?label=active+issues)](https://deepsource.io/gh/johnsonjh/dusage/?ref=repository-badge)
[![DeepSourceR](https://deepsource.io/gh/johnsonjh/dusage.svg/?label=resolved+issues)](https://deepsource.io/gh/johnsonjh/dusage/?ref=repository-badge)

------

## Overview

Guarding disk space is one of the main problems of system management.

A long time ago, [Johan Vromans](https://johan.vromans.org/) created
`dusage` by converting an old `awk`/`sed`/`sh` script used to keep
track of disk usage to a new Perl program, adding features and new
options, including a manual page.

Provided a list of paths, `dusage` filters the output of `du` to find
the amount of disk space used for each of the paths, collecting the
values in one `du` run. It adds the new value to the list, shifting old
values up. It then generates a nice report of the amount of disk space
occupied in each of the specified paths, together with the amount it
grew (or shrank) since the previous run, and since seven runs ago.

When run daily, `dusage` outputs daily and weekly reports.

## Warning

This program was written in 1990 for Perl 3.0. Some parts were
later updated for Perl 5 compatibility. As a result, the source
code might be somewhat ugly.

## Availability

### Source Code

* [GitHub](https://github.com/sciurius/dusage)

## Issue Tracking

* Please use the [GitHub issue tracker](https://github.com/sciurius/dusage/issues).

## Requirements

* Perl version 5 or higher

## Author

* [Johan Vromans](https://johan.vromans.org/)

## License

This software is made available under the terms of the
*[Artistic License](https://github.com/sciurius/dusage/LICENSE.md)*.
