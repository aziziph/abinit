#!/bin/bash -x
(cd ../../../../tmp/; make mj4)
mpirun -n 2 time abinit < t03_x.files > log 2> err

