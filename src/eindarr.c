#include <stdint.h>
#include "mex.h"

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

#if defined(__GNUC__)
#define POMP _Pragma( "omp parallel for private(i)" )
#elif defined(__INTEL_COMPILER) || defined(_MSC_VER)
#define POMP __pragma( omp parallel for private(i) )
#endif

/** eindarr.c - Extract values from indexed array

    PC = EINDARR( P, C ) Extracts values PC from array P with indexes C.

    P can be a row or column vector of double or single type, in which
    case the output PC is equivalent to P(C). Alternatively, if P is a
    two dimensional array, PC is numel(C) x min(size(P)), where each
    row in P is copied to PC from the indices in C.

    Note! No checks are performed on C that indices to P are valid.

    To compile with visual studio or intel compiler:
      1. change to __pragma( omp parallel for )
      2. mex eindarr.c COMPFLAGS="$COMPFLAGS /openmp /MT /Qrestrict"
      3. include vcomp140.dll/libiomp5md.dll with redistribution

    J.S. Hysing 220705.
    Copyright 2013-2022 Precise Simulation, Ltd.
*/

/*------------------------------------------------------------------------*/
#define FUNC(npc, index_stride, outer_stride, pc, p, c_Type, c) { \
    const mwSize nc = mxGetNumberOfElements(prhs[1]);              \
    const c_Type *restrict c = (c_Type *)mxGetData(prhs[1]);       \
    for (mwSize j = 0; j < npc; j++) {                             \
      int i;                                                     \
      POMP                                                       \
      for (i = 0; i < nc; i++) {                                 \
        const mwSize ci = (mwSize)c[i];                           \
        pc[i] = p[(ci-1)*index_stride + j*outer_stride];          \
      }                                                          \
      pc += nc;                                                   \
    }                                                            \
  }

/*------------------------------------------------------------------------*/
bool mx_IsInt(const mxArray *array_ptr) {
  const int id = mxGetClassID(array_ptr);
  return (id == mxINT8_CLASS   || id == mxINT16_CLASS  ||
          id == mxINT32_CLASS  || id == mxINT64_CLASS  ||
          id == mxUINT8_CLASS  || id == mxUINT16_CLASS ||
          id == mxUINT32_CLASS || id == mxUINT64_CLASS);
}


void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {

  if (nrhs != 2 )
    mexErrMsgTxt("Expecting two input arguments.");

  if(mxIsSparse(prhs[0]) || mxIsComplex(prhs[0]) ||
     !(mxIsDouble(prhs[0]) || mxIsSingle(prhs[0])))
    mexErrMsgTxt("Expecting non-sparse double or single array as first input.");

  if(mxIsSparse(prhs[1]) || mxIsComplex(prhs[1]) ||
     !(mxIsDouble(prhs[1]) || mxIsSingle(prhs[1]) || mx_IsInt(prhs[1])))
    mexErrMsgTxt("Expecting non-sparse double, single, or integer array as second input.");

  if (nlhs != 1 )
    mexErrMsgTxt("Expecting one output argument.");

  const mwSize mp = mxGetM(prhs[0]);   // rows
  const mwSize np = mxGetN(prhs[0]);   // cols
  const mwSize mc = mxGetM(prhs[1]);
  const mwSize nc = mxGetN(prhs[1]);
  const mwSize ndim = 2;
  mwSize dims[2];
  mwSize npc = 1;
  mwSize index_stride = 1;
  mwSize outer_stride = 0;
  if (mp==1 || np==1) {   // p vector
    dims[0] = mc; dims[1] = nc;
    index_stride = 1;
    outer_stride = 0;
  } else {   // p array
    dims[0] = mc*nc;
    if (mp > np) {   // Row array
      dims[1] = np;
      index_stride = 1;
      outer_stride = mp;
    } else {   // Column array
      dims[1] = mp;
      index_stride = mp;
      outer_stride = 1;
    }
    npc = dims[1];   // Number of cols in output
  }

  const int id = mxGetClassID(prhs[1]);

  if (mxIsSingle(prhs[0])) {
    float *restrict p = (float *)mxGetData(prhs[0]);
    plhs[0] = mxCreateNumericArray(ndim, dims, mxSINGLE_CLASS, mxREAL);
    float *restrict pc = (float *)mxGetData(plhs[0]);

    if      (id == mxDOUBLE_CLASS) {FUNC(npc, index_stride, outer_stride, pc, p, double,   c);}
    else if (id == mxSINGLE_CLASS) {FUNC(npc, index_stride, outer_stride, pc, p, float,    c);}
    else if (id == mxUINT32_CLASS) {FUNC(npc, index_stride, outer_stride, pc, p, uint32_T, c);}
    else if (id == mxUINT16_CLASS) {FUNC(npc, index_stride, outer_stride, pc, p, uint16_T, c);}
    else if (id == mxUINT8_CLASS)  {FUNC(npc, index_stride, outer_stride, pc, p, uint8_T,  c);}
    else if (id == mxUINT64_CLASS) {FUNC(npc, index_stride, outer_stride, pc, p, uint64_t, c);}
    else if (id == mxINT32_CLASS)  {FUNC(npc, index_stride, outer_stride, pc, p, int32_T,  c);}
    else if (id == mxINT16_CLASS)  {FUNC(npc, index_stride, outer_stride, pc, p, int16_T,  c);}
    else if (id == mxINT8_CLASS)   {FUNC(npc, index_stride, outer_stride, pc, p, int8_T,   c);}
    else if (id == mxINT64_CLASS)  {FUNC(npc, index_stride, outer_stride, pc, p, int64_t,  c);}

  } else {   // Double
    double *restrict p = (double *)mxGetData(prhs[0]);
    plhs[0] = mxCreateNumericArray(ndim, dims, mxDOUBLE_CLASS, mxREAL);
    double *restrict pc =(double *)mxGetData(plhs[0]);

    if      (id == mxDOUBLE_CLASS) {FUNC(npc, index_stride, outer_stride, pc, p, double,   c);}
    else if (id == mxSINGLE_CLASS) {FUNC(npc, index_stride, outer_stride, pc, p, float,    c);}
    else if (id == mxUINT32_CLASS) {FUNC(npc, index_stride, outer_stride, pc, p, uint32_T, c);}
    else if (id == mxUINT16_CLASS) {FUNC(npc, index_stride, outer_stride, pc, p, uint16_T, c);}
    else if (id == mxUINT8_CLASS)  {FUNC(npc, index_stride, outer_stride, pc, p, uint8_T,  c);}
    else if (id == mxUINT64_CLASS) {FUNC(npc, index_stride, outer_stride, pc, p, uint64_t, c);}
    else if (id == mxINT32_CLASS)  {FUNC(npc, index_stride, outer_stride, pc, p, int32_T,  c);}
    else if (id == mxINT16_CLASS)  {FUNC(npc, index_stride, outer_stride, pc, p, int16_T,  c);}
    else if (id == mxINT8_CLASS)   {FUNC(npc, index_stride, outer_stride, pc, p, int8_T,   c);}
    else if (id == mxINT64_CLASS)  {FUNC(npc, index_stride, outer_stride, pc, p, int64_t,  c);}

  }

}
