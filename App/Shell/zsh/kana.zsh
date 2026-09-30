# Kana's zsh layer: inline suggestions, a default prompt, the tab title and
# the welcome screen.
#
# Suggestions
#   As you type, the rest of a likely command shows in grey after the cursor.
#   Tab (or → / End / Ctrl-E at the end of the line) accepts it. Alt-→
#   accepts one word. With no suggestion showing, Tab completes as usual.
#   Ctrl-Alt-Space toggles suggestions on and off.
#
#   Where suggestions come from, first match wins:
#     1. history: the newest command that starts with what you typed
#     2. the first word: commands, aliases, functions and builtins
#     3. later words: files and folders (folders only after cd)
#
# Prompt
#   Only replaces the macOS default prompt. A custom PS1, or KANA_PROMPT=0,
#   is left alone.
#
# Welcome screen
#   `kana banner` before the first prompt of a new tab (KANA_BANNER from the
#   app). Type `kana` to show it again, `kana keys` for just the keys.
#
# Settings (environment): KANA_SUGGEST=0 turns suggestions off,
# KANA_SUGGEST_STYLE sets the highlight (default fg=8), KANA_ACCENT is the
# skin's accent colour, set by the app.

[[ -o interactive ]] || return 0
(( ${+_kana_loaded} )) && return 0
typeset -g _kana_loaded=1

zmodload zsh/parameter 2>/dev/null
builtin autoload -Uz add-zle-hook-widget add-zsh-hook

# ---------------------------------------------------------------- history

# Kana can only suggest what zsh remembers. Raise the macOS defaults
# (HISTSIZE 2000, SAVEHIST 1000) and write each command as it runs, so every
# tab sees the others' history. Bigger values from the user win.
(( ${HISTSIZE:-0} < 50000 )) && HISTSIZE=50000
(( ${SAVEHIST:-0} < 50000 )) && SAVEHIST=50000
[[ -n "$HISTFILE" ]] || HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
setopt inc_append_history hist_ignore_dups hist_reduce_blanks

# ---------------------------------------------------------------- suggestions

typeset -g KANA_SUGGEST_STYLE="${KANA_SUGGEST_STYLE:-fg=8}"
typeset -gi _kana_suggest_on=1
[[ "${KANA_SUGGEST:-1}" == (0|off|false|no) ]] && _kana_suggest_on=0

# Sets REPLY to the full suggested line (always longer than, and starting
# with, $1), or to empty.
_kana_suggest_for() {
    emulate -L zsh
    setopt extended_glob null_glob
    local buffer="$1"
    REPLY=
    [[ -z "$buffer" || "$buffer" == *$'\n'* ]] && return

    # 1. history, newest first ($history is keyed by event number and the
    #    (r) subscript searches from the newest entry)
    local hit="${history[(r)${(b)buffer}?*]}"
    if [[ -n "$hit" && "$hit" != *$'\n'* ]]; then
        REPLY="$hit"
        return
    fi

    local -a words=(${(z)buffer})
    local word="${words[-1]}"
    [[ "$buffer" == *[[:space:]] ]] && return

    # 2. first word: the shortest command that fits, so "gi" gives "git"
    if (( ${#words} == 1 )); then
        local -a names=(
            ${(M)${(k)commands}:#${(b)word}?*}
            ${(M)${(k)aliases}:#${(b)word}?*}
            ${(M)${(k)builtins}:#${(b)word}?*}
            ${${(M)${(k)functions}:#${(b)word}?*}:#_*}
        )
        (( ${#names} )) || return
        names=(${(u)names})
        local best="${names[1]}" name
        for name in $names; do
            if (( ${#name} < ${#best} )) || { (( ${#name} == ${#best} )) && [[ "$name" < "$best" ]] }; then
                best="$name"
            fi
        done
        REPLY="$best"
        return
    fi

    # 3. later words: files, or folders for cd-like commands
    [[ "$word" == *[\\\'\"\$\`\*\?\[]* ]] && return
    local pattern="$word"
    [[ "$pattern" == "~"* ]] && pattern="$HOME${pattern#\~}"
    local -a found
    case "${words[1]}" in
        (cd|pushd|rmdir|z) found=(${~${(b)pattern}}*(N-/)) ;;
        (*) found=(${~${(b)pattern}}*(N)) ;;
    esac
    (( ${#found} )) || return
    local rest="${found[1]:${#pattern}}"
    [[ -d "${found[1]}" ]] && rest+="/"
    [[ -n "$rest" ]] && REPLY="$buffer${rest// /\\ }"
}

_kana_suggest_clear() {
    POSTDISPLAY=
    region_highlight=(${region_highlight:#*memo=kana-suggest})
}

_kana_suggest_show() {
    _kana_suggest_clear
    (( _kana_suggest_on )) || return
    # only at the end of the line, and not while completing or searching
    (( CURSOR == ${#BUFFER} )) || return
    [[ -z "$PREDISPLAY" && "$KEYMAP" != (vicmd|isearch) ]] || return
    _kana_suggest_for "$BUFFER"
    [[ -n "$REPLY" ]] || return
    POSTDISPLAY="${REPLY:${#BUFFER}}"
    region_highlight+=("${#BUFFER} $(( ${#BUFFER} + ${#POSTDISPLAY} )) $KANA_SUGGEST_STYLE memo=kana-suggest")
}

# Recompute before every redraw, but only when the line changed.
typeset -g _kana_last_buffer=$'\0'
_kana_on_redraw() {
    [[ "$BUFFER" == "$_kana_last_buffer" && $CURSOR -eq ${#BUFFER} ]] && return
    _kana_last_buffer="$BUFFER"
    _kana_suggest_show
}

_kana_on_line_init() {
    _kana_last_buffer=$'\0'
}

# Leave no grey text behind in the scrollback once a line runs.
_kana_on_line_finish() {
    _kana_suggest_clear
    zle -R 2>/dev/null
}

_kana_accept() {
    [[ -n "$POSTDISPLAY" ]] || return 1
    BUFFER+="$POSTDISPLAY"
    CURSOR=${#BUFFER}
    _kana_suggest_clear
    _kana_last_buffer="$BUFFER"
    return 0
}

# What Tab did before we took it over (expand-or-complete by default, or
# whatever the user's config bound, like fzf-completion).
typeset -g _kana_tab_widget="${${(s: :)$(bindkey '^I')}[2]:-expand-or-complete}"
[[ "$_kana_tab_widget" == _kana_tab ]] && _kana_tab_widget=expand-or-complete

_kana_tab() {
    _kana_accept || { _kana_suggest_clear; zle "$_kana_tab_widget" }
}

_kana_forward_char() {
    (( CURSOR == ${#BUFFER} )) && _kana_accept || zle .forward-char
}

_kana_end_of_line() {
    (( CURSOR == ${#BUFFER} )) && _kana_accept || zle .end-of-line
}

_kana_forward_word() {
    setopt localoptions extended_glob
    if (( CURSOR == ${#BUFFER} )) && [[ -n "$POSTDISPLAY" ]]; then
        # take up to and including the next word of the suggestion
        local rest="$POSTDISPLAY"
        local take="${(M)rest##[[:space:]]#[^[:space:]]##}"
        [[ -n "$take" ]] || take="$rest"
        BUFFER+="$take"
        CURSOR=${#BUFFER}
        _kana_suggest_show
        _kana_last_buffer="$BUFFER"
    else
        zle .forward-word
    fi
}

_kana_suggest_toggle() {
    (( _kana_suggest_on = !_kana_suggest_on ))
    _kana_suggest_show
    zle -M "Kana suggestions ${${_kana_suggest_on/1/on}/0/off}"
}

# zsh-autosuggestions already does this job; don't fight it.
if (( ! ${+functions[_zsh_autosuggest_start]} )); then
    zle -N _kana_tab
    zle -N _kana_forward_char
    zle -N _kana_end_of_line
    zle -N _kana_forward_word
    zle -N _kana_suggest_toggle
    add-zle-hook-widget line-pre-redraw _kana_on_redraw
    add-zle-hook-widget line-init _kana_on_line_init
    add-zle-hook-widget line-finish _kana_on_line_finish

    for _kana_map in emacs viins; do
        bindkey -M $_kana_map '^I' _kana_tab
        bindkey -M $_kana_map '^[[C' _kana_forward_char
        bindkey -M $_kana_map '^[OC' _kana_forward_char
        bindkey -M $_kana_map '^E' _kana_end_of_line
        bindkey -M $_kana_map '^[[F' _kana_end_of_line
        bindkey -M $_kana_map '^[OF' _kana_end_of_line
        bindkey -M $_kana_map '^[[1;3C' _kana_forward_word
        bindkey -M $_kana_map '^[f' _kana_forward_word
        bindkey -M $_kana_map '^[^@' _kana_suggest_toggle
    done
    unset _kana_map
fi

# ---------------------------------------------------------------- tab title

# The folder at a prompt, the command while it runs. Kana's tabs show it.
if [[ -n "$KANA" ]]; then
    _kana_title_precmd() { builtin print -Pn -- '\e]2;%~\a' }
    _kana_title_preexec() {
        local cmd="${${1//[[:cntrl:]]/ }[1,60]}"
        builtin print -rn -- $'\e]2;'"$cmd"$'\a'
    }
    add-zsh-hook precmd _kana_title_precmd
    add-zsh-hook preexec _kana_title_preexec
    _kana_title_precmd
fi

# ---------------------------------------------------------------- prompt

_kana_default_prompt() {
    [[ "${KANA_PROMPT:-1}" != (0|off|false|no) ]] || return 1
    # macOS /etc/zshrc default, or zsh's own
    [[ "$PS1" == '%n@%m %1~ %# ' || "$PS1" == '%m%# ' || "$PS1" == '%n@%m %~ %# ' ]]
}

if _kana_default_prompt; then
    builtin autoload -Uz vcs_info
    zstyle ':vcs_info:*' enable git
    zstyle ':vcs_info:git:*' formats ' %F{8}on%f %F{white}%b%f'
    zstyle ':vcs_info:git:*' actionformats ' %F{8}on%f %F{white}%b%f %F{yellow}%a%f'
    add-zsh-hook precmd vcs_info
    setopt prompt_subst
    typeset -g _kana_accent="${KANA_ACCENT:-#e0262f}"
    # ~/path on branch
    # ❯            (accent, yellow after a failed command, with the code on the right)
    PS1='%B%F{white}%~%f%b${vcs_info_msg_0_}'$'\n''%(1V.%F{yellow}.%F{'"$_kana_accent"'})❯%f '
    RPS1='%(1V.%F{8}%1v%f.)'
    vcs_info 2>/dev/null
    # Runs first in precmd so it sees the last command's exit code. The very
    # first prompt always looks clean, whatever the startup files returned.
    # Also puts a blank line between a command's output and the next prompt.
    typeset -gi _kana_prompts=${_kana_late:-0}
    _kana_prompt_status() {
        local code=$?
        if (( _kana_prompts++ )); then
            print
            psvar[1]=${${code:#0}:-}
        else
            psvar[1]=
        fi
    }
    precmd_functions=(_kana_prompt_status ${precmd_functions:#_kana_prompt_status})
fi
unfunction _kana_default_prompt

# ---------------------------------------------------------------- welcome screen

# `kana` lives in Kana.app. The app says whether this tab plays the welcome
# animation (the first tab), shows it still (later tabs), or skips it.
if [[ -n "$KANA_BIN_DIR" && -x "$KANA_BIN_DIR/kana" ]]; then
    (( ${path[(Ie)$KANA_BIN_DIR]} )) || path+=("$KANA_BIN_DIR")
    case "${KANA_BANNER:-off}" in
        (animate) command kana banner --new-tab ;;
        (still) command kana banner --still --new-tab ;;
    esac
fi
# shells started from this one don't show it again
unset KANA_BANNER
