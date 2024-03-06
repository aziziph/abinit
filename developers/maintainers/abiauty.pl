# This script beautifies a Fortran source file or a collection of sources from
# a specific subdirectory or, from current directory and all src/* subdirectories.
# Copyright (C) 2007-2023 ABINIT group (LSi)
# This file is distributed under the terms of the
# GNU General Public License, see ~abinit/COPYING
# or http://www.gnu.org/copyleft/gpl.txt .
# For the initials of contributors, see ~abinit/doc/developers/contributors.txt 
#
# NOTE : under Unix, an abiauty script will be automatically generated by 
# the command  make perl  in the ~abinit directory.
#
# USAGE :
# unix shell: abiauty [-p] [-v] [-d subdirectory | sourcefile]
# Windows DOS box: [perl] abiauty.pl [-p] [-v] [-d subdirectory | sourcefile]
# Options:
# -p	original source files will be preserved; new files with .abiauty
# suffix will be written into same subdirectory
# -v	verbose mode
# -d	handle files in subdirectory instead of all files in src/*
#
# Algorithm :
# Big loop on the files to be treated
# For each file, read one line at a time, analyze it, possibly transform it, and write it..
# For each line, there is the possibility of five phases.
# The treatment of each line might begin at phase 5 (execution), depending on whether the previous line ended at phase 5.
# The first phase corresponds to the line that starts the ROBODOC header, with extration of some information.
# The second phase corresponds to the treatment of the ROBODOC header, including recognition of the NAME and SOURCE keywords.
# For the third phase and higher ones, one identifies the ROBODOC Last marker and switch back to phase 1 if identified.
# The third phase start to process the SOURCE section, and find program/subroutine/function... statement
# The fourth phase find executable subsection in source e.g. thanks to the identification of the !******** marker
#   One might come back to a phase 3 level if found end statement before executable section 

$, = ' ';               # set output field separator
$\ = "\n";              # set output record separator

# list of supported file types and corresponding file suffixes:
%Fsufix = ('Fortran','.F90'	);		
@Ftypes = keys(%Fsufix);	# list of file types only
#
@Modules = values(%Fsufix);	# modules list defaults to suffixes list
@SourceDirs = <. src/*>;	# directories list defaults to all source subdirs
# Robodoc definitions
$RobodocBegin = '!!****';	# Robodoc begin marker
$RobodocLast = '!!***';		# last source line
# required items in the specified order:
@RobodocRequ = ('NAME','SOURCE');
# Upper case keywords that should trigger a warning and exceptions ...
@UpCaseKeyWds = ('CASE','DO','ELSE','END','IF','SELECT','THEN');
# ... excluding if present in the following expressions ...
@UpCaseExcl =('DOS','DOWN','DOUBLE','DOCTYPE','MPI_SEND','ENDDEF','DOT_PRODUCT','IFC');
# ENDDEBUG and TODO are normally commented
#
# Indentation constants (that may be changed with caution):
# see WriteLine subroutine for usage
$IndentCols = 2;	# columns count for normal indentation
$IndentCont = 1;	# columns count for continuations
$IndentCase = 0;	# columns count for select case constructs
$IndentMPI = 10;	# columns to shift MPI #ifdef - #endif blocks
#
$debug = 0;			# verbose mode defaults to off
$preserve = 0;	# default is modify source files
# analyze options and parameters
$CurARG = 0;
while (1) {
	if ($ARGV[$CurARG] eq '-v') {
		$debug ++;	# 1 for verbose mode, 2 for intensive debugging, 3 for sub TrimString
		$CurARG++;
		next;
		}
	if ($ARGV[$CurARG] eq '-p') {
		$preserve = 1;	# leave original source files unchanged
		print 'Source files will be kept unchanged' if ($debug > 0);
		$CurARG ++;
		next;
		}
	last;
	}
if ($ARGV[$CurARG] eq '-d') {	# check if -d subdir
	if (! -d $ARGV[$CurARG+1]) {
		print "ERROR: directory $ARGV[$CurARG+1] not found";
		exit 16;
		}	
	@SourceDirs = ($ARGV[$CurARG+1]);	# sources subdirectory
	$CurARG += 2;
	}
elsif ($ARGV[$CurARG] ne '') {
	$fname = $ARGV[$CurARG];
 	while (($ftyp,$fsfx) = each(%Fsufix)) {
	  $suffix = substr($fname,-length($fsfx));	# get file suffix
		$filetyp = $ftyp if ($suffix eq $fsfx);
		}
	if ($filetyp eq '') {
		print "Unrecognized suffix for file $fname";
		exit 12;
		}
	if (! -e $fname) {
		print "ERROR: file $fname not found";
		exit 16;
		}
	@Modules = ($fname);	# single module file
	%ModTypes = ($fname,$filetyp);
	@SourceDirs = ();	# empty directories list
	$CurARG ++;
	}
if ($ARGV[$CurARG] ne '') {
	print "Unexpected argument: $ARGV[$CurARG]";
	exit 8;
	}
#
print "Analyzing modules @Modules in directories @SourceDirs";
# build modules list
foreach $dir (@SourceDirs) {
	foreach $ftyp (@Ftypes) {
		if (! -d $dir) {
			print "Skipping $dir, not a directory" if ($debug > 0);
			next;
			}
		print "Searching $dir for $ftyp modules" if ($debug > 0);
		@Files = (<${dir}/*${Fsufix{$ftyp}}> );
		foreach $fname (@Files) {
			%ModTypes = (%ModTypes,
			$fname,$ftyp);
			}
		}
	}
#
if ($debug > 0) {	# print modules list
	foreach $filetyp (@Ftypes) {
		@Files = ();
		while (($fname,$ftype) = each (%ModTypes)) {
			@Files = (@Files,$fname) if ($ftype eq $filetyp);
			}
		print "$filetyp modules:",@Files;
		}
	}
# for each module, read the source file and find the Robodoc section
foreach $fname (keys(%ModTypes)) {
        $ix = index($fname,'interfaces_');
        if ($ix >= 0) {
                print "Module $fname is a module, abiauty is still unable to treat it";
                next;
                }
        $ix = index($fname,'/m_');
        if ($ix >= 0) {
                print "Module $fname is a module, abiauty still unable to treat it";
                next;
                }
        $ix = index($fname,'/defs_');
        if ($ix >= 0) {
                print "File $fname is likely a module (defs_), abiauty still unable to treat it";
                next;
                }
	$rc = open(FILEIN,"<$fname");
	if ($rc eq '') {
		print "Unable to open file $fname, error $rc";
		next;
		}
        print "\nABIautifying module $fname" if ($debug > 0);
#
	open(FILEOUT,">$fname.abiauty") || die "Unable to open FILEOUT";
# pick file name in path
	$ix = index($fname,'/');
	$modname = $ix >= 0 ? substr($fname,$ix+1) : $fname;
	$dotx = index($modname,'.');
	$modname = substr($modname,0,$dotx);	# suppress suffix
# read the source file
        $linect = 0;		# line counter
	$phase = 1;		# phase number 1 to 6
	$ProgLvl = 0;	# program/subroutine level
	$IndentLvl = 0;	# indentation level (linked to ProgLvl, but not simply equal to it)
	$ModIntFc = 0;	# flag for interface within a Fortran module
	$noabicnt = 0;		# default is beautify every line
        $diffcnt = 0;		# count of changed lines
	READLOOP:
	while ($line = <FILEIN>) {
		$lineorig = $line;
		$linect ++;
		$len = length($line);
		$char1 = substr($line,0,1);
# Phase 5 (execution):
		if ($phase == 5) {
# a) check no_abiauty directive
			$ix = index($line,'no_abiauty');
			if ($ix >= 0) {
				$noabicnt = 1;		# keep unchanged the current line only
				$line5 = substr($line,$ix+10);
				($wd1,$wd2,$wd3) = split(' ',$line5);
				$wd2 = $wd1;
				$wd2 =~ y/0-9//d;		# check numeric
				$noabicnt = $wd1 + 1 if ($wd2 eq '');		# keep more lines unchanged
				print "Beginning no_abiauty section at line $linect for $noabicnt" if ($debug >= 2);
				}
# b1) prepare to remove blanks starting at column 2, for continuations too, or at column 1 for cpp directives. Keep comments unchanged.
			$line5 = $line;
			$ix = 0;
			while ($ix < $len) {
				$charx = substr($line,$ix,1);
				last if ($charx ne ' ');
				$ix ++;
				}
#     Make comments unchanged
                        if (($charx eq '!') && $noabicnt == 0 ) { 
				print "Identified comment at line $linect for noabicnt = $noabicnt" if ($debug >= 2);
                                $noabicnt++ ;
			        }
			if ($ix == 0) {
				$ix = 1;
				}
# b2) align continuations to column 1
			elsif (($charx eq '&') && $noabicnt == 0) {
				$line = substr($line,$ix);
				$char1 = $charx;
				$len -= $ix;
				$ix = 1;
				}
			while ($ix < $len) {
				$charx = substr($line,$ix,1);
				last if ($charx ne ' ');
				$ix ++;
				}
# b3) trim blanks
			$firstcol = $char1 eq '#' ? 0 : 1;
			if ($ix > $firstcol && $noabicnt == 0) {
				$line1 = substr($line,$ix);
				$line = $char1.$line1;
				$len = length($line);
				}
# c) insert blank into 'enddo' or 'endif' to beautify and handle as 'end do/if'
			$left6 = substr($line,0,6);
			if (($left6 eq ' enddo' || $left6 eq ' endif') && $noabicnt == 0) {
				$line1 = substr($line,4);
				$line = ' end '.$line1;
				$len ++;
				}
# d) check for upper case construct keywords that could fool this script
# According to the coding rules, Fortran keywords should not be written in upper case.
# When a violation of this rule occurs, a statement that is part of a special construct will go
# undetected (e.g. if, then, else, do, case, end). The script will not be able to recognize the
# beginning and end of this construct and will probably find an inconsistency later in the source file.
# Recovering from such an error is not an easy task and this script will abort the treatment. To
# help the programmer find his error, a simple warning is displayed in such a case.
			$line2 = &TrimString($line,$len);	# remove constants strings and comments
			if ($char1 ne '!') {
				$doifcase = '';
				foreach $kwd (@UpCaseKeyWds) {
					$ix = index($line2,$kwd);
					if ($ix >= 0) {
						$exception = 0;
						foreach $kwdx (@UpCaseExcl) {
							$ix2 = index($kwdx,$kwd);
							next if ($ix2 < 0);
							if ($kwdx eq substr($line2,$ix-$ix2,length($kwdx))) {
								$exception = 1;
								last;
								}
							}
						$doifcase = "$doifcase$kwd " if ($exception == 0);
						}
					}
				print "WARNING($fname): upper case construct keyword(s) $doifcase"."found at line $linect" if ($doifcase ne '');
				}
# e) check for multiple instructions on this line with do, if or select construct
# This is prohibited by coding rules! See note at step a) above
			$endInstr = length($line2) - 1;
			$semicols = 0;
			$doifcase = '';
			while (1) {
				$ix = -1;
				if ($char1 ne '!') {
					$ix = rindex($line2,';',$endInstr);		# process right to left
					$semicols ++ if ($ix >0);
					$len5 = $endInstr - $ix;
					$len5 -- if ($semicols == 1);			# chop \n
					}
				$line5 = substr($line2,$ix+1,$len5);		# fetch a single instruction
				($wd1,$wd2,$wd3,$wd4,$wd5,$wd6,$wd7,$wd8,$wd9) = split(' ',$line5);
				$wd1wd2 = "$wd1$wd2";
				$wd2wd3 = "$wd2$wd3";
				$kwd = $wd1;		# possible keyword of an if/do/select construct
 				$ix2 = index($line5,'then');
				$kwd = 'then' if ($ix2 > 0);
				if ($wd1 eq 'do' || (substr($wd1wd2,0,3) eq 'if(' && $ix2 > 0) || $wd1 eq 'else' || substr($wd1wd2,0,7) eq 'elseif(' || ($wd1 eq 'select' && substr($wd2wd3,0,5) eq 'case(' ) || substr($wd1wd2,0,5) eq 'case(' || substr($wd1wd2,0,11) eq 'casedefault' || ($wd1 eq 'end' && ($wd2 eq 'do' || $wd2 eq 'if' || $wd2 eq 'select') ) ) {
					$doifcase = "$doifcase$kwd ";
					print "ERROR($fname): $kwd construct statement encountered in no_abiauty section at line $linect" if ($noabicnt > 0); 
					}
				if ($ix < 1) {	# semicolon not found or first char
					print "ERROR($fname): semicolon found at line $linect with $doifcase statement" if ($semicols > 0 && $doifcase ne '');
					last;				# exit loop
					}
				print "Multiple instruction $semicols at line $linect: $line5" if ($debug >= 2);
				$endInstr = $ix - 1;		# prepare to find previous instruction
				}
# f) check for in-line comment and make sure it is not sticked to the end of the instruction as:  end if!
                        $charx = substr($line2,-1,1);		# last character in trimmed line
			if ($charx eq '!' && $comntcol1 > 1 && substr($line,$comntcol1 -1,1) ne ' ') {
				$line1 = substr($line,$comntcol1);
				$line5 = substr($line,0,$comntcol1);		# drop comment before parsing
				if ($noabicnt == 0) {
					$line = "$line5 $line1";
 					$len ++;
					}
				}
			$line5 = $semicol1 < 0 ? $line : substr($line,0,$semicol1);		# fetch first or single instruction
			($wd1,$wd2,$wd3,$wd4,$wd5,$wd6,$wd7,$wd8,$wd9) = split(' ',$line5);
			}
# This is the splitting of all lines that have not started being in phase 5.
                else {
			($wd1,$wd2,$wd3,$wd4,$wd5,$wd6,$wd7,$wd8,$wd9) = split(' ',$line);
			}
# Phase 1: make sure Robodoc module header follows
		if ($phase == 1) {
			$wd1hd6 = substr($wd1,0,6);
			$EndRobodoc = 0;	# flag for end of Robodoc header
			if ($wd1hd6 eq $RobodocBegin) {
				$hdrtyp = substr($wd1,6);
# check project
				$ix = index($wd2,'/');
				if($ix > 0) {
					$pjct = substr($wd2,0,$ix+1);		# get what should be the project name
					$sub = substr($wd2,$ix+1);	# get what should be the subroutine/module name
					print "Robodoc header $hdrtyp $pjct $sub begins at line $linect" if ($debug > 1);
					&WriteLine($line,$len);
                                        $phase = 2;
		         	        $itemNum = 0;
			                $section = '';
			                next;
	          			}
		         	}
         		}
# Phase 2: check the presence of defined Robodoc sections
		if ($phase == 2) {
			if ($wd1 eq '!!') {
				if ($section eq 'NAME') {	# check subroutine name
					if ($wd2 ne '') {
						$section = '';
						$subname = $wd2;
						}
					}
				($item = $wd2) =~ tr/a-z/A-Z/;	# copy, then translate lowercase to uppercase
				if ($item eq $wd2) {		# was already uppercased ?
					if ($wd2 eq $RobodocRequ[$itemNum]) {	# expected section ?
						print "Found $wd2 item at line $linect" if ($debug > 1);
						if ($wd2 eq 'SOURCE') {
							&WriteLine($line,$len);
							$phase = 3;		# phase 3: read source
							$cppifLvl = 0; # nested cpp #if blocks level
							$MPIdefLvl = 0;	# MPI definition #if level
							$itemNum = 0;
							$continuct = 0;	# indentation count for continuation lines
							$ifcontinu = 0;	# remember an if has been found with continuation
							next;
							}
						else {
							$section = $wd2;
							$itemNum ++;
							}
						}
					}
				}
			}
# end of phase 2 processing
# phases 3 and subsequent: check Robodoc last line
		if ($phase >= 3) {
# turn flag on if Robodoc last line was found
			if ($EndRobodoc == 0 && $wd1 eq $RobodocLast) {
				print "Robodoc fence encountered at line $linect" if ($debug > 1);
				print "ERROR($fname): executable section not found" if ($phase == 4);
				$EndRobodoc = 1;
				$phase = 1;		# search for a possible following robodoc header if
				}
			}
		$wd1hd9 = substr($wd1,0,9);
		$wd2hd9 = substr($wd2,0,9);
		if ($phase == 3) {
# phase 3: process SOURCE section, find program/subroutine/function... statement
# following SOURCE we should have the program or subroutine definition
# ignore empty lines, comments and cpp directives
			if ($wd1 ne '' && $char1 ne '!' && $char1 ne '#') { 
				if ($wd1 eq 'program' || $wd1 eq 'module' || $wd1 eq 'interface' || $wd1 eq 'subroutine' || $wd1 eq 'function') {
                                        &HndlProg($wd1,$wd2);
                                        $IndentLvl += $IndentCols;
					}
				elsif ( ($wd2 eq 'function') && ($wd1 eq 'integer' || $wd1 eq 'complex' || $wd1 eq 'logical' || $wd1 eq 'recursive' || $wd1 eq 'pure' || $wd1hd9 eq 'character') ){
                                        &HndlProg($wd2,$wd3);
                                        $IndentLvl += $IndentCols;
					}
				elsif ( ($wd2 eq 'subroutine') && ($wd1 eq 'recursive') ){
                                        &HndlProg($wd2,$wd3);
                                        $IndentLvl += $IndentCols;
					}
				elsif ( ($wd3 eq 'function') && $wd1 eq 'double' && $wd2 eq 'precision') {
                                        &HndlProg($wd3,$wd4);
                                        $IndentLvl += $IndentCols;
					}
				elsif ( $wd1 eq 'end') {
					$ProgLvl --;
					$IndentLvl -= $IndentCols ;
					if ($ProgLvl < 0) {
						print "ERROR($fname): found end $wd2 statement at line $linect unrelated to any open block";
						last;
						}
					$ModIntFc = 0 if ( $wd2 eq 'interface' || ( $wd2 eq '' && $ProgType[$ProgLvl] eq 'interface' ) );
					}
				else {
					print "ERROR($fname): found $wd1 at line $linect while expecting program/subroutine";
					last;
					}
				&WriteLine($line,$len);
				$phase = 4;
				next;
				}
			}	# end of phase 3 processing
# Phase 4: find executable subsection in source
		if ($phase == 4) {
			if ($wd1 eq 'end' && ($wd2 eq 'subroutine' || $wd2 eq 'function' || $wd2 eq 'module')) {
				print "ERROR($fname): found end statement at line $linect for '' $wd2 $wd3 '' before executable section";
				&WriteLine($line,$len);
				$itemNum = 0;
				$phase = 3;
				next;
				}
			if ($wd1hd9 eq '!********' || $wd1hd9 eq '!Interfac' || ($wd1 eq '!' && $wd2hd9 eq '*********')) {
				print "Executable subsection encountered at line $linect" if ($debug > 1);
				&WriteLine($line,$len);
				$phase = 5;
				next;
				}
			}	# end of phase 4 processing
# Phase 5:
		if ($phase == 5) {
			$wd1wd2 = "$wd1$wd2";
			$wd2wd3 = "$wd2$wd3";
			$indentafter = 0;
# a) handle cpp #if-#endif blocks
			if (substr($wd1,0,3) eq '#if') {
				print "cpp #if block begins at line $linect" if ($debug > 1);
				$cppifLvl ++;
				if ((substr($wd1wd2,3,3) eq 'def' || index($line,' defined ') > 0) && index($line,' MPI') > 0) {
					$MPIdefLvl = $cppifLvl;
					print "#if cpp directive checks MPI definition at line $linect" if ($debug > 1);
					print "ERROR($fname): MPI definition checked in no_abiauty section at line $linect" if ($noabicnt > 0);
					}
				}
			elsif ($wd1wd2 eq '#endif') {
				if ($cppifLvl <= 0) {
					print "ERROR($fname): found #endif cpp directive at line $linect unrelated to any #if open block";
					last;
					}
				print "#endif closes cpp #if block at line $linect" if ($debug > 1);
				$cppifLvl --;
				if ($cppifLvl < $MPIdefLvl) {
					print "ERROR($fname): end of MPI block encountered in no_abiauty section at line $linect" if ($noabicnt > 0);
					$MPIdefLvl = 0;
					}
				}
# b) handle continuations
			if ($continued && $char1 eq '&') {
				$continuct = $IndentCont;
				print "Continuation found at line $linect" if ($debug > 1);
				}
			else {
				$continuct = 0;
				}
			$continued = ($line =~ m/.*&\s*\n$/) if ($char1 ne '!');;	# continued non-comment line ?
#
			if ($continued == 0 && $ifcontinu) {	# was if statement/construct pending ?
				if ($line =~ m/.*\)?\s*then\s*(!.*)?\n$/ ) {	# ends with "[)] then [comment]" ?
		  		&HndlProg('if','construct');
                                $IndentLvl += $IndentCols;
		  		$indentafter = $IndentCols ;
					}
				elsif ($char1 ne '!') {
					print "if statement encountered at line $linect" if ($debug > 1);
					}
				$ifcontinu = 0;
				}
# c) record subprogram type and name to check subsequent end statement
			if ($wd1 eq 'subroutine' || $wd1 eq 'interface' || $wd1 eq 'function') {
                                &HndlProg($wd1,$wd2);
                                $IndentLvl += $IndentCols;
				}
			elsif (($wd2 eq 'function') && ($wd1 eq 'integer' || $wd1 eq 'complex' || $wd1 eq 'logical' || $wd1hd9 eq 'character') ){
                                &HndlProg($wd2,$wd3);
                                $IndentLvl += $IndentCols;
				}
			elsif ($wd3 eq 'function' && $wd1 eq 'double' && $wd2 eq 'precision') {
                                &HndlProg($wd3,$wd4);
                                $IndentLvl += $IndentCols;
				}
# d) handle construct names
			$constrname = 'construct';		# default name
			if ($wd1wd2 =~ m/(^\w+):(\w*)/ ) {
				$constrname = $1;
				if ($wd2 eq ':') {
					$wd1 = $wd3;			# shift first words 2 times left
					$wd2 = $wd4;
					$wd3 = $wd5;
					$wd4 = $wd6;
					}
				elsif ( length($1) <= length($wd1)-2 ) {		# colon in the middle of first word
					$wd1 = substr($wd1,length($1)+1);	# drop name:
					}
				else {
					$wd1 = $2;		# drop name:
					$wd2 = $wd3;			# shift first words left
					$wd3 = $wd4;
					$wd4 = $wd5;
					}
				$wd1wd2 = "$wd1$wd2";
				$wd2wd3 = "$wd2$wd3";
				}
# e) handle do
			if ($wd1 eq 'do') {
                                &HndlProg($wd1,$constrname);
                                $IndentLvl += $IndentCols;
                                $indentafter = $IndentCols ;
				}
# f) handle 'if (' or 'if('
			if (substr($wd1wd2,0,3) eq 'if(' ) {
				if ($continued) {
					print "Continued if found at line $linect" if ($debug > 1);
					$ifcontinu = 1;		# if statement/construct pending
					}
				elsif ($line =~ m/.+\)\s*then\s*(!.*)?\n$/ ) {	# ends with ') then ' [comment] ?
                                        &HndlProg('if',$constrname);
                                        $IndentLvl += $IndentCols;
			  	        $indentafter = $IndentCols ;
					}
				else {
					print "if statement encountered at line $linect" if ($debug > 1);
					}
				}
# f2) handle else, 'elseif (' or 'elseif('
			if ($wd1 eq 'else' || substr($wd1wd2,0,7) eq 'elseif(') {
			  $indentafter = $IndentCols ;		# same block-level as previous if and same alignment
				}
# g) handle 'select case(' or 'select case ('
			if ($wd1 eq 'select' && substr($wd2wd3,0,5) eq 'case(') {
                                &HndlProg('select',$constrname);
                                $IndentLvl += $IndentCase;
                                $indentafter = $IndentCase ;
				}
# g2) handle 'case (' or 'case(' or 'case default'
			if (substr($wd1wd2,0,5) eq 'case(' || substr($wd1wd2,0,11) eq 'casedefault' ) {
				if ($ProgLvl > 0) {
					$PrevLvl = $ProgLvl - 1;
					if ($ProgType[$PrevLvl] eq 'select') {
                                                &HndlProg('case','construct');
                                                $IndentLvl += $IndentCols;
						}
					elsif ($ProgType[$PrevLvl] eq 'case') {
						print "case $ProgName[$PrevLvl] level $PrevLvl encountered at line $linect" if ($debug > 1);
						}
					else {
						print "ERROR($fname): found $wd1wd2 statement at line $linect unrelated to any select block";
						last;
						}
					}
			        $indentafter = $IndentCols ;
				}
# h) check end statements
			if ($wd1 eq 'end' && ($wd2 eq 'subroutine' || $wd2 eq 'module' || $wd2 eq 'interface' || $wd2 eq 'function' || $wd2 eq 'do' || $wd2 eq 'if' || $wd2 eq 'select' || $wd2 eq '') ) {
				$ProgLvl --;
				$IndentLvl -= $IndentCols ;
				if ($ProgLvl < 0) {
					print "ERROR($fname): found end $wd2 statement at line $linect unrelated to any open block";
					last;
					}
				$IndentLvl -= $IndentCase if ($wd2 eq 'select' && $ProgType[$ProgLvl] eq 'case');		
				$ProgLvl -- if ($wd2 eq 'select' && $ProgType[$ProgLvl] eq 'case');		# end select closes case(s) list first
				if ($ProgType[$ProgLvl] ne $wd2 || ($ProgName[$ProgLvl] ne $wd3 && (($wd3 ne '' && substr($wd3,0,1) ne '!') || $ProgName[$ProgLvl] ne 'construct') ) ) {
					print "ERROR($fname): found end statement at line $linect for '' $wd2 $wd3 '' instead of '' $ProgType[$ProgLvl] $ProgName[$ProgLvl] '' ";
					last;
					}
				print "end $ProgType[$ProgLvl] $ProgName[$ProgLvl] level $ProgLvl encountered at line $linect" if ($debug > 1);
				if ($ModIntFc == 1) {		# reset for next subroutine if any
					&WriteLine($line,$len);
					$itemNum = 0;
					$cppifLvl = 0; # nested cpp if blocks level
					$MPIdefLvl = 0;	# MPI definition #if level
					$phase = 3;
					next;
					}
				$ModIntFc = 0 if ($ProgType[$ProgLvl] eq 'interface');
				}
			}
# Phases 2 and subsequent: copy line from input file to FILEOUT
		&WriteLine($line,$len);
		}	# end while <FILEIN
# end of file or unrecoverable error has been encountered
	close (FILEOUT);
	close (FILEIN);
# were all sections and statements encountered ?
        if ($phase < 5 && $phase > 1) {
		print "ERROR($fname): end of file $fname hit prematurely while expecting:";
		print "  Robodoc $RobodocRequ[$itemNum] section" if ($phase == 2);
		print '  program/subroutine/function statement' if ($phase == 3);
		print '  delimitor for executable section' if ($phase == 4);
                next;		# process next subroutine
                }
	print "Processing of file $fname ended phase $phase item $itemNum line $linect" if($debug > 1);
        next if ($phase == 5 && $EndRobodoc == 0);	# fatal error, see last message; process next sub
# rename files if preserve option (-p) has not been specified
	if ($preserve == 0) {
		if ($diffcnt == 0) {
			unlink ("$fname.abiauty");	# suppress work file
			print "Module $fname was already beautified";
			}
		else {
			unlink ("$fname");			# suppress old file
			$rc = rename("$fname.abiauty",$fname);
			if ($rc != 1) {
				print "ERROR $! renaming $fname.abiauty to $fname";
				next;
				}
			print "Module $fname processing completed, $diffcnt lines changed";
			}
		next;
		}
	print "Module $fname processed completely and preserved";
	}

exit;
# ***************************
sub HndlProg { local ($type,$name) = @_;
  local ($ix);
# Purpose: build a stack of program/subroutine/function/do/if definitions
# Arguments: program/module/interface/subroutine/function type and name
# Common variables: $ProgLvl, $itemNum
# drop subroutine/function (parameters
	$ix = index($name,'(');
	$name = substr($name,0,$ix) if ($ix > 0);
# stack (sub)program type and name to check subsequent end statement
	$ProgType[$ProgLvl] = $type;
	$ProgName[$ProgLvl] = $name;
# check for interface within module
# handle first Program/Module/Subroutine
	print "$type $ProgName[$ProgLvl] level $ProgLvl encountered at line $linect" if ($debug >= 2);
	if ($ProgType[0] eq 'module' && $type eq 'interface') {
		$ModIntFc = 1;
# leaving itemNum unchanged will search for next subroutine/function...
		}
	if ($type eq 'subroutine' || $type eq 'interface' || $type eq 'function') {
		print "WARNING($fname): $type name found is $name instead of $subname" if ($name ne $subname && $debug > 0);
		}
	$ProgLvl ++;	# bump stack pointer
	return;
	}
# ***************************
sub WriteLine {	local ($line,$llen) = @_;
  local ($rc,$char1,$line1,$repeatct);
# Purpose: write one line to FILEOUT and check return code
# Arguments:  $line, $llen = line to be written and length
# Common variables: $IndentLvl,$indentafter,$fname,$diffcnt,$noabicnt
	$char1 = substr($line,0,1);
	$char2 = substr($line,0,2);
	$char5 = substr($line,0,5);
# print cpp directives, lines beginning with !$  (this is for OpenMP), and empty lines unchanged; set indentation for others
	if ($phase == 5 && $char1 ne '#' && $char2 ne '!$' && $char5 ne '!!OMP' && '!!$OM' && $line ne "\n" && $noabicnt == 0) { 
		$repeatct = $IndentLvl - $indentafter ;	# indentation increases AFTER do, if
		$repeatct += $continuct if ($char1 ne '!');	# add 1 col if continuation
		$repeatct += $IndentMPI if ($MPIdefLvl > 0);	# shift several col right if MPI block
		if ($char1 eq ' ' || $char1 eq '!' || $char1 eq '&') {
			$line1 = substr($line,1);
# 1st blank accounts in indentation offset
			$repeatct -= $IndentCols;
			$line = $char1.(' ' x $repeatct).$line1;
			}
		else {
# lines beginning at column 1: insert spaces ahead
			$line = (' ' x $repeatct).$line;
			}
		$llen = length($line);
		}
	$diffcnt ++ if ($line ne $lineorig);
	$rc = syswrite(FILEOUT,$line,$llen);
	if ($rc != $llen) {
		print "ERROR: $rc writing to $fname.abiauty";
		exit 100;
		}
	$noabicnt-- if ($noabicnt > 0);
	return;
	}
# ***************************
sub TrimString { local ($line, $llen) = @_;
  local ($ix,$charx,$charp,$colstart,$offset,$strend,$strstart,$strdelim,$strlen,$strchars);
  local ($trimleft,$trimline,$trimdiff);
# Purpose: find character strings in a Fortran source line, trim strings and comments
# Arguments:  $line, $llen = line to be trimmed and length
# Common variables: $linect,$comntcol1,$semicol1
# Note setting $debug to 3 helps to debug this routine
  $strend = '';
  $trimline = $line;
  $trimdiff = 0;
  $strstart = -2;	# no string found yet
  $ix = -1;
# find string delimitor
  $comntcol1 = -1;
  $semicol1 = -1;
  while ($ix < $llen) {
    $ix ++;
    $charx = substr($line,$ix,1);
    if (substr($strend,-9) eq 'continued') {
      next if ($charx eq ' ');
      $ix = -1 if ($charx ne '&');	# string continuation begins in col 1
      $charx = $strdelim;		# assume delimitor has been found there too
      $strend = '';
      $colstart = $ix + 2;
      print "Continuation start at column $colstart of line $linect" if ($debug >= 3);
      }
    if ($charx eq '!') {
      $comntcol1 = $ix;		# index of comment delimitor
      $ix ++;
      print "Comment at line $linect column $ix" if ($debug >= 3);
      $offset = $ix -$trimdiff;
      $trimline = substr($trimline,0,$offset);
      $strstart = $ix;
      last;
      }
    $semicol1 = $ix if ($charx eq ';');	# index of first semicolon
    if ($charx eq "\'" || $charx eq "\"") {
      $strstart = $ix + 1;	# >=0 when string begins
      $colstart = $strstart + 1;
      $strdelim = $charx;
      $strend = 'end';
      $charp = $charx;	# previous character in string
# find end of string delimitor
      while ($ix < $llen) {
        $ix ++;
        $charx = substr($line,$ix,1);
    		$semicol1 = $ix if ($semicol1 == -1 && $charx eq ';');	# index of first semicolon
        if ($charx eq $strdelim) {		# same string delimitor ?
          if ($charp eq "\\" || $charp eq $strdelim) {		# escaped delimitor ?
            $charp='';
            }
          else {
            $charp=$charx;
            }
          next;
          }
        if ($charp eq $strdelim) {		# was previous character the same string delimitor ?
          if ($ix == $strstart) {		# begin delimitor
            $charp=$charx;
            next;
            }
          $strlen = $ix - $strstart - 1;
          $strchars = substr($line,$strstart,$strlen);
          print "String at line $linect, columns $colstart:$strlen=$strchars" if ($debug >= 3);
          $offset = $colstart - $trimdiff - 1;
          $trimleft = substr($trimline,0,$offset);
          $offset += $strlen;
          $trimline = $trimleft.substr($trimline,$offset);
          $trimdiff += $strlen;
          $strstart = -1;	# end of string found
          last;
          }
        if ($charx eq '&' && $charp ne "\\") {  # continuation delimitor UNescaped
          $strlen = $ix-$strstart;
          $strchars = substr($line,$strstart,$strlen);
          $strend = "$strlen, continued";
          $ix = $llen;	# skip remainder
          last;
          }
        $charp = $charp eq "\\" && $charx eq "\\" ? '' : $charx;  # escaped backslash
        }
      }
    if ($strstart > 0 && $debug >= 3) {
      if($strend eq 'end') {
        $strchars = substr($line,$strstart);		# remainder of line
        $offset = $colstart - $trimdiff - 1;		# length of left part
        $trimline = substr($trimline,0,$offset);
        }
      else {
        $offset = $colstart - $trimdiff - 1;		# length of left part
        $trimline = substr($trimline,0,$offset).'&';	# remainder of line (comment) is dropped
        }
      print "String at line $linect, columns $colstart:$strend=$strchars";
      }
    }
  if ($debug >= 3 && $strstart >= -1 && $comntcol1 != 0) {
    print "$linect < $line";
    print "$linect > $trimline";
    }
  return $trimline;
  }
