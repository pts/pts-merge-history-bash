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

MRG_DONEI=":$SHELLOPTS:"
if test "${MRG_DONEI#*:history:}" != "$PTS_DONEI" &&
   (test "${BASH_VERSION#[5-9].}" != "$BASH_VERSION" ||
    test "${BASH_VERSION#4.[1-9].}" != "$BASH_VERSION") &&
   test "$HOME" &&
   test -f "$HOME/.merged_bash_history"; then

# Merge the timestamped .bash_history files specified in $@ , remove
# duplicates, print the results to stdout.
function _mrg_merge_ts_history() {
  PERL_BADLANG=x perl -wne '
    use integer;
    use strict;
    use vars qw($prefix @lines);
    if (/^#(\d+)\n/) {
      $prefix = sprintf("%030d ", $1);
    } else {
      chomp; $prefix = sprintf("%030d ", time) if !defined $prefix;
      push @lines, "$prefix$_\n"; undef $prefix;
    }
    END {
      my $prev = "";
      for (sort @lines) {
        s@^(\d+) @@; my $ts = $1 + 0; my $cur = "#$ts\n$_";
        print $cur if $cur ne $prev;
        $prev = $cur;
      }
    }
  ' -- "$@"
}

# Read history from $HISTFILE_MRG, 
function _rdh() {
  test "$HISTFILE_MRG" || return
  local HISTFILE="$HISTFILE_MRG"
  # Make `history -w' prefix "$TIMESTAMP\n" to $HISTFILE
  local HISTTIMEFORMAT=' '
  history -c  # Clear the in-memory history.
  history -r  # Append the contents of $HISTFILE to the in-memory history.
}

INSTALL_DEBUG_TRAP=
#INSTALL_DEBUG_TRAP='trap hook_at_debug DEBUG'
export -n HISTTIMEFORMAT HISTFILE HISTFILE_MRG
unset HISTFILE  # No history file by default, equivalent to HISTFILE="".
unset HISTTIMEFORMAT
HISTFILE_MRG="$HOME/.merged_bash_history"
history -c  # Discard the current history, whatever it was.

function hook_at_debug() {
  test "$COMP_LINE" && return  # Within the completer.
  trap '' DEBUG  # Uninstall debug trap.
  test "$HISTFILE_MRG" || return
  if : >>"$HISTFILE_MRG"; then
    # Make `history -w' prefix "$TIMESTAMP\n" to $HISTFILE
    local HISTTIMEFORMAT=' '
    # TODO(pts): Don't save if nothing changed (i.e. `history -1` prints
    # the same sequence number as before).
    local TMPDIR="${TMPDIR:-/tmp}"
    local HISTFILE="$TMPDIR/whistory.$UID.$$"
    local MHISTFILE="$TMPDIR/mhistory.$UID.$$"
    history -w  # Write to /tmp/whistory.$$ .
    _mrg_merge_ts_history "$HISTFILE_MRG" "$HISTFILE" >"$MHISTFILE"
    command mv -f -- "$MHISTFILE" "$HISTFILE_MRG"
  fi
}

# Set these both so hook_at_debug gets called in a subshell.
set -o functrace > /dev/null 2>&1
shopt -s extdebug > /dev/null 2>&1

# As a side effect, we install our own debug hook. We wouldn't have to do
# that if bash had support for `preexec' (executed just after a command has
# been read and is about to be executed). in zsh.
PROMPT_COMMAND="trap '' DEBUG; _rdh; trap hook_at_debug DEBUG; $PROMPT_COMMAND"

fi  # End of the file's if guard.
unset MRG_DONEI
