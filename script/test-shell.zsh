#!/bin/zsh
# End-to-end tests for Kana's zsh layer (App/Shell/zsh). Each test starts a
# real interactive zsh in a pseudo-terminal with a throwaway HOME, types
# keys, and checks what the shell printed.
#
# Usage: zsh script/test-shell.zsh [path/to/App/Shell/zsh]

zmodload zsh/zpty || { print "zsh/zpty missing"; exit 1 }
setopt extended_glob

K=${1:-${0:A:h:h}/App/Shell/zsh}
K=${K:A}
TMP=$(mktemp -d -t kana-shell-test)
trap 'rm -rf $TMP' EXIT
integer pass=0 fail=0

# check NAME KEYS REGEX [raw]: fresh shell, type KEYS, expect REGEX in the
# output (escape codes stripped, unless "raw")
check() {
    local home=$TMP/home
    rm -rf $home; mkdir -p "$home/some folder" $home/projects
    print ': 1700000000:0;echo kana-history-test-123' > $home/.zsh_history
    touch $home/projects/readme-unique.md
    cd $home
    zpty t env -i KANA=1 HOME=$home TERM=xterm-256color PATH=/usr/bin:/bin ZDOTDIR=$K /bin/zsh -i
    sleep 1.2
    zpty -r -t t _junk
    zpty -w -n t "$2"
    sleep 2
    local out= chunk
    for i in {1..20}; do
        if zpty -r -t t chunk 2>/dev/null; then out+=$chunk; else sleep 0.1; fi
    done
    zpty -d t
    local plain=${out//$'\e'\[[0-9;?]#[A-Za-z]/}
    local esc=$'\e' bel=$'\a'
    plain=${plain//${esc}\][^${bel}]#${bel}/}   # OSC, like the tab title
    [[ "$4" == raw ]] && plain=$out
    if [[ $plain =~ $3 ]]; then
        print "  ok    $1"; (( pass++ ))
    else
        print "  FAIL  $1"; print -r -- "$plain" | cat -v | tail -4 | sed 's/^/        /'; (( fail++ ))
    fi
}

check "history suggestion, Tab accepts"   $'echo kana-h\t\r'       $'\nkana-history-test-123'
check "command name suggestion"           $'whoam\t\r'             $'\n'"$(whoami)"
check "file suggestion"                   $'ls projects/read\t\r'  $'\nprojects/readme-unique.md'
check "folder with a space, after cd"     $'cd some\t\rpwd\r'      'some folder'
check "right arrow accepts"               $'echo kana-h\e[C\r'     $'\nkana-history-test-123'
check "alt-right accepts one word"        $'ech\e[1;3C MARK\r'     $'\nMARK'
check "Tab completes when nothing shows"  $'ls projects/*\t\r'     $'\nprojects/readme-unique.md'
check "no grey text left after running"   $'echo kana-h\r'         $'\nkana-h\r'
check "suggestion is drawn in grey"       $'echo kana-h'           $'\e\\[90m[^\e]*history-test-123' raw
check "first prompt isn't marked failed"  ''                       '❯'

print "  $pass passed, $fail failed"
(( fail == 0 ))
