#include "mex.h"
#include <stdint.h>
#include <string.h>

void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {
  /* Get Matlab sparse matrix CSC format.

     [j,i,ind,v] = findsp(a)
     j = column start indices (1,ncols+1)
     i = row indices (1,nnz)
     ind = non-zero indices (1,nnz)
     v = non-zero values (1,nnz)

  */

  if (nlhs > 4)
    mexErrMsgTxt("findsp supports at most four output arguments.");

  if (nrhs != 1 || !mxIsSparse(prhs[0]) || !mxIsDouble(prhs[0]) ||
      mxIsComplex(prhs[0]))
    mexErrMsgTxt("Expecting a real sparse matrix as input.");


  /* Column index vector (size ncols+1) with last entry equal to nnz. */
  const mwSize ncols = mxGetN(prhs[0]);
  const mwIndex *jc = mxGetJc(prhs[0]);
  if (sizeof(mwIndex) != 8)
    mexErrMsgTxt("findsp requires a 64-bit mwIndex build.");
  if (nlhs >= 1) {
    const mwSize dims[] = {1, ncols+1};
    plhs[0] = mxCreateNumericArray(2, dims, mxUINT64_CLASS, mxREAL);
    uint64_t *p = (uint64_t *) mxGetData(plhs[0]);
    /* for (mwSize i = 0; i < ncols+1; i++) { */
    /*   p[i] = *(jc + i); */
    /* } */
    memcpy(p, jc, (ncols+1)*sizeof(uint64_t));
  }

  /* Row index vector */
  const mwIndex nnz = *(jc + ncols);
  const mwIndex *ir = mxGetIr(prhs[0]);
  if (nlhs >= 2) {
    const mwSize dims[] = {1, nnz};
    plhs[1] = mxCreateNumericArray(2, dims, mxUINT64_CLASS, mxREAL);
    uint64_t *p = (uint64_t *) mxGetData(plhs[1]);
    /* for (mwSize i = 0; i < nnz; i++) { */
    /*   p[i] = *(ir + i); */
    /* } */
    if (nnz != 0)
      memcpy(p, ir, nnz*sizeof(uint64_t));
  }

  /* Index vector */
  if (nlhs >= 3) {
    const mwSize dims[] = {1, nnz};
    plhs[2] = mxCreateNumericArray(2, dims, mxUINT64_CLASS, mxREAL);
    uint64_t *p = (uint64_t *) mxGetData(plhs[2]);
    mwSize i = 0;
    const mwSize nrows = mxGetM(prhs[0]);
    for (mwSize icol = 0; icol < ncols; icol++) {
      for (mwSize ia = *(jc+icol); ia < *(jc+icol+1); ia++) {
        const uint64_t row = (uint64_t)*(ir + ia);
        const uint64_t col = (uint64_t)icol;
        const uint64_t rows = (uint64_t)nrows;
        if (rows != 0 && col > (UINT64_MAX - row)/rows)
          mexErrMsgTxt("Linear index exceeds the uint64 range.");
        p[i++] = row + col*rows;
      }
    }
  }

  /* Value vector */
  if (nlhs >= 4) {
    double *avals = mxGetPr(prhs[0]);
    plhs[3] = mxCreateDoubleMatrix(1, nnz, mxREAL);
    double *p = mxGetPr(plhs[3]);
    /* for (mwSize i = 0; i < nnz; i++) { */
    /*   p[i] = *(avals + i); */
    /* } */
    if (nnz != 0)
      memcpy(p, avals, nnz*sizeof(double));
  }

}
