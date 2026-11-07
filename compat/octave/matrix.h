#ifndef FEATOOL_OCTAVE_MATRIX_COMPAT_H
#define FEATOOL_OCTAVE_MATRIX_COMPAT_H

/*
 * MATLAB ships matrix.h as part of the MEX C API.  The imported FEATool
 * sources include it after mex.h, but GNU Octave either omits matrix.h or
 * exposes a C++-only header under that name depending on the release.
 * Octave's mex.h already provides the matrix API needed by these sources, so
 * this compatibility shim is intentionally empty.
 */

#endif
