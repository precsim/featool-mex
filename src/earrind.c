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

/** earrind.c - Extract indexed values from array

    PC = EARRIND( P, C, X ) Extracts values PC from (row) array P with
    indexes C. C are indices to rows in P, or if C = [i1,i2] extracts
    from rows i1 to i2. With optional X given, the rows are summed and
    multiplied with X(row_i).

    Note! Few checks are performed on C that indices to P are valid.

    Build with intel compiler:

    mex earrind.c COMPFLAGS="$COMPFLAGS /openmp /MT /Qrestrict"

    J.S. Hysing 220709.
    Copyright 2013-2022 Precise Simulation, Ltd.
*/


void dcopy(const double *restrict p1, double *restrict p2, const mwSize n) {
  ptrdiff_t i;
#pragma omp parallel for private(i)
  for (i = 0; i < (ptrdiff_t)n; i++) {
    p2[i] = p1[i];
  }
}

void dcopy_dind(const double *restrict p1, double *restrict p2, const double *restrict ind, const mwSize n) {
  ptrdiff_t i;
#pragma omp parallel for private(i)
  for (i = 0; i < (ptrdiff_t)n; i++) {
    p2[i] = p1[(mwIndex)ind[i]-1];
  }
}

void dsumx(const double *restrict p1, double *restrict p2, const mwSize n, double x) {
  ptrdiff_t i;
#pragma omp parallel for private(i)
  for (i = 0; i < (ptrdiff_t)n; i++) {
    p2[i] += x * p1[i];
  }
}

void dsumx_dind(const double *restrict p1, double *restrict p2, const double *restrict ind, const mwSize n, double x) {
  ptrdiff_t i;
#pragma omp parallel for private(i)
  for (i = 0; i < (ptrdiff_t)n; i++) {
    p2[i] += x * p1[(mwIndex)ind[i]-1];
  }
}


void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {

  if (nrhs < 2 || nrhs > 3)
    mexErrMsgTxt("Expecting two or three input arguments.");

  if (mxIsSparse(prhs[0]) || mxIsComplex(prhs[0]) || !mxIsDouble(prhs[0]))
    mexErrMsgTxt("Expecting non-sparse double array as first input.");

  if (mxIsSparse(prhs[1]) || mxIsComplex(prhs[1]) || !mxIsDouble(prhs[1]))
    mexErrMsgTxt("Expecting non-sparse double array as second input.");

  if (nrhs == 3 && (mxIsSparse(prhs[2]) || mxIsComplex(prhs[2]) || !mxIsDouble(prhs[2])))
    mexErrMsgTxt("Expecting non-sparse double array as third input.");

  if (nlhs != 1)
    mexErrMsgTxt("Expecting one output argument.");

  const double* p = (double *)mxGetData(prhs[0]);
  const mwSize mp = mxGetM(prhs[0]);   // rows
  const mwSize np = mxGetN(prhs[0]);   // cols

  const double* c = (double *)mxGetData(prhs[1]);
  const int mc = (int)mxGetM(prhs[1]);
  int nc = (int)mxGetN(prhs[1]);
  if (!(mc == 1 || nc==1))
    mexErrMsgTxt("Second argument must be an index vector.");
  int i1 = -1; int i2 = -1;
  if (mc*nc == 2) {
    i1 = (int)c[0] - 1;
    i2 = (int)c[1] - 1;
    if (i1 < 0 || i2 > mp-1 || i2 < i1)
      mexErrMsgTxt("Pointer out of bounds");
    nc = i2 - i1 + 1;
  } else {
    nc = mc*nc;
  }


  if (nrhs == 2) {
    const mwSize dims[2] = {nc, np};
    plhs[0] = mxCreateNumericArray(2, dims, mxDOUBLE_CLASS, mxREAL);
    double* pc = (double *)mxGetData(plhs[0]);

    if (i1 >= 0) {
      for (int j = 0; j < np; j++) {
        int off_p  = j*mp + i1;
        int off_pc = j*nc;
        if (off_p>mp*np-1)
          mexErrMsgTxt("Pointer out of bounds");

        dcopy(p + off_p, pc + off_pc, nc);
      }

    } else {   // Use indices c
      for (int j = 0; j < np; j++) {
        mwSize off_p  = (mwSize)j*mp;
        mwSize off_pc = (mwSize)j*nc;

        dcopy_dind(p + off_p, pc + off_pc, c, nc);
      }
    }

  } else {   // Scale with x and sum rows
    const double* x = (double *)mxGetData(prhs[2]);
    const mwSize nx = mxGetNumberOfElements(prhs[2]);

    const mwSize dims[2] = {nc, 1};
    plhs[0] = mxCreateNumericArray(2, dims, mxDOUBLE_CLASS, mxREAL);
    double* pc = (double *)mxGetData(plhs[0]);

    double xj = 1.;
    if (i1 >= 0) {
      for (int j = 0; j < np; j++) {
        int off_p = j*mp + i1;
        if (off_p>mp*np-1)
          mexErrMsgTxt("Pointer out of bounds");
        if (j < nx) { xj = x[j]; }

        dsumx(p + off_p, pc, nc, xj);
      }

    } else {   // Use indices c
      for (int j = 0; j < np; j++) {
        mwSize off_p = (mwSize)j*mp;
        if (j < nx) { xj = x[j]; }

        dsumx_dind(p + off_p, pc, c, nc, xj);
      }
    }

  }

}
