#!/bin/sh

find_elf() {
        find "$(ruby -e 'puts Gem.default_dir')" -type f -not \( -name '*.o' \) |
        xargs -n1 -P$(nproc) sh $0 scan | tr ',' '\n' | sort -u |
        awk '{ print "so:" $1 }'
}

scan() {
        case "$(head -c 4 "$1" 2>/dev/null)" in
                ?ELF*) scanelf --needed --nobanner --format '%n#p' "$1" ;;
        esac
}

case $1 in
        scan) scan $2 ;;
        *) find_elf ;;
esac
