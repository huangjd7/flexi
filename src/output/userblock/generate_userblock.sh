#!/bin/bash
#************************************************************************************
#
# Author:       Thomas Bolemann
# Institution:  Inst. of Aero- and Gasdynamics, University of Stuttgart
# Date:         07.07.2016
#
# Description:  This script will generate a userblock file to be appended to
#               executables or simulation results enabling the exact rebuilding of
#               of the simulation code, which was used to generate those results.
#               A patch to the remote Git branch of the current code is generated
#               or to the master, if the branch does not exist on the remote.
# 
#************************************************************************************

# $1: CMAKE_RUNTIME_OUTPUT_DIRECTORY
# $2: CMAKE_CACHEFILE_DIR
# $3: CMAKE_CACHE_MAJOR_VERSION.CMAKE_CACHE_MINOR_VERSION.CMAKE_CACHE_PATCH_VERSION
# $4: CMAKE_CURRENT_SOURCE_DIR

if [ ! -d "$1" ]; then
  exit 1;
fi
if [ ! -d "$2" ]; then
  exit 1;
fi

# get branch name (only info)
BRANCHNAME=$(git rev-parse --abbrev-ref HEAD)
PARENTNAME=$BRANCHNAME
PARENTCOMMIT=$(git show-ref | grep "origin/$BRANCHNAME$" | cut -b -40)

if [ -z "$PARENTCOMMIT" ]; then
  LOCBRANCHNAME=$BRANCHNAME
  # recursively search for parent branch
  FOUND=0
  while [ $FOUND -eq 0 ]; do
    # get commit on server, where branch started
    COLUMN=$((    $(git show-branch | grep '^[^\[]*\*'  | head -1 | cut -d* -f1 | wc -c) - 1 )) 
    START_ROW=$(( $(git show-branch | grep -n "^[\-]*$" | cut -d: -f1) + 1 )) 
    PARENTNAME=$(   git show-branch | tail -n +$START_ROW | grep -v "^[^\[]*\[$LOCBRANCHNAME" | grep "^.\{$COLUMN\}[^ ]" | head -n1 | sed 's/.*\[\(.*\)\].*/\1/' | sed 's/[\^~].*//')
    if [ -z "$PARENTNAME" ]; then
      break
    fi
  
    PARENTCOMMIT=$(git show-ref | grep "origin/$PARENTNAME$" | cut -b -40)
    if [ -z "$PARENTCOMMIT" ]; then
      LOCBRANCHNAME=$PARENTNAME 
    else
      FOUND=1
      break
    fi
  done

  if [ $FOUND -eq 0 ]; then
    PARENTNAME='master'
    PARENTCOMMIT=$(git rev-parse origin/master)
    echo "WARNING: Could not find parent commit, creating userblock diff to master."
  fi
fi

cd "$1"
echo "{[( CMAKE )]}"               >  userblock.txt
cat configuration.cmake            >> userblock.txt
echo "{[( GIT BRANCH )]}"          >> userblock.txt
echo "$BRANCHNAME"                 >> userblock.txt
echo $(git rev-parse HEAD)         >> userblock.txt

# Reference is the start commit, which is either identical to
# the branch, if it exists on the remote or points to the first
# real parent in branch history available on remote.
echo "{[( GIT REFERENCE )]}"       >> userblock.txt
echo "$PARENTNAME"                 >> userblock.txt
echo $PARENTCOMMIT                 >> userblock.txt

#echo "{[( GIT FORMAT-PATCH )]}"    >> userblock.txt
## create format patch containing log info for commit changes
## PARENT should be identical to origin
#git format-patch $PARENTCOMMIT..HEAD --minimal --stdout >> $1/userblock.txt

# Also store binary changes in diff
echo "{[( GIT DIFF )]}"            >> userblock.txt
# commited changes
git diff -p $PARENTCOMMIT..HEAD    >> userblock.txt
# uncommited changes
git diff -p                        >> userblock.txt

echo "{[( GIT URL )]}"             >> userblock.txt
git config --get remote.origin.url >> userblock.txt

# change directory to cmake chache dir
cd "$2/CMakeFiles"
# copy compile flags of the flexi(lib) to userblock
echo "{[( libflexistatic.dir/flags.make )]}" >> $1/userblock.txt
cat libflexistatic.dir/flags.make            >> $1/userblock.txt
echo "{[( libflexishared.dir/flags.make )]}" >> $1/userblock.txt
cat libflexishared.dir/flags.make            >> $1/userblock.txt
echo "{[( flexi.dir/flags.make )]}"          >> $1/userblock.txt
cat flexi.dir/flags.make                     >> $1/userblock.txt

# change directory to actual cmake version
cd "$3"
# copy detection of compiler to userblock
echo "{[( COMPILER VERSIONS )]}"           >> $1/userblock.txt
cat CMakeFortranCompiler.cmake             >> $1/userblock.txt


cd "$1" # go back to the runtime output directory
# generate C print commands to print userblock: 
#      replace \ by \\
#                    replace " by \"
#                                              prepend fprintf to line
#                                                              append end of line 
sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/^/   fprintf(fp, "/' -e 's/$/\\n");/' userblock.txt > userblock_print.txt
# copy empty source file template
cp "$4/src/output/userblock/read_userblock.c" .
# insert userblock print commands
sed -i -e '/INSERT_BUILD_INFO_HERE/r userblock_print.txt' read_userblock.c
