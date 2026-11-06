#include "mex.h"
#include <stddef.h>

#ifdef _OPENMP
#include <omp.h>
#endif

#if defined(__GNUC__)
#define restrict __restrict__
#elif defined(__INTEL_COMPILER)
#define restrict restrict
#elif defined(_MSC_VER)
#define restrict __restrict
#endif

/** spsetd.c - Diagonalize selected rows in sparse matrix

    B = SPSETD( A, I ) Sets non-diagonal entries of rows I in sparse
    matrix A to zero, and diagonal entries to 1. A is copied before it
    is modified, and zero entries are not removed from B. Throws error
    if not all diagonal entries I are found in A.

    To compile with visual studio:
    1. mex eindarr.c COMPFLAGS="$COMPFLAGS /openmp /MT"
    2. include vcomp140.dll with redistribution

    J.S. Hysing 2207010.
    Copyright 2013-2022 Precise Simulation, Ltd.
*/

void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {

  if (nrhs != 2)
    mexErrMsgTxt("Expecting two input arguments.");
  if (nlhs != 1)
    mexErrMsgTxt("Expecting one output argument.");

  if (!mxIsSparse(prhs[0]) || !mxIsDouble(prhs[0]) || mxIsComplex(prhs[0]))
    mexErrMsgTxt("Expecting real sparse double matrix as first input.");

  if (mxIsSparse(prhs[1]) || !mxIsDouble(prhs[1]) || mxIsComplex(prhs[1]))
    mexErrMsgTxt("Expecting real full double array as second input.");


  /* Sparse matrix A.  MEX inputs are MATLAB-owned and must not be mutated. */
  plhs[0] = mxDuplicateArray(prhs[0]);
  mxArray *a = plhs[0];
  const mwIndex *restrict jca = mxGetJc(a);
  const mwIndex *restrict ira = mxGetIr(a);
  const mwSize nrows = mxGetM(a);
  const mwSize ncols = mxGetN(a);
  double *restrict pa = mxGetPr(a);

  /* Row pointers */
  mwIndex i, ii;
  int nerr = 0;
  const double *restrict rp = (double *)mxGetData(prhs[1]);
  const mwSize nrp = mxGetNumberOfElements(prhs[1]);
  int8_T* indrows = mxCalloc(nrows, sizeof(int8_T));
  int8_T* founddiag = mxCalloc(nrows, sizeof(int8_T));
  for (ii = 0; ii < nrp; ++ii) {
    const double row = rp[ii];
    if (row >= 1.0 && row <= (double)nrows &&
        row == (double)(mwIndex)row) {
      i = (mwIndex)row - 1;
      indrows[i] = 1;
    } else {
      nerr += 1;
      break;
    }
  }

  if (nerr > 0) {
    mxFree(founddiag);
    mxFree(indrows);
    mexErrMsgTxt("Row indices out of bounds.");
  }

  /* Null rows and set diagonal entry */
  ptrdiff_t col;
#pragma omp parallel for private(i,ii)
  for (col = 0; col < (ptrdiff_t)ncols; ++col) {   // column
    const mwIndex j = (mwIndex)col;
    /* printf("j = %d, jca[j] = %d\n", j, jca[j]); */
    for (ii = jca[j]; ii < jca[j+1]; ++ii) {
      i = ira[ii];   // row
      /* printf("ii = %d, i = %d %d\n", ii, i, indrows[i]); */
      if (indrows[i]) {
        if (i == j) {
          pa[ii] = 1.;
          founddiag[i] = 1;
        } else {
          pa[ii] = 0.;
        }
      }
    }
  }

  ptrdiff_t row;
#pragma omp parallel for reduction(+:nerr)
  for (row = 0; row < (ptrdiff_t)nrows; ++row) {
    if (indrows[row] && !founddiag[row]) {
      nerr += 1;
#ifndef _OPENMP
      break;
#endif
    }
  }

  mxFree(founddiag);
  mxFree(indrows);
  if (nerr > 0)
    mexErrMsgTxt("Requested row does not contain a diagonal entry.");

}
