#include "mex.h"
#include <string.h>

void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {
  /* Get Matlab sparse matrix CSC format.

     [j,i,ind,v] = findsp(a)
     j = column start indices (1,ncols+1)
     i = row indices (1,nnz)
     ind = non-zero indices (1,nnz)
     v = non-zero values (1,nnz)

  */

  if (nrhs != 1 || !mxIsSparse(prhs[0]) || !mxIsDouble(prhs[0]))
    mexErrMsgTxt("Expecting a real sparse matrix as input.");


  /* Column index vector (size ncols+1) with last entry equal to nnz. */
  const mwSize ncols = mxGetN(prhs[0]);
  const mwIndex *jc = mxGetJc(prhs[0]);
  if (sizeof(mwIndex) != 8)
    mexErrMsgTxt("findsp requires a 64-bit mwIndex build.");
  if (nlhs >= 1) {
    const mwSize dims[] = {1, ncols+1};
    plhs[0] = mxCreateNumericArray(2, dims, mxUINT64_CLASS, mxREAL);
    mwIndex *p = (mwIndex *) mxGetData(plhs[0]);
    /* for (mwSize i = 0; i < ncols+1; i++) { */
    /*   p[i] = *(jc + i); */
    /* } */
    memcpy(p, jc, (ncols+1)*sizeof(mwIndex));
  }

  /* Row index vector */
  const mwIndex nnz = *(jc + ncols);
  const mwIndex *ir = mxGetIr(prhs[0]);
  if (nlhs >= 2) {
    const mwSize dims[] = {1, nnz};
    plhs[1] = mxCreateNumericArray(2, dims, mxUINT64_CLASS, mxREAL);
    mwIndex *p = (mwIndex *) mxGetData(plhs[1]);
    /* for (mwSize i = 0; i < nnz; i++) { */
    /*   p[i] = *(ir + i); */
    /* } */
    memcpy(p, ir, nnz*sizeof(mwIndex));
  }

  /* Index vector */
  if (nlhs >= 3) {
    const mwSize dims[] = {1, nnz};
    plhs[2] = mxCreateNumericArray(2, dims, mxUINT64_CLASS, mxREAL);
    mwIndex *p = (mwIndex *) mxGetData(plhs[2]);
    mwSize i = 0;
    const mwSize nrows = mxGetM(prhs[0]);
    for (mwSize icol = 0; icol < ncols; icol++) {
      for (mwSize ia = *(jc+icol); ia < *(jc+icol+1); ia++) {
        p[i++] = *(ir + ia) + icol*nrows;
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
    memcpy(p, avals, nnz*sizeof(double));
  }

}
