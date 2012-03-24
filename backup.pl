#!/usr/bin/perl

use Time::HiRes qw(time);

$PERL_START = time;
#printf "%.2f", $PERL_START;
#print "\n";
#printf "%.2f", 0.1;
#print "\n";
#exit;


#use File::Find;
use File::Spec::Functions;
use File::Copy;
use File::Path qw(make_path);
use File::Basename;

use POSIX qw(strftime);

use Term::ANSIColor;

use feature "switch";


use constant CATALOG_DIR => "/mnt/ex/linux/backup/arch/perl/.catalog";
use constant TREE_DIR => ("/mnt/ex/linux/backup/arch/perl/" . strftime("%Y.%m.%d-%H.%M.%S", localtime));
use constant INCLUDE_FILE => "/tmp/lb.filelist";
use constant EXCLUDE_FILE => "/etc/backup.exclude";

use constant PRINT_INDENT => 8;
use constant PRINT_DESCRIPTION => "\n[" . colored("%8s", "yellow") . "] " . colored("%-" . (PRINT_INDENT) . "s", "green") . ": " . colored("%s", "bold") . "\n";
use constant PRINT_ACTION => (" " x 11) . colored("%" . (PRINT_INDENT + 7) . "s", "blue") . ": %s\n";

our $_WRNothing = 0, $_WRCatalog = 1, $_WRLink = 2, $_WRSymlink = 3, $_WRMkdir = 4;

our $DRY_RUN = 0;

sub is_excluded {
	my $file = shift;
	return ($file ~~ @_) if @_;
	return 0;
}

sub print_action {
	printf PRINT_ACTION, @_;
#	my ($action, $text) = @_;
#	print colored(sprintf("%" . (PRINT_INDENT + 7) . "s", $action), "blue");
#	print ": ";
#	#print colored($text, "bold");
#	print $text;
#	print "\n";
}

sub print_description {
	printf PRINT_DESCRIPTION, sprintf("%.3f", (time - $PERL_START)), @_;
#	my ($description, $text) = @_;
#	print colored(sprintf("%-" . (PRINT_INDENT) . "s", $description), "green");
#	print ": ";
#	print colored($text, "bold");
#	print "\n";
}

# Returns:
# 	_WRNothing: Nothing done
# 	_WRCatalog: File added to catalog and (hard)linked
# 	_WRLink: File (hard)linked
# 	_WRSymlink: File symlinked
#	_WRMkdir: Dir created
sub wanted {
	#my $fullFileName = $File::Find::name;
	my $fullFileName = shift;
	return $_WRNothing if !(-e $fullFileName);
	#my @excluded = @_;
	my $fullDirName = (fileparse($fullFileName))[1];
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		$atime,$mtime,$ctime,$blksize,$blocks)
			= lstat($fullFileName);
	my $catalogName = "$ino-$size-$mtime";
	my $fullCatalogName = canonpath(catfile(CATALOG_DIR, $catalogName));
	my $fullTreeName = canonpath(catfile(TREE_DIR, $fullFileName));
	if (is_excluded($fullFileName, @_)) {
		print_description("Exclude", $fullFileName);
		return $_WRNothing;
	}
	if (-d _) {
		print_description("Dir", $fullFileName);
		# directory (no entry in catalog)

		my $dir = canonpath(catdir(TREE_DIR, $fullFileName));

		print_action("mkdir", "`$dir'");

		if (!$DRY_RUN) {
			make_path($dir);
			chmod $mode, $dir;
			chown $uid, $gid, $dir;
			return $_WRMkdir;
		}
	} elsif (-l _) {
		print_description("SymLink", $fullFileName);
		# symbolic link... not sure what to do:
		# 	link to the original destination, or
		# 	link to the destination in the tree?
		#	for now, link to the original destination (no entry in catalog)

		my $origLocation = readlink $fullFileName;

		#print_action("symlink", "`$fullCatalogName' to `$origLocation'");
		print_action("symlink", "`$fullCatalogName'");
		print_action("to", "`$origLocation'");

		if (!$DRY_RUN) {
			# make sure the parent directory exists
			make_path(canonpath(catdir(TREE_DIR, $fullDirName)));
			#symlink $fullTreeName, $origLocation;
			symlink $origLocation, $fullTreeName;
			chmod $mode, $fullTreeName;
			chown $uid, $gid, $fullTreeName;
			utime $atime, $mtime, $fullTreeName;
			return $_WRSymlink;
		}
	} elsif (-f _) {
		print_description("File", $fullFileName);
		# plain file
		my $fullTreeName = canonpath(catfile(TREE_DIR, $fullFileName));
		my $catalogAdded = 0;
		if (!(-e $fullCatalogName)) {

			print_action("copy", "(catalog) `$fullCatalogName'");

			# catalog file does not exist...
			if (!$DRY_RUN) {
				File::Copy::copy $fullFileName, $fullCatalogName;
				chmod $mode, $fullCatalogName;
				chown $uid, $gid, $fullCatalogName;
				utime $atime, $mtime, $fullCatalogName;
			}
			$catalogAdded = 1;
		}

		#print_action("link", "`$fullCatalogName' to `$fullTreeName'");
		print_action("link", "`$fullCatalogName'");
		print_action("to", "`$fullTreeName'");

		if (!$DRY_RUN) {
			# make sure the parent directory exists
			make_path(canonpath(catdir(TREE_DIR, $fullDirName)));
			#link $fullCatalogName, $fullTreeName;
			link $fullTreeName, $fullCatalogName;
			return $_WRCatalog if $catalogAdded;
			return $_WRLink;
		}
	} else {
		print_description("Other", $fullFileName);
		# ignore FIFOs, special files, etc...
		return $_WRNothing;
	}
	return $_WRNothing;
}

if (!$DRY_RUN) {
	make_path(TREE_DIR);
	make_path(CATALOG_DIR);
}

#find(\&wanted, '/home/jeffrey/MC-Projects');

our @exclude_list = ( );
if (-e EXCLUDE_FILE) {
	open(my $fh, "<", EXCLUDE_FILE)
		or die "cannot open exclude file:" . EXCLUDE_FILE . "\n";
	while (<$fh>) {
		chomp $_;
		if ($_) {
			push @exclude_list, qr/$_/;
		}
	}
	close($fh);
}

#exit;

our $catalog = 0;
our $link = 0;
our $symlink = 0;
our $mkdir = 0;

open(my $fh, "<", INCLUDE_FILE)
	or die "cannot open include file:" . INCLUDE_FILE . "\n";
while (<$fh>) {
	chomp $_;
	my $ret = wanted($_, @exclude_list);
	given ($ret)  {
		when ($_WRCatalog)	{ $catalog ++; }
		when ($_WRLink)		{ $link ++; }
		when ($_WRSymlink)	{ $symlink ++; }
		when ($_WRMkdir)	{ $mkdir ++; }
	}
}
close($fh);

print_description("Stats", "$catalog added to catalog");
print_description("Stats", ($catalog + $link) . " (hard)linked");
print_description("Stats", "$symlink (sym)linked");
print_description("Stats", "$mkdir directories created");

if (!$DRY_RUN) {
	my $parentDir = catdir(TREE_DIR, '..');
	unlink catdir($parentDir, "latest");
	symlink TREE_DIR, catdir($parentDir, "latest");
}
