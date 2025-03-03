# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg
using Base.BinaryPlatforms

include("../../fancy_toys.jl")

name = "libclangex"
version = v"0.1.3"

# Collection of sources required to complete build
sources = [
    GitSource("https://github.com/Gnimuc/libclangex.git", "c27bb2040d9e2cff4eee9e4abaaa1f5dbb30dd24")
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir
cd libclangex/
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
     -DLLVM_DIR=$prefix \
     -DCLANG_DIR=$prefix \
     -DLLVM_ASSERT_BUILD=false \
     -DCMAKE_BUILD_TYPE=Release \
     -DCMAKE_EXPORT_COMPILE_COMMANDS=true
make -j${nproc}
make install
install_license ../COPYRIGHT ../LICENSE-APACHE ../LICENSE-MIT
"""

function configure(julia_version, llvm_version)
    # These are the platforms we will build for by default, unless further
    # platforms are passed in on the command line
    platforms = expand_cxxstring_abis(supported_platforms(; experimental=true))

    foreach(platforms) do p
        BinaryPlatforms.add_tag!(p.tags, "julia_version", string(julia_version))
    end

    # The products that we will ensure are always built
    products = Product[
        # Life is horrible and we can't add Clang_jll as a dependency, thus
        # loading the library will always fail. We can fix this in the consumer
        # so don't dlopen
        LibraryProduct("libclangex", :libclangex, dont_dlopen=true),
    ]
    # ver = "$(llvm_version.major).$(llvm_version.minor).$(llvm_version.patch)"
    dependencies = [
        BuildDependency(get_addable_spec("LLVM_full_jll", llvm_version))
        # Dependency("LLVM_full_jll", llvm_version, compat=ver),
        # ^ is given through julia_version tag
    ]

    return platforms, products, dependencies
end

# TODO: Don't require build-id on LLVM version
supported = (
    # (v"1.6", v"11.0.1+3"),
    (v"1.7", v"12.0.1+0"),
    (v"1.8", v"12.0.1+0"),
)

for (julia_version, llvm_version) in supported
    platforms, products, dependencies = configure(julia_version, llvm_version)

    any(should_build_platform.(triplet.(platforms))) || continue

    # Build the tarballs.
    build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
                   preferred_gcc_version=v"8", julia_compat="1.7")
end
