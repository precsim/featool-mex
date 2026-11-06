#include "mex.h"
#include <stddef.h>
#include <stdlib.h>

#ifdef _OPENMP
#include <omp.h>
#endif

#if defined(__GNUC__)
#define restrict __restrict__
#elif defined(__INTEL_COMPILER)
#define restrict __restrict
#elif defined(_MSC_VER)
#define restrict __restrict
#endif

/** spsetd.c - Diagonalize selected rows in sparse matrix

    B = SPSETD( A, I ) Sets non-diagonal entries of rows I in sparse
    matrix A to zero, and diagonal entries to 1. A is copied before it
    is modified, and zero entries are not removed from B. Throws error
    if not all diagonal entries I are found in A.

    To compile with visual studio:
    1. mex spsetd.c COMPFLAGS="$COMPFLAGS /openmp /MT"
    2. include vcomp140.dll with redistribution

    J.S. Hysing 2207010.
    Copyright 2013-2022 Precise Simulation, Ltd.
*/

int compare_mwindex(const void *a, const void *b) {
  const mwIndex ia = *(const mwIndex *)a;
  const mwIndex ib = *(const mwIndex *)b;
  return (ia > ib) - (ia < ib);
}

int find_selected_row(const mwIndex *restrict rows, const mwSize nrows,
                      const mwIndex target, mwSize *position) {
  mwSize lo = 0;
  mwSize hi = nrows;
  while (lo < hi) {
    const mwSize mid = lo + (hi - lo)/2;
    if (rows[mid] < target)
      lo = mid + 1;
    else
      hi = mid;
  }
  if (lo < nrows && rows[lo] == target) {
    *position = lo;
    return 1;
  }
  return 0;
}

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

  /* Selected rows. Keep storage proportional to the selection, not nrows. */
  const double *restrict rp = (double *)mxGetData(prhs[1]);
  const mwSize nrp = mxGetNumberOfElements(prhs[1]);
  if (nrp == 0)
    return;

  mwIndex *restrict rows = mxCalloc(nrp, sizeof(mwIndex));
  mwSize k;
  for (k = 0; k < nrp; ++k) {
    const double row = rp[k];
    if (row >= 1.0 && row <= (double)nrows &&
        row == (double)(mwIndex)row) {
      rows[k] = (mwIndex)row - 1;
    } else {
      mxFree(rows);
      mexErrMsgTxt("Row indices out of bounds.");
    }
  }

  qsort(rows, nrp, sizeof(mwIndex), compare_mwindex);
  mwSize nsel = 1;
  for (k = 1; k < nrp; ++k) {
    if (rows[k] != rows[nsel-1])
      rows[nsel++] = rows[k];
  }
  int8_T *restrict founddiag = mxCalloc(nsel, sizeof(int8_T));

  /* Null rows and set diagonal entry */
  ptrdiff_t col;
#pragma omp parallel for
  for (col = 0; col < (ptrdiff_t)ncols; ++col) {   // column
    const mwIndex j = (mwIndex)col;
    mwIndex ii;
    for (ii = jca[j]; ii < jca[j+1]; ++ii) {
      const mwIndex i = ira[ii];   // row
      mwSize selected_pos;
      if (find_selected_row(rows, nsel, i, &selected_pos)) {
        if (i == j) {
          pa[ii] = 1.;
          founddiag[selected_pos] = 1;
        } else {
          pa[ii] = 0.;
        }
      }
    }
  }

  for (k = 0; k < nsel; ++k) {
    if (!founddiag[k]) {
      mxFree(founddiag);
      mxFree(rows);
      mexErrMsgTxt("Requested row does not contain a diagonal entry.");
    }
  }

  mxFree(founddiag);
  mxFree(rows);

}
