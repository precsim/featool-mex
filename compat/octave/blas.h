#ifndef FEATOOL_OCTAVE_BLAS_COMPAT_H
#define FEATOOL_OCTAVE_BLAS_COMPAT_H

/*
 * The imported FEATool MEX sources include MATLAB's blas.h but do not call
 * BLAS functions. GNU Octave does not ship that MATLAB compatibility header.
 * Supplying an empty header on the Octave include path preserves src/ exactly
 * while allowing the original sources to compile with mkoctfile.
 */

#endif
