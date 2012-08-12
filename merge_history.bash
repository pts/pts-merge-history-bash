#
# merge_history.bash: merge bash history lines just like zsh merge_history
# by pts@fazekas.hu at Fri Mar 25 15:14:43 CET 2011
#
# * tested with bash 4.1.5 (on Ubuntu Lucid)
# * based on http://hints.macworld.com/dlfiles/preexec.bash.txt
# * based on http://stackoverflow.com/questions/103944/
#
# Installation:
#
# * Copy this file to ~/merge_history.bash .
# * Run this: touch ~/.merged_bash_history
# * Put (append) this to your ~/.bashrc: source "$HOME"/merge_history.bash
# * Set HISTSIZE and HISTFILESIZE to large enough values in your ~/.bashrc .
# * Close all your terminal windows (and SSH connections) and open new ones
#   to make the changes take effect.
# * If you want your old shell history to be reused, please copy
#   ~/.bash_history to ~/.merged_bash_history .
#
# zsh equivalent of this command:
#
#   setopt hist_ignore_dups share_history inc_append_history extended_history
#
# It's safe to reload this file by `source'-ing it to an existing bash.
#
# TODO(pts): Add support for multiline commands.

MRG_DONEI=":$SHELLOPTS:"
if test "${MRG_DONEI#*:history:}" != "$MRG_DONEI" &&
   (test "${BASH_VERSION#[5-9].}" != "$BASH_VERSION" ||
    test "${BASH_VERSION#4.[0-9].}" != "$BASH_VERSION") &&
   test "$HOME" &&
   test -f "$HOME/.merged_bash_history"; then

# Merge the timestamped .bash_history file on STDIN to $1. The output file
# is sorted by (timestamp, command), and duplicate (timestamp, command) tuples
# are removed.
#
# The implementation is very fast in the 2 most common cases:
#
# * Appending a few new entries.
# * Not changing it at all, because it's already up-to-date.
function _mrg_merge_ts_history() {
  PERL_BADLANG=x perl -e '
    use_integer;
    use strict;
    my $now = time;
    sub readhist($) {
      my $F = $_[0];
      my @lines;
      my $prefix;
      my $line;
      while (defined($line = <$F>)) {
        $line .= "\n" if substr($line, -1) ne "\n";
        if ($line =~ /^#(\d+)\n/) {
          $prefix = sprintf("%022d ", $1);
        } else {
          chomp; $prefix = sprintf("%022d ", $now) if !defined $prefix;
          push @lines, $prefix . $line; undef $prefix;
        }
      }
      \@lines
    }
    sub sortuniq($) {
      my @lines;
      my $prev = "";
      for my $line (sort @{$_[0]}) {
        die if $line !~ m@^(\d+) (.*)@s;
        my $ts = $1 + 0; my $cur = "#$ts\n$2";
        push @lines, $cur if $cur ne $prev;
        $prev = $cur;
      }
      \@lines
    }
    # Strip the prefix of double-lines from $_[0] common with $_[1];
    sub strip_common_prefix2($$) {
      my $i = 0;
      my $j;
      my $k;
      while (($j = index($_[0], "\n", $i) + 1) > 0 and
             ($k = index($_[0], "\n", $j) + 1) > 0 and
             substr($_[0], $i, $k - $i) eq substr($_[1], $i, $k - $i)) {
        $i = $k;
      }
      substr($_[0], 0, $i) = "" if $i;
      $i
    }
    my $merged_fn = $ARGV[0];
    die "$0: cannot open for a+: $merged_fn\n" if !open F, "+>>", $merged_fn;
    my $newhist = readhist(\*STDIN);
    my $newdata = join("", @{sortuniq($newhist)});
    die "$0: $merged_fn: $!\n" if !seek(F, 0, 2);
    my $size = tell(F);
    # This is outdated, it assumed that $newdata has a copy of the tail of $olddata.
    # Read 1 longer than length($newdata) for stripping at \n# below.
    # my $size_to_read = $size < length($newdata) + 1 ? $ size : length($newdata) + 1;
    my $size_to_read = $size < 4096 ? $size : 4096;
    die if $newdata !~ m@\A(#(\d+)\n[^\n]*\n)@;
    my $newhead = $1;
    my $newts = $2 + 0;
    my $need_full_rewrite = 1;
    if (defined $newts and $size_to_read > 0) {
      die "$0: $merged_fn: $!\n" if !seek(F, $size - $size_to_read, 0);
      my $olddata;
      die "$0: $merged_fn: $!\n" if
          $size_to_read != read(F, $olddata, $size_to_read);
      #print STDERR "info: AAA $size $size_to_read ($olddata)\n";
      # TODO(pts): What if regular shell commands look like #12345 timestamp?
      $olddata = "" if $size != $size_to_read and $olddata !~ s@\A.*?\n#@#@s;
      #print STDERR "info: BBB ($olddata)\n";
      if (length($olddata) > 0 and substr($olddata, -1) eq "\n") {
        my $j;
        # TODO(pts): What if regular shell commands look like #12345 timestamp?
        if (substr($olddata, 0, length($newhead)) eq $newhead) {
          strip_common_prefix2($newdata, $olddata);
        } elsif (($j = rindex($olddata, "\n$newhead") + 1) > 0) {
          strip_common_prefix2($newdata, substr($olddata, $j));
        }
        #print STDERR "info: CCC ($newdata)\n";
        if (0 == length($newdata)) {
          $need_full_rewrite = 0;
        } else {  # Now find the last entry in $olddata.
          die if $newdata !~ m@\A(#(\d+)\n[^\n]*\n)@;
          $newhead = $1;
          $newts = $2 + 0;
          $j = rindex($olddata, "\n", length($olddata) - 2);
          #print STDERR "info: DDD $newts ($newdata)\n";
          if ($j >= 0) {
            my $k = rindex($olddata, "\n", $j - 1) + 1;
            # ($k == 0) here means the beginning of $olddata, which is also fine,
            # because we have a new entry there.
            my $oldtail = substr($olddata, $k);
            #print STDERR "info: EEE $k ($oldtail)\n";
            if ($oldtail =~ m@\A#(\d+)\n[^\n]*\n@) {
              my $oldts = $1 + 0;
              if ($oldts < $newts or
                  $oldts == $newts and $oldtail lt $newhead) {
                $need_full_rewrite = 0;
              }
            }
          }
        }
      }
    }
    #print STDERR "info: $need_full_rewrite ($newdata)\n";
    #exit;
    if (!$need_full_rewrite) {  # Shortcut: Just append $newdata to F.
      $need_full_rewrite = 1;
      if (length($newdata) > 0) {
        { my $oldf = select(F); $| = 1; select($oldf) }
        die "$0: $merged_fn: $!\n" if !seek(F, 0, 2);
        if (print(F $newdata)) {
          my $new_size = tell(F);
          if ($new_size == $size + length($newdata)) {
            $need_full_rewrite = 0;
            close(F);
          }
        }
      } else {  # Nothing to append.
        $need_full_rewrite = 0;
      }
    }
    #print STDERR "info: $need_full_rewrite BX\n";
    if ($need_full_rewrite) {
      die "$0: $merged_fn: $!\n" if !seek(F, 0, 0);
      my $hist = readhist(\*F);
      push @$hist, @$newhist;
      my $tmp_fn = "$merged_fn.tmp.$$";
      unlink $tmp_fn;
      die "$0: $tmp_fn: $!\n" if !open G, ">", $tmp_fn;
      if (!print(G @{sortuniq($hist)})) {
        my $error = "$1";
        close(G);
        unlink($tmp_fn);
        die "$0: $tmp_fn: $error\n";
      } elsif (!close(G)) {
        my $error = "$1";
        unlink($tmp_fn);
        die "$0: $tmp_fn: $error\n";
      }
      my @stat = stat(F);
      close(F);
      die if !@stat;
      # This is for sudo root.
      # TODO(pts): Add better fix for sudo regular user.
      chown $stat[4], $stat[5], $tmp_fn;  # Error not checked.
      chmod $stat[2] & 07777, $tmp_fn;  # Error not checked.
      # TODO(pts): Do not lose data on concurrent merges and renames.
      die "$0: rename $tmp_fn to $merged_fn: $1" if
          !rename($tmp_fn, $merged_fn);
    }
  '  -- "$1"
}

# Move cursor to BOL and read history from $HISTFILE_MRG.
function _mrg_rdh() {
  # $COLUMNS is initialized by bash to the current number of columns of the
  # terminal just before $PROMPT_COMMAND gets executed.
  #
  # This printf is the trick (similar to what zsh does) which prints an
  # inverted % and moves the cursor to the beginning of the next line, unless
  # the cursor is already at the beginning of the line. It works even in mc.
  #
  # \e[K clears to the end of the line, and fixes copy-paste of spaces at EOL.
  printf %s%${COLUMNS}s%s '[0;7m%[0m' '' '[K'
  # test "$MC_TMPDIR" && return  # mc is fast now, no need to skip.
  _mrg_rdr
}

function _mrg_rdr() {
  # _mrg_rdr seems to be slower than _mrg_ec.

  test "$MRG_NOREAD" && return
  test "$HISTFILE_MRG" || return
  local SIZE="$(perl -e 'print -s $ARGV[0]' -- "$HISTFILE_MRG")"
  test "$MRG_LAST_SIZE" = "$SIZE" && return
  MRG_LAST_SIZE="$SIZE"
  
  local HISTFILE="$HISTFILE_MRG"
  # Make `history -w' and `history -a' add prefix "$TIMESTAMP\n" to $HISTFILE.
  local HISTTIMEFORMAT=' '
  # TODO(pts): Apply a shortcut if only one line has been appended.
  #echo AAA
  history -c  # Clear the in-memory history. TODO(pts): Reset counter.
  #echo BBB
  history -r  # Append the contents of $HISTFILE to the in-memory history.
  #echo CCC
}

export -n HISTTIMEFORMAT HISTFILE HISTFILE_MRG
shopt -u histappend
unset HISTFILE  # No history file by default, equivalent to HISTFILE="".
unset HISTTIMEFORMAT
HISTFILE_MRG="$HOME/.merged_bash_history"
history -c  # Discard the current history, whatever it was.

# Called in `trap _mrg_ec DEBUG' in `extdebug' mode, before each shell
# command to be executed.
function _mrg_ec() {
  test "$COMP_LINE" && return  # Within the completer.
  trap '' DEBUG  # Uninstall debug trap.
  test "$HISTFILE_MRG" || return

  if test "$MC_TMPDIR"; then
    # Example: COMMAND:cd "`printf "%b" '\0057var\0057cache'`"
    #echo "COMMAND:$BASH_COMMAND" >>/tmp/cmd.out
    if [[ "$BASH_COMMAND" = 'cd "`'* ]]; then
      #echo "A" >>/tmp/cmd.out
      # Return early, without touching the history file. That's to make
      # pressing <Enter> to change directories in Midight Commander fast.
      return  # Run the original $BASH_COMMAND.
    elif [[ "$BASH_COMMAND" = "PROMPT_COMMAND='pwd>"* ]]; then
      # Midnight Commander (mc) is trying to override $PROMPT_COMMAND with
      # its pwd saving and `kill -STOP $$'. We do it, but we set our hook
      # back to the beginning of $PROMPT_COMMAND.
      eval "$BASH_COMMAND"  # Set $PROMPT_COMMAND as mc wanted it.
      _mrg_install_debug_hook  # Prepend our commands to $PROPT_COMMAND.
      trap _mrg_ec DEBUG
      return 1  # Don't run the original $BASH_COMMAND.
    fi
    #echo "B" >>/tmp/cmd.out
  fi

  # TODO(pts): Why is this command run 4 times per pressing <Enter>?
  #history 1
  #history | wc -l  # SUXX: This doesn't increase above $HISTFILESIZE

  # If we don't have permission to append to the history file, then just
  # don't do anything.
  #
  # TODO(pts): Don't screw up the permission of $HISTFILE_MRG when running
  # as root.
  if : 2>/dev/null >>"$HISTFILE_MRG"; then
    # Make `history -w' and `history -a' add prefix "$TIMESTAMP\n" to $HISTFILE.
    local HISTTIMEFORMAT=' '
    # TODO(pts): Don't save if nothing changed (i.e. `history 1` prints
    # the same sequence number as before). SUXX: Prints larger and larger
    # numbers.
    local TMPDIR="${TMPDIR:-/tmp}"
    local HISTFILE="$TMPDIR/whistory.$UID.$$"
    #echo XXX
    # `history -a' writes only those lines which have been added since the
    # last `history -r'. Cool, that's exactly what we want, because we want
    # to write only commands typed to this shell. Usually this `history -a'
    # writes a single entry (2 lines) only, because there was a recent
    # `history -r' in _mrg_rdh.
    #
    # `history -a' doesn't even create the file if it doesn't want to write
    # any entries.
    #echo XXX
    history -a
    #echo YYY
    if test -f "$HISTFILE"; then
      #time command wc -l -- "$HISTFILE"
      #echo YYY
      #cp "$HISTFILE_MRG" /tmp/m
      #cp "$HISTFILE" /tmp/new
      #ls -l "$HISTFILE_MRG" "$HISTFILE"
      #time _mrg_merge_ts_history "$HISTFILE_MRG" <"$HISTFILE"
      _mrg_merge_ts_history "$HISTFILE_MRG" <"$HISTFILE"
      # TODO(pts): try other, Linux-specific options (for speed):
      # stat -c %s "$HISTFILE_MRG"
      # du -b "$HISTFILE_MRG"
      # #wc -c "$HISTFILE_MRG"  # Don't try, it reads the file.
      # TODO(pts): Fix elsewhere.
      MRG_LAST_SIZE="$(perl -e 'print -s $ARGV[0]' -- "$HISTFILE_MRG")"
      #echo ZZZ
      command rm -f -- "$HISTFILE"
    fi
  fi
}

function _mrg_install_debug_hook() {
  # Remove previous hook installed by _mrg_install_debug_hook .
  #
  # TODO(pts): Remove old versions more smartly, by detecting delimiters.
  PROMPT_COMMAND="${PROMPT_COMMAND#trap \'\' DEBUG; _mrg_rdh; }"
  PROMPT_COMMAND="${PROMPT_COMMAND%
trap _mrg_ec DEBUG}"

  # We want to run `trap _mrg_ec DEBUG' in $PROMPT_COMMAND as late as
  # possible so that the debug hook (_mrg_ec) won't be executed on the rest
  # of $PROMPT_COMMAND, but it will be executed at the user command.
  PROMPT_COMMAND="trap '' DEBUG; _mrg_rdh; $PROMPT_COMMAND
trap _mrg_ec DEBUG"
}

# Set these both so hook_at_debug gets called in a subshell.
set -o functrace > /dev/null 2>&1
shopt -s extdebug > /dev/null 2>&1

MRG_LAST_SIZE=

# As a side effect, we install our own debug hook. We wouldn't have to do
# that if bash had support for zsh's `preexec' hook, which is executed just
# after a command has been read and is about to be executed).
_mrg_install_debug_hook

# It's too early to do this, lines starting with # would be also loaded.
#test "$MC_TMPDIR" && _mrg_rdr

fi  # End of the file's if guard.
unset MRG_DONEI
