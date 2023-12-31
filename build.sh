#!/usr/bin/env bash

SRC=$(dirname $0)

BUILD="$(pwd)/build"
LLVM_SRC=$(pwd)/upstream/llvm-project

SRC=$(realpath "$SRC")

LLVM_BUILD=$BUILD/llvm
LLVM_NATIVE=$BUILD/llvm-native

# If we don't have a copy of LLVM, make one
if [ ! -d $LLVM_SRC/ ]; then
    git clone https://github.com/llvm/llvm-project.git "$LLVM_SRC/" --depth=1
    pushd $LLVM_SRC/

    # latest commit of llvm-project
    git reset --hard 4b3dbaaa32420ab2cb66981b03122e2e4804f7eb

    # The clang driver will sometimes spawn a new process to avoid memory leaks.
    # Since this complicates matters quite a lot for us, just disable that.
    git apply $SRC/upstream/patches/llvm-project.patch

    popd
fi

# Cross compiling llvm needs a native build of "llvm-tblgen" and "clang-tblgen"
if [ ! -d $LLVM_NATIVE/ ]; then
    cmake -G Ninja \
        -S $LLVM_SRC/llvm/ \
        -B $LLVM_NATIVE/ \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_TARGETS_TO_BUILD=WebAssembly \
        -DLLVM_ENABLE_PROJECTS="clang"
fi
cmake --build $LLVM_NATIVE/ -- llvm-tblgen clang-tblgen

if [ ! -d $LLVM_BUILD/ ]; then
    CXXFLAGS="-Dwait4=__syscall_wait4" \
    LDFLAGS="\
        -s LLD_REPORT_UNDEFINED=1 \
        -s ALLOW_MEMORY_GROWTH=1 \
        -s EXPORTED_FUNCTIONS=_main,_free,_malloc \
        -s EXPORTED_RUNTIME_METHODS=FS,PROXYFS,ERRNO_CODES,allocateUTF8 \
        -lproxyfs.js \
        --js-library=$SRC/upstream/emlib/fsroot.js \
    " emcmake cmake -G Ninja \
        -S $LLVM_SRC/llvm/ \
        -B $LLVM_BUILD/ \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_TARGETS_TO_BUILD=WebAssembly \
        -DLLVM_ENABLE_PROJECTS="clang" \
        -DLLVM_ENABLE_DUMP=OFF \
        -DLLVM_ENABLE_ASSERTIONS=OFF \
        -DLLVM_ENABLE_EXPENSIVE_CHECKS=OFF \
        -DLLVM_ENABLE_BACKTRACES=OFF \
        -DLLVM_BUILD_TOOLS=OFF \
        -DLLVM_ENABLE_THREADS=OFF \
        -DLLVM_BUILD_LLVM_DYLIB=OFF \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_TABLEGEN=$LLVM_NATIVE/bin/llvm-tblgen \
        -DCLANG_TABLEGEN=$LLVM_NATIVE/bin/clang-tblgen

    # Make sure we build js modules (.mjs).
    sed -i -E 's/\.js/.mjs/g' $LLVM_BUILD/build.ninja

    # The mjs patching is over zealous, and patches some source JS files rather than just output files.
    # Undo that.
    sed -i -E 's/(pre|post|proxyfs|fsroot)\.mjs/\1.js/g' $LLVM_BUILD/build.ninja
fi
cmake --build $LLVM_BUILD/ -- clang
