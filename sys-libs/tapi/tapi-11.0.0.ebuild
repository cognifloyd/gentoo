# Copyright 1999-2017 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit cmake llvm llvm.org

LLVM_COMPONENTS=( clang )
llvm.org_set_globals

# Apple version numbers are based on LLVM version numbers
# so downloading tapi 1100.* aligns with LLVM 11.0.0.
# TAPI also has another version: TAPI_FULL_VERSION is 2.0.0.
# The ebuild uses the LLVM version to simplify using llvm.org.eclass
TAPI_INTERNAL_PV="2.0.0"
TAPI_PV="1100.0.11"
TAPI_P="${PN}-${TAPI_PV}"
SRC_URI+=" https://opensource.apple.com/tarballs/${PN}/${TAPI_P}.tar.gz"

# cognifloyd:
#	available:
# 		EPREFIX/usr/lib/llvm/11/bin/llvm-tblgen
#	missing:
#		clang-tblgen
# How do I place clang and tapi sources?
# TODO: maybe instead of build clang-tblgen here, modify the clang ebuild so it installs clang-tblgen.

DESCRIPTION="Text-based Application Programming Interface"
HOMEPAGE="https://opensource.apple.com/source/tapi"

LICENSE="|| ( UoI-NCSA MIT )"
SLOT="0"
KEYWORDS="~x64-macos ~x86-macos"

DEPEND="sys-devel/llvm:=
	sys-devel/clang:="
RDEPEND="${DEPEND}"

DOCS=( Readme.md )

CLANG_S="${WORKDIR}/${LLVM_COMPONENTS[0]}"
TAPI_S="${WORKDIR}/${TAPI_P}"
# fix llvm.org changing the dir
S="${TAPI_S}"

# extra parent dir for relative CLANG_RESOURCE_DIR access
TAPI_BUILD_DIR="${WORKDIR}/x/y/tapi"
CLANG_BUILD_DIR="${WORKDIR}/x/y/clang"

src_prepare() { 
	mkdir -p "${TAPI_BUILD_DIR}" "${CLANG_BUILD_DIR}" || die

	cd "${CLANG_S}" || die
	S="${CLANG_S}" \
		BUILD_DIR="${CLANG_BUILD_DIR}" \
		llvm.org_src_prepare || die

	cd "${TAPI_S}" || die
	# Allow all clients to link against the library, not just ld.
	# Main reason: Our ld is called ld64 when we link it.
	sed -i -e 's/ -allowable_client ld//' tools/libtapi/CMakeLists.txt || die
	eapply "${FILESDIR}"/${PN}-11.0.0-clang-inputkind-to-language.patch
	eapply "${FILESDIR}"/${PN}-11.0.0-cxx-std-make-unique.patch
	eapply "${FILESDIR}"/${PN}-11.0.0-explicit-stringref-to-std-string-conversion.patch
	eapply "${FILESDIR}"/${PN}-11.0.0-filemanager-interface-change.patch
	eapply "${FILESDIR}"/${PN}-11.0.0-standalone.patch

	S="${TAPI_S}" \
		BUILD_DIR="${TAPI_BUILD_DIR}" \
		llvm.org_src_prepare || die
}

get_distribution_components() {
	local sep=${1-;}

	# source paths are in cmake/caches
	local out=(
		# in both apple-tapi.cmake tapi-defaults.cmake
		tapi-headers
		libtapi
		tapi-clang-headers
		tapi

		# only in tapi-defaults.cmake
		tapi-run

		# only in apple-tapi.cmake
		tapi-configs
		tapi-api-verifier
	)

	# in both apple-tapi and tapi-defaults
	#use doc && out+=(
	#	tapi-docs
	#)

	printf "%s${sep}" "${out[@]}"
}

src_configure() {
	# configure clang for tablegen build
	local mycmakeargs=(
		# shared libs cause all kinds of problems and we don't need them just
		# to run tblgen a couple of times
		-DBUILD_SHARED_LIBS=OFF
		# these are not propagated reliably, so redefine them
		-DLLVM_ENABLE_EH=ON
		-DLLVM_ENABLE_RTTI=ON
	)

	cd "${CLANG_S}" || die
	CMAKE_USE_DIR="${CLANG_S}" \
		BUILD_DIR="${CLANG_BUILD_DIR}" \
		cmake_src_configure || die

	# cmake/caches/apple-tapi.cmake
	#set(LLVM_DISTRIBUTION_COMPONENTS
	#  CACHE STRING "" FORCE)
	# cmake/caches/tapi-defaults.cmake

	local llvm_prefix=$(get_llvm_prefix)

	local mycmakeargs=(
		-DLLVM_TABLEGEN_EXE="${llvm_prefix}"/bin/llvm-tblgen
		# use tblgens from LLVM build directory directly. They generate source
		# from description files. Therefore it shouldn't matter if they
		# match up with the installed LLVM.
	#	-DLLVM_TABLEGEN_EXE="${LLVM_BUILD}"/bin/llvm-tblgen
	#	-DCLANG_TABLEGEN_EXE="${LLVM_BUILD}"/bin/clang-tblgen
		-DCLANG_TABLEGEN_EXE="${CLANG_BUILD_DIR}"/bin/clang-tblgen
		# pull in includes and libs from ObjCMetadata's temporary install root
	#	-DOBJCMETADATA_INCLUDE_DIRS="${OBJCMD_ROOT}"/include
	#	-DOBJCMETADATA_LIBRARY_DIRS="${OBJCMD_ROOT}"/lib

		# based on defaults in cmake/caches/apple-tapi.cmake
		#-DLLVM_ENABLE_PROJECTS="clang;tapi"

		-DLLVM_ENABLE_ZLIB=OFF
		-DLLVM_ENABLE_TERMINFO=OFF
		-DLLVM_REQUIRES_RTTI=OFF
		-DLLVM_INCLUDE_DOCS=OFF
		-DLLVM_INCLUDE_TESTS=OFF
		-DTAPI_INCLUDE_DOCS=OFF # apple enables this

		# These are not used by TAPI configure
		#-DLLVM_ENABLE_TIMESTAMPS=OFF
		#-DLLVM_ENABLE_LIBCXX=ON
		#-DLLVM_ENABLE_CRASH_OVERRIDES=OFF
		#-DLLVM_INCLUDE_EXAMPLES=OFF
		#-DLLVM_BUILD_TOOLS=OFF
		#-DLLVM_BUILD_RUNTIME=OFF
		#-DCLANG_ENABLE_ARCMT=OFF
		#-DCLANG_ENABLE_STATIC_ANALYZER=OFF
		#-DLLVM_ENABLE_LTO=OFF

		-DLLVM_DISTRIBUTION_COMPONENTS=$(get_distribution_components)
	)

	cd "${TAPI_S}" || die
	CMAKE_USE_DIR="${TAPI_S}" \
		BUILD_DIR="${TAPI_BUILD_DIR}" \
	       	cmake_src_configure || die
}

src_compile() {
	cd "${CLANG_S}" || die
	CMAKE_USE_DIR="${CLANG_S}" \
		BUILD_DIR="${CLANG_BUILD_DIR}" \
		cmake_src_compile clang-tblgen

	cd "${TAPI_S}" || die
	CMAKE_USE_DIR="${TAPI_S}" \
		BUILD_DIR="${TAPI_BUILD_DIR}" \
		cmake_src_compile
}
