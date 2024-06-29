#!/bin/sh

if ! command -v iverilog >/dev/null 2>&1; then
    echo "You should install iverilog"
    exit 1
fi


if command -v rg >/dev/null 2>&1; then
    GREP="rg"
else
    GREP="grep"
fi

clean() {
    rm -f ./a.out
}

compile() {
    if ! iverilog -g2005-sv riscv.sv; then
        exit 1
    fi
}

run_single_test() {
    _run_single_test__path="$1"
    if [ -n "$_run_single_test__path" ]; then
        python3 ./encode.py "$_run_single_test__path" memory_contents.hex
        echo Testing - "$_run_single_test__path"
        if [ ! -f ./a.out ]; then
            compile
        fi
        ./a.out
    else
        echo Missing file argument, maybe you meant: "$0" test
    fi
    unset _run_single_test__path
}

run_test() {
    _run_test__path="$1"
    python3 ./encode.py "$_run_test__path" memory_contents.hex
    echo Testing - "$_run_test__path"
    if [ ! -f ./a.out ]; then
        compile
    fi
    ./a.out | $GREP -i test
    unset _run_test__path
}


run_tests() {
    for f in $(/bin/ls examples); do
        run_test "examples/$f"
    done
}


case "$1" in
    clean)
        clean
        ;;
    compile)
        compile
        ;;
    test)
        run_tests
        ;;
    run)
        run_single_test "$2"
        ;;
    *)
        echo "Usage $0 [compile/test/run]"
        ;;
esac
