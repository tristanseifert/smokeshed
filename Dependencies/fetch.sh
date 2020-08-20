#!/bin/sh

# fetch git modules

# libraw
cd libraw
cp Makefile.dist Makefile
make
cd ..

# lensfun
cd lensfun
mkdir build
cd build
cmake .. -DBUILD_STATIC=ON
make
cd ..
