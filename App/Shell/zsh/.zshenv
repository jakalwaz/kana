# Kana zsh bootstrap.
#
# Kana starts zsh through libghostty's shell integration. Ghostty sets
# ZDOTDIR to its own folder; Kana sets GHOSTTY_ZSH_ZDOTDIR (where Ghostty's
# .zshenv hands over next) to this folder, and passes the user's own ZDOTDIR,
# if they had one, in KANA_ZSH_ZDOTDIR. So the chain is:
#
#   ghostty .zshenv -> this file -> the user's .zshenv
#   (then ghostty .zshenv loads its integration: prompt marks, cwd reporting)
#
# We put ZDOTDIR back straight away so .zprofile, .zshrc and .zlogin all come
# from the user's folder, then load kana.zsh from the first precmd, after
# .zshrc, so our key bindings win over the defaults the user's config set.

typeset -g KANA_ZSH_DIR="${${(%):-%x}:A:h}"

if [[ -n "${KANA_ZSH_ZDOTDIR+set}" ]]; then
    ZDOTDIR="$KANA_ZSH_ZDOTDIR"
    unset KANA_ZSH_ZDOTDIR
else
    unset ZDOTDIR
fi

if [[ -r "${ZDOTDIR:-$HOME}/.zshenv" ]]; then
    builtin source -- "${ZDOTDIR:-$HOME}/.zshenv"
fi

if [[ -o interactive ]]; then
    _kana_deferred_init() {
        builtin unfunction _kana_deferred_init
        precmd_functions=(${precmd_functions:#_kana_deferred_init})
        # tells kana.zsh the first prompt is already being drawn
        typeset -g _kana_late=1
        [[ -r "$KANA_ZSH_DIR/kana.zsh" ]] && builtin source -- "$KANA_ZSH_DIR/kana.zsh"
    }
    typeset -ga precmd_functions
    precmd_functions+=(_kana_deferred_init)
fi
