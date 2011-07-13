#!/bin/bash
set -eu

# This script is usually run by run_tests.sh script, see there for some
# comments.

# You can disable heaptrc for shorter output (useful only for debug builds
# that have heaptrc compiled in)
export HEAPTRC=disabled

if [ -f view3dscene ]; then
  VIEW3DSCENE=./view3dscene
else
  # expect view3dscene on $PATH
  VIEW3DSCENE=view3dscene
fi

# For some tests (by default commented out, see lower in this script)
# you need a 2nd view3dscene binary. Usually you want to use
# some older, stable view3dscene release as "other" below,
# and as $VIEW3DSCENE use newer view3dscene from SVN or nightly snapshots.
#VIEW3DSCENE_OTHER="$VIEW3DSCENE"
VIEW3DSCENE_OTHER=view3dscene-3.10.0-release

FILE="$1"

# It's important that temp_file is inside the same directory,
# otherwise re-reading it would not work because relative URLs
# are broken.
TEMP_FILE=`dirname "$FILE"`/view3dscene_test_temporary_file.wrl

echo '---- Reading' "$FILE"
#echo '(temp is ' "$TEMP_FILE" ')'
"$VIEW3DSCENE" "$FILE" --write --encoding=classic > "$TEMP_FILE"

# Check input file and output file headers.
# They indicate VRML version used to write the file.
# They should match, otherwise SuggestVRMLVersion of some nodes
# possibly doesn't work and the resulting file has different VRML version.
#
# Note that this test works only with classic VRML files (XML X3D versions,
# or gzip compressed, have version elsewhere, other 3D formats are converted
# to any version we like, and output is always classic VRML --- so comparison
# has no sense).

FILE_EXTENSION=`stringoper ExtractFileExt "$FILE"`

if [ '(' '(' "$FILE_EXTENSION" = '.wrl' ')' -o \
         '(' "$FILE_EXTENSION" = '..x3dv' ')' ')' -a \
     '(' `basename "$FILE"` != cones_gzipped_but_with_normal_extension.wrl ')' ]; then
  INPUT_HEADER=`head -n 1 "$FILE"`
  OUTPUT_HEADER=`head -n 1 "$TEMP_FILE"`

  # trim both headers, to trim possibly different newlines
  # (maybe they are stripped by ` already?)
  # and whitespace around.
  INPUT_HEADER="`stringoper Trim \"$INPUT_HEADER\"`"
  OUTPUT_HEADER="`stringoper Trim \"$OUTPUT_HEADER\"`"

  if [ "$INPUT_HEADER" != "$OUTPUT_HEADER" ]; then
    echo 'WARNING: input/output headers differ:'
    echo 'Header on input is' "$INPUT_HEADER"
    echo 'Header on output is' "$OUTPUT_HEADER"
  fi
fi

echo '---- Reading again' "$FILE"
"$VIEW3DSCENE" "$TEMP_FILE" --write --encoding=classic > /dev/null

rm -f "$TEMP_FILE"

# SaveToStream comparison ----------------------------------------------------

do_compare_classic_save ()
{
  SAVE_CLASSIC_OLD=`stringoper ChangeFileExt "$FILE" _classic_save_test_old.x3dv`
  SAVE_CLASSIC_NEW=`stringoper ChangeFileExt "$FILE" _classic_save_test_new.x3dv`

  echo '---- Comparing classic save with' "$VIEW3DSCENE_OTHER"
  "$VIEW3DSCENE_OTHER" "$FILE" --write-to-vrml > "$SAVE_CLASSIC_OLD"
  "$VIEW3DSCENE"       "$FILE" --write-to-vrml > "$SAVE_CLASSIC_NEW"
  diff -wur "$SAVE_CLASSIC_OLD" "$SAVE_CLASSIC_NEW"

  rm -f "$SAVE_CLASSIC_OLD" "$SAVE_CLASSIC_NEW"
}

# Uncomment this to compare classic save with other (older?) view3dscene version.
# Uses --write (--write-to-vrml for older view3dscene versions) to save,
# and standard Unix "diff" to compare.
# do_compare_classic_save

# Screenshot comparison ------------------------------------------------------

mk_screnshot ()
{
  echo '---- Rendering and making screenshot' "$VIEW3DSCENE_OTHER"
  "$VIEW3DSCENE_OTHER" "$FILE" --screenshot 0 --geometry 300x200 "$SCREENSHOT_OLD"
}

compare_screenshot ()
{
  echo '---- Comparing screenshot' "$VIEW3DSCENE"
  "$VIEW3DSCENE" "$FILE" --screenshot 0 --geometry 300x200 "$SCREENSHOT_NEW"

  # Don't exit on screenshot comparison fail. That's because
  # taking screenshots takes a long time, so just continue checking.
  # The caller will have to check script output to know if something failed.
  # (Also the comparison images will be left, unrecognized
  # by version control system, for cases that failed.)
  if image_compare "$SCREENSHOT_OLD" "$SCREENSHOT_NEW"; then
    true # do nothing
  else
    DELETE_SCREENSHOTS=''
  fi
}

do_compare_screenshot ()
{
  SCREENSHOT_OLD=`stringoper ChangeFileExt "$FILE" _test_screen_old.png`
  SCREENSHOT_NEW=`stringoper ChangeFileExt "$FILE" _test_screen_new.png`

  DELETE_SCREENSHOTS='t'

  mk_screnshot
  # You could comment this, if you only want to check if screenshot generation
  # works, without comparing if with older view3dscene.
  compare_screenshot

  if [ -n "$DELETE_SCREENSHOTS" ]; then
    rm -f "$SCREENSHOT_OLD"
    rm -f "$SCREENSHOT_NEW"
  fi
}

# Uncomment this to compare screenshots with other (older?) view3dscene version.
# Uses --screenshot to capture, and image_compare
# (see kambi_vrml_game_engine/examples/images/) to compare.
# This is quite longer test, but it nicely checks for any regressions
# in the renderer.
#
# The output (_test_screen*.png files that were not removed) should be examined
# by hand afterwards. Note that many differences should be ignored
# (OpenGL is not guaranteed to display the same scene pixel-by-pixel exactly
# the same if some state is different).
# do_compare_screenshot
