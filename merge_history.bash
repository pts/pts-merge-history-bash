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

# Merge the timestamped .bash_history files specified in $@ , remove
# duplicates (where both timestamp and command name are exactly the same),
# print the results to stdout.
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
function _mrg_rdh() {
  test "$HISTFILE_MRG" || return
  local HISTFILE="$HISTFILE_MRG"
  # Make `history -w' prefix "$TIMESTAMP\n" to $HISTFILE
  local HISTTIMEFORMAT=' '
  # TODO(pts): Apply a shortcut if only one line has been appended.
  history -c  # Clear the in-memory history. TODO(pts): Reset counter.
  history -r  # Append the contents of $HISTFILE to the in-memory history.
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

  if [[ "$BASH_COMMAND" = "PROMPT_COMMAND='pwd>"* ]] && test "$MC_TMPDIR"; then
    # Midnight Commander (mc) is trying to override $PROMPT_COMMAND with its
    # pwd saving and `kill -STOP $$'. We do it,
    eval "$BASH_COMMAND"  # Set $PROMPT_COMMAND as mc wanted it.
    _mrg_install_debug_hook  # Prepend our commands to $PROPT_COMMAND.
    trap _mrg_ec DEBUG
    return 1  # Don't run the original $BASH_COMMAND.
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
    # Make `history -w' prefix "$TIMESTAMP\n" to $HISTFILE
    local HISTTIMEFORMAT=' '
    # TODO(pts): Don't save if nothing changed (i.e. `history 1` prints
    # the same sequence number as before). SUXX: Prints larger and larger
    # numbers.
    local TMPDIR="${TMPDIR:-/tmp}"
    local HISTFILE="$TMPDIR/whistory.$UID.$$"
    local MHISTFILE="$TMPDIR/mhistory.$UID.$$"
    history -w  # Write to the temporary $HISTFILE .
    _mrg_merge_ts_history "$HISTFILE_MRG" "$HISTFILE" >"$MHISTFILE"
    command mv -f -- "$MHISTFILE" "$HISTFILE_MRG"
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

# As a side effect, we install our own debug hook. We wouldn't have to do
# that if bash had support for zsh's `preexec' hook, which is executed just
# after a command has been read and is about to be executed).
_mrg_install_debug_hook

fi  # End of the file's if guard.
unset MRG_DONEI
