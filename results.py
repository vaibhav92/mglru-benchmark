#!/bin/python3

import os
import sys
import re
import datetime
from pathlib import Path

def slurp(path):
    if not (path.exists() and path.is_file()):
        return ''
    with path.open() as f:
        return f.read().strip()

def generate_result(path):
    timestamp_final=slurp(path.joinpath('timestamp.final'))
    if timestamp_final == '':
        sys.stderr.write(f'Incomplete run {path}')
        return
    timestamp_initial = slurp(path.joinpath('timestamp.intial'))
    boot_kernel=slurp(path.joinpath('boot.kernel'))
    mglru_regexp = re.compile('.*non-mglru.*')
    is_mglru = not mglru_regexp.match(boot_kernel)

    #ycsb_log = slurp(path.joinpath('ycsb.log'))
    throuput_regexp = re.compile('^\[OVERALL\], Throughput\(ops/sec\), ([0-9.]*)$', re.MULTILINE)
    match=throuput_regexp.search(slurp(path.joinpath('ycsb.log')))
    if match is None:
        sys.stderr.write('Unable to find throughput match\n')
        return
    throuput=match.groups()[0]
    distribution=slurp(path.joinpath('distribution'))
    print(f'{path.name},{is_mglru},{distribution},{throuput}')


def main():
    if len(sys.argv) < 1:
        sys.stderr.write(f'Expect results dir path as argument')
        return

    for path in sys.argv[1:]:
        p = Path(sys.argv[1])
        if not p.is_dir():
            sys.stderr.write(f'{sys.argv[1]} is not a results dir')
            return
        testdirs = [ x for x in p.iterdir() if x.is_dir()]
        print('RUN,IS-MGLRU,Distribution,Throughput')
        for dir in testdirs:
            generate_result(Path(dir))

if __name__ == '__main__':
    sys.exit(main()) 
