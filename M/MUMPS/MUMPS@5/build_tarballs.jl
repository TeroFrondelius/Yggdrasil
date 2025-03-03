using BinaryBuilder

name = "MUMPS"
version = v"5.4.1"

sources = [
  ArchiveSource("http://mumps.enseeiht.fr/MUMPS_$version.tar.gz",
                "93034a1a9fe0876307136dcde7e98e9086e199de76f1c47da822e7d4de987fa8"),
  DirectorySource("./bundled"),
]

# Bash recipe for building across all platforms
script = raw"""
mkdir -p ${libdir}
cd $WORKSPACE/srcdir/MUMPS*
atomic_patch -p1 ${WORKSPACE}/srcdir/patches/mumps_int64.patch

OPENBLAS=(-lopenblas)
FFLAGS=()
CFLAGS=()
if [[ ${nbits} == 64 ]] && [[ ${target} != aarch64* ]]; then
  FFLAGS+=(-ffixed-line-length-none)  # replacing symbols below sometimes makes lines > 72 chars
  OPENBLAS=(-lopenblas64_)
  if [[ "${target}" == powerpc64le-linux-gnu ]]; then
    OPENBLAS+=(-lgomp)
  fi

  syms=(DGEMM IDAMAX ISAMAX SNRM2 XERBLA caxpy ccopy cgemm cgemv cgeru cher clarfg cscal cswap ctrsm ctrsv cungqr cunmqr daxpy dcopy dgemm dgemv dger dlamch dlarfg dorgqr dormqr dnrm2 dscal dswap dtrsm dtrsv dznrm2 idamax isamax ilaenv scnrm2 saxpy scopy sgemm sgemv sger slamch slarfg sorgqr sormqr snrm2 sscal sswap strsm strsv xerbla zaxpy zcopy zgemm zgemv zgeru zlarfg zscal zswap ztrsm ztrsv zungqr zunmqr)
  for sym in ${syms[@]}
  do
    FFLAGS+=("-D${sym}=${sym}_64")
    CFLAGS+=("-D${sym}=${sym}_64")
  done
fi

makefile="Makefile.G95.PAR"
cp Make.inc/${makefile} Makefile.inc

make_args+=(OPTF=-O
            CDEFS=-DAdd_
            LMETISDIR=${libdir}
            IMETIS=-I${prefix}/include
            LMETIS='-L$(LMETISDIR) -lparmetis -lmetis'
            ORDERINGSF="-Dpord -Dparmetis"
            CC="mpicc -fPIC"
            FC="mpif90 -fPIC ${FFLAGS[@]}"
            FL="mpif90 -fPIC ${CFLAGS[@]}"
            SCALAP=-lscalapack
            INCPAR=  # Let MPI compilers fill in the blanks
            LIBPAR=-lscalapack
            LIBBLAS=${OPENBLAS})

if [[ "${target}" == *-apple* ]]; then
  make_args+=(RANLIB=echo)
fi

# NB: parallel build fails
make all "${make_args[@]}"

# build shared libs
all_load="--whole-archive"
noall_load="--no-whole-archive"
extra=""
if [[ "${target}" == *-apple-* ]]; then
    all_load="-all_load"
    noall_load="-noall_load"
    extra="-Wl,-undefined -Wl,dynamic_lookup -headerpad_max_install_names"
fi

cd lib
libs=(-lparmetis -lmetis -lscalapack ${OPENBLAS})
mpif90 -fPIC -shared -Wl,${all_load} libpord.a ${libs[@]} -Wl,${noall_load} ${extra[@]} -o libpord.${dlext}
cp libpord.${dlext} ${libdir}

libs+=(-L${libdir} -lpord)
mpif90 -fPIC -shared -Wl,${all_load} libmumps_common.a ${libs[@]} -Wl,${noall_load} ${extra[@]} -o libmumps_common.${dlext}
cp libmumps_common.${dlext} ${libdir}

libs+=(-lmumps_common)
for libname in cmumps dmumps smumps zmumps
do
  mpif90 -fPIC -shared -Wl,${all_load} lib${libname}.a ${libs[@]} -Wl,${noall_load} ${extra[@]} -o lib${libname}.${dlext}
done
cp *.${dlext} ${libdir}
cd ..

cp include/* ${prefix}/include
"""

# OpenMPI and MPICH are not precompiled for Windows
# SCALAPACK doesn't build on PowerPC
platforms = expand_gfortran_versions(filter!(p -> !Sys.iswindows(p) && arch(p) != "powerpc64le", supported_platforms()))

# The products that we will ensure are always built
products = [
    LibraryProduct("libsmumps", :libsmumps),
    LibraryProduct("libdmumps", :libdmumps),
    LibraryProduct("libcmumps", :libcmumps),
    LibraryProduct("libzmumps", :libzmumps),
]

# Dependencies that must be installed before this package can be built
dependencies = [
    Dependency("CompilerSupportLibraries_jll"),
    Dependency("MPICH_jll"),
    Dependency("METIS_jll"),
    Dependency("PARMETIS_jll"),
    Dependency("SCALAPACK_jll"),
    Dependency("OpenBLAS_jll", v"0.3.9"),
]

# Build the tarballs
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies)
