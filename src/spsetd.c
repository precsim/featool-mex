#include "mex.h"
#include "matrix.h"

#ifdef _OPENMP
#include <omp.h>
#endif

#ifdef __GNUC__
#define restrict __restrict__
#elif __INTEL_COMPILER
#define restrict restrict
#endif

/** spsetd.c - Diagonalize selected rows in sparse matrix

    SPSETD( A, I ) Sets non-diagonal entries of rows I in sparse
    matrix A to zero, and diagonal entries to 1. A is updated in-place
    without safe copying, and zero entries are not removed from
    matrix. Throws error if not all diagonal entries I are found in A.

    To compile with visual studio:
    1. mex eindarr.c COMPFLAGS="$COMPFLAGS /openmp /MT"
    2. include vcomp140.dll with redistribution

    J.S. Hysing 2207010.
    Copyright 2013-2022 Precise Simulation, Ltd.
*/

void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {

  if (nrhs != 2)
    mexErrMsgTxt("Expecting two input arguments.");

  if (!mxIsSparse(prhs[0]) || !mxIsDouble(prhs[0]))
    mexErrMsgTxt("Expecting sparse double matrix as first input.");

  if (mxIsSparse(prhs[1]) || !mxIsDouble(prhs[1]))
    mexErrMsgTxt("Expecting full double array as second input.");


  /* Sparse matrix A */
  const mwSize *restrict jca = mxGetJc(prhs[0]);
  const mwSize *restrict ira = mxGetIr(prhs[0]);
  const mwSize ncols = mxGetN(prhs[0]);
  const mwSize na = *(jca + ncols);
  double *restrict pa = (double *)mxGetData(prhs[0]);
  if (na < 1) {return;}

  /* Row pointers */
  int i, ii, j, nerr = 0;
  const double *restrict rp = (double *)mxGetData(prhs[1]);
  const mwSize nrp = mxGetNumberOfElements(prhs[1]);
  int8_T* indrows = mxCalloc(na, sizeof(int8_T));
#pragma omp parallel for private(i,ii) reduction(+:nerr)
  for (ii = 0; ii < nrp; ++ii) {
    i = (int)rp[ii];
    if (i >= 1 && i <= na) {
      indrows[i-1] = -1;
    } else {
      nerr += 1;
#ifndef _OPENMP
      break;
#endif
    }
  }

  if (nerr > 0)
    mexErrMsgTxt("Row indices out of bounds.");

  /* Null rows and set diagonal entry */
#pragma omp parallel for private(i,ii,j)
  for (j = 0; j < ncols; ++j) {   // column
    /* printf("j = %d, jca[j] = %d\n", j, jca[j]); */
    for (ii = jca[j]; ii < jca[j+1]; ++ii) {
      i = ira[ii];   // row
      /* printf("ii = %d, i = %d %d\n", ii, i, indrows[i]); */
      if (indrows[i] != 0) {
        if (i == j) {
          pa[ii] = 1.;
          indrows[i] = 1;
        } else {
          pa[ii] = 0.;
        }
      }
    }
  }

#pragma omp parallel for private(i) reduction(+:nerr)
  for (i = 0; i < na; ++i) {
    if (indrows[i] < 0) {
      nerr += 1;
#ifndef _OPENMP
      break;
#endif
    }
  }

  mxFree(indrows);
  if (nerr > 0)
    mexErrMsgTxt("Row entires found not present i A.");

}
