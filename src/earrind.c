#include "mex.h"
#include <stddef.h>

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

/** earrind.c - Extract indexed values from array

    PC = EARRIND( P, C, X ) Extracts values PC from (row) array P with
    indexes C. C are indices to rows in P, or if C = [i1,i2] extracts
    from rows i1 to i2. With optional X given, returns P(C,:)*X(:).
    A scalar X is broadcast to all columns; otherwise numel(X) must equal
    size(P,2).

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

void validate_indices(const double *restrict ind, const mwSize n, const mwSize limit) {
  mwSize i;
  for (i = 0; i < n; ++i) {
    const double value = ind[i];
    if (!(value >= 1.0 && value <= (double)limit &&
          value == (double)(mwIndex)value))
      mexErrMsgTxt("Index values must be finite positive integers within array bounds.");
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
  const mwSize mc = mxGetM(prhs[1]);
  const mwSize cc = mxGetN(prhs[1]);
  const mwSize nind = mxGetNumberOfElements(prhs[1]);
  if (!(mc == 1 || cc == 1))
    mexErrMsgTxt("Second argument must be an index vector.");
  mwSize nc = nind;
  mwIndex i1 = 0;
  int use_range = 0;
  if (nind == 2) {
    mwIndex i2;
    validate_indices(c, nind, mp);
    i1 = (mwIndex)c[0] - 1;
    i2 = (mwIndex)c[1] - 1;
    if (i2 < i1)
      mexErrMsgTxt("Range end must not precede range start.");
    nc = (mwSize)(i2 - i1 + 1);
    use_range = 1;
  } else {
    validate_indices(c, nind, mp);
  }


  if (nrhs == 2) {
    const mwSize dims[2] = {nc, np};
    plhs[0] = mxCreateNumericArray(2, dims, mxDOUBLE_CLASS, mxREAL);
    if (nc == 0)
      return;
    double* pc = (double *)mxGetData(plhs[0]);

    if (use_range) {
      mwSize j;
      for (j = 0; j < np; j++) {
        const mwSize off_p  = j*mp + (mwSize)i1;
        const mwSize off_pc = j*nc;
        dcopy(p + off_p, pc + off_pc, nc);
      }

    } else {   // Use indices c
      mwSize j;
      for (j = 0; j < np; j++) {
        const mwSize off_p  = j*mp;
        const mwSize off_pc = j*nc;

        dcopy_dind(p + off_p, pc + off_pc, c, nc);
      }
    }

  } else {   // Scale with x and sum rows
    const double* x = (double *)mxGetData(prhs[2]);
    const mwSize nx = mxGetNumberOfElements(prhs[2]);
    if (!(nx == 1 || nx == np))
      mexErrMsgTxt("Third argument must be scalar or contain one value for each column of the first input.");

    const mwSize dims[2] = {nc, 1};
    plhs[0] = mxCreateNumericArray(2, dims, mxDOUBLE_CLASS, mxREAL);
    if (nc == 0)
      return;
    double* pc = (double *)mxGetData(plhs[0]);

    if (use_range) {
      mwSize j;
      for (j = 0; j < np; j++) {
        const mwSize off_p = j*mp + (mwSize)i1;
        const double xj = nx == 1 ? x[0] : x[j];
        dsumx(p + off_p, pc, nc, xj);
      }

    } else {   // Use indices c
      mwSize j;
      for (j = 0; j < np; j++) {
        const mwSize off_p = j*mp;
        const double xj = nx == 1 ? x[0] : x[j];
        dsumx_dind(p + off_p, pc, c, nc, xj);
      }
    }

  }

}
