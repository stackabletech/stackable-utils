#!/usr/bin/env fish

rm --recursive vex_wo_fixed
mkdir vex_wo_fixed

for document in vex/*
    cat $document \
        | jq 'del(.statements.[] | select(.status == "fixed"))' \
        > vex_wo_fixed/(basename $document)
end
